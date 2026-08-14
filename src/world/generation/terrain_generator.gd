extends RefCounted
class_name TerrainGenerator

var config: WorldConfig

var noise_continentalness: FastNoiseLite
var noise_erosion: FastNoiseLite
var noise_peaks_valleys: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_humidity: FastNoiseLite
var noise_river: FastNoiseLite

var _thread_lake_caches: Dictionary = {}
var _lake_grid_mutex: Mutex = Mutex.new()
var _noise_mutex: Mutex = Mutex.new()
var _thread_noises: Dictionary = {}

# Rivers: wide channel contributes only a fraction of core strength.
# This weight was tuned so wide channels still trigger sand/water and beach
# logic, but don't dominate deep carving or over-widen beaches.
const RIVER_WIDE_WEIGHT: float = 0.42
const LAKE_GRID_CACHE_MAX: int = 1024
const LAKE_GRID_CACHE_KEEP: int = 768
const COPPER_GROWTH_DIRECTIONS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

func _init(p_config: WorldConfig):
	config = p_config
	_thread_lake_caches.clear()
	_lake_grid_mutex = Mutex.new()
	_noise_mutex = Mutex.new()

func _make_noise_set() -> Dictionary:
	var n_cont = FastNoiseLite.new()
	n_cont.seed = config.seed_value + config.continentalness_seed_offset
	n_cont.noise_type = FastNoiseLite.TYPE_PERLIN
	n_cont.frequency = config.continentalness_frequency
	n_cont.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_cont.fractal_octaves = config.continentalness_octaves
	n_cont.fractal_lacunarity = 2.0
	n_cont.fractal_gain = 0.45

	var n_erosion = FastNoiseLite.new()
	n_erosion.seed = config.seed_value + config.erosion_seed_offset
	n_erosion.noise_type = FastNoiseLite.TYPE_PERLIN
	n_erosion.frequency = config.erosion_frequency
	n_erosion.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_erosion.fractal_octaves = config.erosion_octaves
	n_erosion.fractal_lacunarity = 2.0
	n_erosion.fractal_gain = 0.5

	var n_pv = FastNoiseLite.new()
	n_pv.seed = config.seed_value + config.peaks_valleys_seed_offset
	n_pv.noise_type = FastNoiseLite.TYPE_PERLIN
	n_pv.frequency = config.peaks_valleys_frequency
	n_pv.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_pv.fractal_octaves = config.peaks_valleys_octaves
	n_pv.fractal_lacunarity = 2.0
	n_pv.fractal_gain = 0.5

	var n_temp = FastNoiseLite.new()
	n_temp.seed = config.seed_value + config.temperature_seed_offset
	n_temp.noise_type = FastNoiseLite.TYPE_PERLIN
	n_temp.frequency = config.temperature_frequency
	n_temp.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_temp.fractal_octaves = config.temperature_octaves
	n_temp.fractal_lacunarity = 2.0
	n_temp.fractal_gain = 0.5

	var n_hum = FastNoiseLite.new()
	n_hum.seed = config.seed_value + config.humidity_seed_offset
	n_hum.noise_type = FastNoiseLite.TYPE_PERLIN
	n_hum.frequency = config.humidity_frequency
	n_hum.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_hum.fractal_octaves = config.humidity_octaves
	n_hum.fractal_lacunarity = 2.0
	n_hum.fractal_gain = 0.5

	var n_river = FastNoiseLite.new()
	n_river.seed = config.seed_value + config.river_seed_offset
	n_river.noise_type = FastNoiseLite.TYPE_PERLIN
	n_river.frequency = config.river_frequency
	n_river.fractal_octaves = 3
	n_river.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_river.fractal_gain = 0.5

	return {
		"continentalness": n_cont,
		"erosion": n_erosion,
		"peaks_valleys": n_pv,
		"temperature": n_temp,
		"humidity": n_hum,
		"river": n_river,
	}

func _combined_river_factor(core: float, wide: float) -> float:
	return maxf(core, wide * RIVER_WIDE_WEIGHT)

func _get_thread_noises() -> Dictionary:
	var tid = OS.get_thread_caller_id()
	if tid == OS.get_main_thread_id():
		return {
			"continentalness": noise_continentalness,
			"erosion": noise_erosion,
			"peaks_valleys": noise_peaks_valleys,
			"temperature": noise_temperature,
			"humidity": noise_humidity,
			"river": noise_river,
		}
	_noise_mutex.lock()
	if _thread_noises.has(tid):
		var cached = _thread_noises[tid] as Dictionary
		_noise_mutex.unlock()
		return cached
	_noise_mutex.unlock()
	var dict = _make_noise_set()
	_noise_mutex.lock()
	if _thread_noises.has(tid):
		var existing = _thread_noises[tid] as Dictionary
		_noise_mutex.unlock()
		return existing
	_thread_noises[tid] = dict
	_noise_mutex.unlock()
	return dict


func setup_noises():
	var dict = _make_noise_set()
	noise_continentalness = dict["continentalness"]
	noise_erosion = dict["erosion"]
	noise_peaks_valleys = dict["peaks_valleys"]
	noise_temperature = dict["temperature"]
	noise_humidity = dict["humidity"]
	noise_river = dict["river"]
	_lake_grid_mutex.lock()
	_thread_lake_caches.clear()
	_lake_grid_mutex.unlock()

func _find_closest_biome(params: PackedFloat32Array) -> Biome:
	return config.biome_library.find_closest(params)

# --- CDF flattening ---

func _erf_approx(x: float) -> float:
	var a1: float = 0.254829592
	var a2: float = -0.284496736
	var a3: float = 1.421413741
	var a4: float = -1.453152027
	var a5: float = 1.061405429
	var p: float = 0.3275911
	var sign: float = 1.0
	if x < 0.0:
		sign = -1.0
	x = absf(x)
	var t: float = 1.0 / (1.0 + p * x)
	var y: float = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-x * x)
	return sign * y

func _perlin_to_uniform(n: float) -> float:
	var sigma: float = 0.25
	return clamp(0.5 * (1.0 + _erf_approx(n / (sigma * sqrt(2.0)))), 0.0, 1.0)

func _pv_to_uniform(pv_raw: float) -> float:
	var sigma: float = 0.25
	var one_minus: float = clamp(1.0 - pv_raw, 0.0, 2.0)
	var erf_val: float = _erf_approx(one_minus / (sigma * sqrt(2.0)))
	return clamp(1.0 - erf_val, 0.0, 1.0)

func _raw_params_at(lx: int, lz: int, tn: Dictionary) -> PackedFloat32Array:
	var n_cont_obj = tn.get("continentalness", noise_continentalness)
	var n_er_obj = tn.get("erosion", noise_erosion)
	var n_pv_obj = tn.get("peaks_valleys", noise_peaks_valleys)
	var n_temp_obj = tn.get("temperature", noise_temperature)
	var n_hum_obj = tn.get("humidity", noise_humidity)
	var n_cont_raw: float = 0.0
	var n_er_raw: float = 0.0
	var n_pv_raw: float = 0.0
	var n_temp_raw: float = 0.0
	var n_hum_raw: float = 0.0
	if n_cont_obj != null:
		n_cont_raw = n_cont_obj.get_noise_2d(float(lx), float(lz))
	if n_er_obj != null:
		n_er_raw = n_er_obj.get_noise_2d(float(lx), float(lz))
	if n_pv_obj != null:
		n_pv_raw = n_pv_obj.get_noise_2d(float(lx), float(lz))
	if n_temp_obj != null:
		n_temp_raw = n_temp_obj.get_noise_2d(float(lx), float(lz))
	if n_hum_obj != null:
		n_hum_raw = n_hum_obj.get_noise_2d(float(lx), float(lz))
	var continentalness: float = _perlin_to_uniform(n_cont_raw)
	var erosion: float = _perlin_to_uniform(n_er_raw)
	var pv_raw: float = clamp(1.0 - abs(n_pv_raw), 0.0, 1.0)
	var peaks_valleys: float = _pv_to_uniform(pv_raw)
	var temperature: float = _perlin_to_uniform(n_temp_raw)
	var humidity: float = _perlin_to_uniform(n_hum_raw)
	var arr = PackedFloat32Array()
	arr.resize(5)
	arr[Biome.IDX_CONTINENTALNESS] = continentalness
	arr[Biome.IDX_EROSION] = erosion
	arr[Biome.IDX_PEAKS_VALLEYS] = peaks_valleys
	arr[Biome.IDX_TEMPERATURE] = temperature
	arr[Biome.IDX_HUMIDITY] = humidity
	return arr

func _get_lattice_raw(lx: int, lz: int, tn: Dictionary, cache: Dictionary) -> PackedFloat32Array:
	var key = Vector2i(lx, lz)
	if cache.has(key):
		return cache[key] as PackedFloat32Array
	var raw = _raw_params_at(lx, lz, tn)
	cache[key] = raw
	return raw

func _sample_height_params(x: int, z: int, tn: Dictionary, lattice_cache: Dictionary) -> Vector3:
	var step: int = config.param_lattice_step
	if step <= 1:
		var raw = _raw_params_at(x, z, tn)
		return Vector3(raw[Biome.IDX_CONTINENTALNESS], raw[Biome.IDX_EROSION], raw[Biome.IDX_PEAKS_VALLEYS])
	var x0: int = int(floor(float(x) / float(step))) * step
	var z0: int = int(floor(float(z) / float(step))) * step
	var tx: float = float(x - x0) / float(step)
	var tz: float = float(z - z0) / float(step)
	var c00 = _get_lattice_raw(x0, z0, tn, lattice_cache)
	var c10 = _get_lattice_raw(x0 + step, z0, tn, lattice_cache)
	var c01 = _get_lattice_raw(x0, z0 + step, tn, lattice_cache)
	var c11 = _get_lattice_raw(x0 + step, z0 + step, tn, lattice_cache)
	var out = Vector3.ZERO
	for i in 3:
		var v00 = c00[i]
		var v10 = c10[i]
		var v01 = c01[i]
		var v11 = c11[i]
		var vx0 = lerp(v00, v10, tx)
		var vx1 = lerp(v01, v11, tx)
		out[i] = lerp(vx0, vx1, tz)
	return out

func _generate_lake_cell(gx: int, gz: int) -> Variant:
	var rng_cell = RandomNumberGenerator.new()
	rng_cell.seed = config.seed_value + gx * 73856093 + gz * 19349663 + 99931
	var should_have_lake = rng_cell.randf() <= config.lake_chance_per_cell
	var result = null
	if should_have_lake:
		var grid = config.lake_grid_size
		var cell_origin_x = gx * grid
		var cell_origin_z = gz * grid
		var margin = config.lake_radius_max + 8
		if margin * 2 >= grid:
			margin = grid / 4
		margin = clamp(margin, 5, grid / 3)
		var offset_x = rng_cell.randi_range(margin, grid - margin)
		var offset_z = rng_cell.randi_range(margin, grid - margin)
		var cx = cell_origin_x + offset_x
		var cz = cell_origin_z + offset_z
		var dist_to_origin_sq = float(cx * cx + cz * cz)
		var min_dist = config.meadow_radius + config.lake_min_dist_from_meadow
		if dist_to_origin_sq >= min_dist * min_dist:
			var radius = rng_cell.randi_range(config.lake_radius_min, config.lake_radius_max)
			var depth = config.lake_depth + rng_cell.randi_range(-1, 2)
			depth = clamp(depth, 1, 20)
			result = {"center": Vector2i(cx, cz), "radius": radius, "radius_sq": radius * radius, "depth": depth, "grid": Vector2i(gx, gz)}
	return result

func _get_thread_lake_cache() -> Dictionary:
	var tid = OS.get_thread_caller_id()
	_lake_grid_mutex.lock()
	if not _thread_lake_caches.has(tid):
		_thread_lake_caches[tid] = {}
	var cache = _thread_lake_caches[tid] as Dictionary
	_lake_grid_mutex.unlock()
	return cache

func release_thread_caches(tid: int) -> void:
	_lake_grid_mutex.lock()
	_thread_lake_caches.erase(tid)
	_lake_grid_mutex.unlock()
	_noise_mutex.lock()
	_thread_noises.erase(tid)
	_noise_mutex.unlock()

func _get_lake_for_grid_cell(gx: int, gz: int, lake_cache: Variant) -> Variant:
	if not config.lake_enabled:
		return null
	var cache: Dictionary
	if lake_cache == null:
		cache = _get_thread_lake_cache()
	else:
		cache = lake_cache as Dictionary
	var key = Vector2i(gx, gz)
	if cache.has(key):
		return cache[key]
	var result = _generate_lake_cell(gx, gz)
	cache[key] = result
	if cache.size() > LAKE_GRID_CACHE_MAX:
		var keys = cache.keys()
		var to_remove = cache.size() - LAKE_GRID_CACHE_KEEP
		for i in range(to_remove):
			cache.erase(keys[i])
	return result

func _get_lake_info_fast(x: int, z: int, lake_cache: Variant = null) -> Vector2:
	if not config.lake_enabled:
		return Vector2.ZERO
	var best = 0.0
	var best_depth = 0
	var grid = config.lake_grid_size
	var gx = int(floor(float(x) / float(grid)))
	var gz = int(floor(float(z) / float(grid)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var lake = _get_lake_for_grid_cell(gx + dx, gz + dz, lake_cache)
			if lake == null:
				continue
			var dx_ = x - lake["center"].x
			var dz_ = z - lake["center"].y
			if float(dx_ * dx_ + dz_ * dz_) >= float(lake["radius_sq"]):
				continue
			var dist = sqrt(float(dx_ * dx_ + dz_ * dz_))
			var t = 1.0 - dist / float(lake["radius"])
			var smooth = t * t * (3.0 - 2.0 * t)
			if smooth > best:
				best = smooth
				best_depth = lake["depth"]
				if best > 0.95:
					return Vector2(best, best_depth)
	return Vector2(best, best_depth)

func _apply_lake_carve_with_info(base_h: float, info: Vector2) -> float:
	if not config.lake_enabled:
		return base_h
	var factor = info.x
	if factor <= 0.001:
		return base_h
	var depth = int(info.y)
	var target_h = float(config.water_level) - 1.2 - float(depth) * factor
	target_h = max(target_h, 1.0)
	var blended = lerp(base_h, target_h, factor * config.lake_rim_blend)
	if blended < base_h:
		if factor > 0.7:
			blended = min(blended, float(config.water_level) - 1.0)
		return blended
	return base_h

func _get_river_factors_fast(x: int, z: int, thread_noises: Dictionary) -> Vector2:
	if not config.river_enabled:
		return Vector2.ZERO
	var river_n = thread_noises["river"] as FastNoiseLite
	var erosion_n = thread_noises["erosion"] as FastNoiseLite
	var n = river_n.get_noise_2d(float(x), float(z))
	var abs_n = absf(n)
	var core_thr = 0.09
	var wide_thr = 0.15
	var core_f = 0.0
	var wide_f = 0.0
	if abs_n < wide_thr:
		var tw = 1.0 - abs_n / wide_thr
		wide_f = tw * tw * (3.0 - 2.0 * tw)
	if abs_n < core_thr:
		var tc = 1.0 - abs_n / core_thr
		core_f = tc * tc * (3.0 - 2.0 * tc)
		core_f = pow(core_f, 0.90)
	var n2 = erosion_n.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.06
	if wide_f > 0.0:
		wide_f = clamp(wide_f + n2 * 0.5, 0.0, 1.0)
	if core_f > 0.0:
		core_f = clamp(core_f + n2, 0.0, 1.0)
	var d_center = Vector2(x, z).length()
	if d_center < config.meadow_radius + config.river_min_dist_from_meadow - 5.0:
		var fade = clamp((d_center - (config.meadow_radius - 5.0)) / (config.river_min_dist_from_meadow), 0.0, 1.0)
		wide_f *= fade
		core_f *= fade
	return Vector2(core_f, wide_f)

func _apply_river_carve_with_factors(base_h: float, factors: Vector2) -> float:
	if not config.river_enabled:
		return base_h
	var core = factors.x
	var wide = factors.y
	if core <= 0.001 and wide <= 0.001:
		return base_h
	var h = base_h
	if wide > 0.001:
		var shallow_target = float(config.water_level) + 1.5
		var wide_blend = wide * 0.38
		if base_h > float(config.water_level) + 4.0:
			wide_blend = wide * 0.52
		h = lerp(h, shallow_target, clamp(wide_blend, 0.0, 0.70))
	if core > 0.001:
		var deep_target = float(config.water_level) - 0.5 - float(config.river_depth) * core
		deep_target = max(deep_target, float(config.water_level) - float(config.river_depth) - 1.0)
		deep_target = max(deep_target, 1.0)
		var core_blend = core * 0.88
		h = lerp(h, deep_target, clamp(core_blend, 0.0, 0.90))
	if h < base_h:
		if core > 0.45:
			var target_max = float(config.water_level) - 1.0 - (core - 0.5) * 0.6
			if h > target_max:
				var lerp_strength = clamp((core - 0.45) * 2.2, 0.0, 0.95)
				h = lerp(h, target_max, lerp_strength)
		return h
	return base_h

func _compute_base_height(x: int, z: int, continentalness: float, erosion: float, pv: float) -> float:
	continentalness = clamp(continentalness, 0.0, 1.0)
	erosion = clamp(erosion, 0.0, 1.0)
	pv = clamp(pv, 0.0, 1.0)
	var cont_offset: float = config.sample_spline(continentalness, config.continentalness_curve)
	var amp: float = config.sample_spline(erosion, config.erosion_amplitude_curve)
	amp = clamp(amp, 0.0, 1.0)
	var h: float = config.base_height + cont_offset + pv * amp * config.relief_scale
	var meadow_center = config.get_meadow_center()
	var offset = Vector2(x, z) - meadow_center
	if offset.length_squared() < config.meadow_radius * config.meadow_radius:
		var d_center = offset.length()
		var t = 1.0 - d_center / config.meadow_radius
		h = lerp(h, config.meadow_target_height, t * 0.75)
	return h

func _is_shore(surface_y: int, water_influence: float) -> bool:
	# Callable per surface (once per column top), not per voxel.
	# Keep the `or` as written - do not simplify.
	# Waterline case ahead of influence gate: surface at or below water+1 is shore regardless of influence.
	if surface_y <= config.water_level + config.shore_waterline_margin:
		return true
	if water_influence <= config.shore_influence_min:
		return false
	return water_influence > config.shore_influence_strong or surface_y - config.water_level <= config.shore_height_margin

func compute_column_at_world(x: int, z: int) -> Vector2i:
	if noise_continentalness == null:
		setup_noises()
	var tn = _get_thread_noises()
	var params = _raw_params_at(x, z, tn)
	var base = _compute_base_height(x, z, params[Biome.IDX_CONTINENTALNESS], params[Biome.IDX_EROSION], params[Biome.IDX_PEAKS_VALLEYS])
	var lake_info = _get_lake_info_fast(x, z)
	var river_factors = _get_river_factors_fast(x, z, tn)
	var hf = _apply_lake_carve_with_info(base, lake_info)
	hf = _apply_river_carve_with_factors(hf, river_factors)
	var ih = int(round(clamp(hf, 1.0, float(config.max_height))))
	var rf = _combined_river_factor(river_factors.x, river_factors.y)
	var block_type = _compute_type_with_params(x, z, ih, params, lake_info.x, rf)
	return Vector2i(ih, block_type)

func _compute_type_with_params(x: int, z: int, h: int, params: PackedFloat32Array, lake_factor: float, river_factor: float) -> int:
	return _compute_type_with_biome(x, z, h, _find_closest_biome(params), lake_factor, river_factor)

func _compute_type_with_biome(x: int, z: int, h: int, biome: Biome, lake_factor: float, river_factor: float) -> int:
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var is_lake = lake_factor > 0.01
	var is_river = river_factor > 0.01
	if Vector2(x, z).distance_squared_to(meadow_center) < (meadow_radius - 2.0) * (meadow_radius - 2.0):
		if (is_lake and lake_factor > 0.5 and h <= config.water_level + 1) or (is_river and river_factor > 0.55 and h <= config.water_level + 1):
			return BlockId.Type.SAND
		return BlockId.Type.GRASS
	var water_influence: float = max(lake_factor, river_factor)
	if _is_shore(h, water_influence):
		return biome.shore_block
	return biome.surface_block

func _generate_copper_deposit(
	origin_x: int,
	origin_z: int,
	chunk_size: int,
	size_y: int,
	cache_z: int,
	height_dict: Dictionary,
	cache: PackedInt32Array
) -> Dictionary:
	var deposit: Dictionary = {}
	if not config.copper_deposits_enabled or chunk_size < 6:
		return deposit
	var rng := RandomNumberGenerator.new()
	rng.seed = config.seed_value + origin_x * 73856093 + origin_z * 19349663 + 486187739
	if rng.randf() > config.copper_deposit_chance_per_chunk:
		return deposit

	var seed_pos := Vector3i.ZERO
	var found_seed := false
	for _attempt in range(16):
		var x := rng.randi_range(origin_x + 2, origin_x + chunk_size - 3)
		var z := rng.randi_range(origin_z + 2, origin_z + chunk_size - 3)
		var surface_y := height_dict.get(Vector2i(x, z), -1) as int
		if surface_y <= config.water_level + 1 or surface_y >= size_y:
			continue
		var expose_surface := config.copper_max_surface_blocks > 0 and rng.randf() <= config.copper_surface_exposure_chance
		var y := surface_y if expose_surface else surface_y - rng.randi_range(1, 4)
		if y < 1:
			continue
		seed_pos = Vector3i(x, y, z)
		found_seed = true
		break
	if not found_seed:
		return deposit

	var target_size := rng.randi_range(config.copper_deposit_min_blocks, config.copper_deposit_max_blocks)
	var seed_surface := height_dict[Vector2i(seed_pos.x, seed_pos.z)] as int
	var has_outcrop := seed_pos.y == seed_surface
	var surface_limit := 0
	if has_outcrop:
		surface_limit = mini(config.copper_max_surface_blocks, maxi(1, int(target_size / 5)))
	var surface_count := 1 if has_outcrop else 0
	deposit[seed_pos] = BlockId.Type.COPPER

	var attempts := 0
	var max_attempts := target_size * 400
	while deposit.size() < target_size and attempts < max_attempts:
		attempts += 1
		var positions := deposit.keys()
		var anchor := positions[rng.randi_range(0, positions.size() - 1)] as Vector3i
		var direction := COPPER_GROWTH_DIRECTIONS[rng.randi_range(0, COPPER_GROWTH_DIRECTIONS.size() - 1)]
		var candidate := anchor + direction
		if deposit.has(candidate):
			continue
		if candidate.x < origin_x + 1 or candidate.x >= origin_x + chunk_size - 1:
			continue
		if candidate.z < origin_z + 1 or candidate.z >= origin_z + chunk_size - 1:
			continue
		if candidate.y < 1 or candidate.y >= size_y:
			continue
		var offset := candidate - seed_pos
		if offset.length_squared() > 12:
			continue
		var column_surface := height_dict.get(Vector2i(candidate.x, candidate.z), -1) as int
		if column_surface < candidate.y:
			continue
		var is_surface := candidate.y == column_surface
		if is_surface and (surface_count >= surface_limit or column_surface <= config.water_level):
			continue
		var lx := candidate.x - origin_x + 1
		var lz := candidate.z - origin_z + 1
		var idx := lx * size_y * cache_z + candidate.y * cache_z + lz
		var existing_block := cache[idx]
		if existing_block not in [BlockId.Type.GRASS, BlockId.Type.DIRT, BlockId.Type.SAND, BlockId.Type.STONE]:
			continue
		deposit[candidate] = BlockId.Type.COPPER
		if is_surface:
			surface_count += 1

	if deposit.size() != target_size:
		deposit.clear()
	return deposit

func build_cache_with_generation(
	origin_x: int,
	origin_z: int,
	chunk_size: int,
	max_y: int,
	placed_snap: Dictionary,
	removed_snap: Dictionary,
	existing_tree_snap: Dictionary,
	terrain_only: bool = false,
	existing_copper_snap: Dictionary = {},
	generate_copper: bool = false
) -> Dictionary:
	if noise_continentalness == null:
		setup_noises()

	var thread_noises: Variant = null
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		thread_noises = _get_thread_noises()
	else:
		thread_noises = {
			"continentalness": noise_continentalness,
			"erosion": noise_erosion,
			"peaks_valleys": noise_peaks_valleys,
			"temperature": noise_temperature,
			"humidity": noise_humidity,
			"river": noise_river,
		}
	var tn = thread_noises as Dictionary
	var lake_cache = _get_thread_lake_cache()
	var cs = chunk_size
	var size_y = clamp(max_y, 6, 128)
	var cache_x = cs + 2
	var cache_z = cs + 2

	var ext_min_x = origin_x - 2
	var ext_max_x = origin_x + cs + 1
	var ext_min_z = origin_z - 2
	var ext_max_z = origin_z + cs + 1

	var ext_h: Dictionary = {}
	var ext_lake_info: Dictionary = {}
	var ext_river_factors: Dictionary = {}

	var lattice_cache: Dictionary = {}

	for x in range(ext_min_x, ext_max_x + 1):
		for z in range(ext_min_z, ext_max_z + 1):
			var params = _sample_height_params(x, z, tn, lattice_cache)
			var base = _compute_base_height(x, z, params.x, params.y, params.z)
			var lake_info = _get_lake_info_fast(x, z, lake_cache)
			var river_factors = _get_river_factors_fast(x, z, tn)
			var hf = _apply_lake_carve_with_info(base, lake_info)
			hf = _apply_river_carve_with_factors(hf, river_factors)
			var ih = int(round(clamp(hf, 1.0, float(config.max_height))))
			var key = Vector2i(x, z)
			ext_h[key] = ih
			ext_lake_info[key] = lake_info
			ext_river_factors[key] = river_factors

	var height_dict: Dictionary = {}
	var type_dict: Dictionary = {}
	var max_diff_dict: Dictionary = {}
	var biome_dict: Dictionary = {}

	var step: int = config.param_lattice_step
	var lattice_biome_cache: Dictionary = {}

	for x in range(origin_x - 1, origin_x + cs + 1):
		for z in range(origin_z - 1, origin_z + cs + 1):
			var key = Vector2i(x, z)
			var h = ext_h[key] as int
			height_dict[key] = h
			var lake_info = ext_lake_info[key] as Vector2
			var river_factors = ext_river_factors[key] as Vector2
			var lf = lake_info.x
			var rf = _combined_river_factor(river_factors.x, river_factors.y)
			var max_diff = 0
			var combined = max(lf, rf)
			if combined < 0.35:
				var h0 = h
				var n1 = ext_h[Vector2i(x + 1, z)]
				var n2 = ext_h[Vector2i(x - 1, z)]
				var n3 = ext_h[Vector2i(x, z + 1)]
				var n4 = ext_h[Vector2i(x, z - 1)]
				max_diff = max(abs(n1 - h0), abs(n2 - h0))
				max_diff = max(max_diff, abs(n3 - h0))
				max_diff = max(max_diff, abs(n4 - h0))
			# Biome per lattice cell (4 block resolution) - params already lattice interpolated
			var lx: int = int(floor(float(x) / float(step))) * step
			var lz: int = int(floor(float(z) / float(step))) * step
			var lattice_key = Vector2i(lx, lz)
			var biome: Biome = lattice_biome_cache.get(lattice_key, null) as Biome
			if biome == null:
				var cell_params = _get_lattice_raw(lx, lz, tn, lattice_cache)
				biome = _find_closest_biome(cell_params)
				lattice_biome_cache[lattice_key] = biome
			biome_dict[key] = biome
			type_dict[key] = _compute_type_with_biome(x, z, h, biome, lf, rf)
			max_diff_dict[key] = max_diff

	var out_tree_fast: Dictionary = {}
	var tree_positions: Array = []
	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = config.seed_value + origin_x * 73856093 + origin_z * 19349663
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius

	for x in range(origin_x, origin_x + cs):
		for z in range(origin_z, origin_z + cs):
			var key = Vector2i(x, z)
			var h = height_dict[key] as int
			if h <= config.water_level + 2:
				continue
			var lake_info = ext_lake_info[key] as Vector2
			var river_factors = ext_river_factors[key] as Vector2
			var lf = lake_info.x
			var rf = _combined_river_factor(river_factors.x, river_factors.y)
			if lf > 0.15 or rf > 0.12:
				continue
			var ttype = type_dict[key]
			if ttype != BlockId.Type.GRASS:
				continue
			if Vector2(x, z).distance_squared_to(meadow_center) < (meadow_radius - 2.0) * (meadow_radius - 2.0):
				continue
			var max_diff = max_diff_dict[key] as int
			if max_diff > 1:
				continue
			var biome := biome_dict[key] as Biome
			var biome_density: float = biome.tree_density
			if biome_density <= 0.0:
				continue
			var height_factor = clamp((float(h) - config.base_height) / 6.0, 0.2, 1.0)
			var effective_density = biome_density * (0.6 + height_factor * 0.5)
			# Blend with global config density as soft multiplier to keep user control
			effective_density *= clamp(config.tree_density / 0.012, 0.3, 2.0)
			if chunk_rng.randf() > effective_density:
				continue
			var too_close = false
			for p in tree_positions:
				if abs(p.x - x) < 4 and abs(p.y - z) < 4:
					if Vector2i(x, z).distance_squared_to(p) < config.tree_spacing * config.tree_spacing:
						too_close = true
						break
			if too_close:
				continue
			tree_positions.append(Vector2i(x, z))
			var trunk_h = config.tree_trunk_min + (chunk_rng.randi() % (config.tree_trunk_max - config.tree_trunk_min + 1))
			for y in range(h + 1, h + 1 + trunk_h):
				var pos = Vector3i(x, y, z)
				if out_tree_fast.has(pos) or existing_tree_snap.has(pos):
					continue
				out_tree_fast[pos] = BlockId.Type.LOG
			var leaves_base_y = h + trunk_h + 1
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var p = Vector3i(x + dx, leaves_base_y, z + dz)
					if out_tree_fast.has(p) or existing_tree_snap.has(p):
						continue
					out_tree_fast[p] = BlockId.Type.LEAVES
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if abs(dx) == 1 and abs(dz) == 1 and chunk_rng.randf() < 0.5:
						continue
					var p = Vector3i(x + dx, leaves_base_y + 1, z + dz)
					if out_tree_fast.has(p) or existing_tree_snap.has(p):
						continue
					out_tree_fast[p] = BlockId.Type.LEAVES
			var top = Vector3i(x, leaves_base_y + 2, z)
			if not out_tree_fast.has(top) and not existing_tree_snap.has(top):
				out_tree_fast[top] = BlockId.Type.LEAVES

	var cache_dict = null
	var out_copper_fast: Dictionary = {}
	if not terrain_only:
		var cache = PackedInt32Array()
		cache.resize(cache_x * size_y * cache_z)
		cache.fill(-1)
		for lx in range(cache_x):
			var wx = origin_x + lx - 1
			var column_offset = lx * size_y * cache_z
			for lz in range(cache_z):
				var wz = origin_z + lz - 1
				var col_key = Vector2i(wx, wz)
				var base_h = height_dict[col_key] as int
				var base_top_t = type_dict[col_key] as int
				for ly in range(min(base_h, size_y - 1) + 1):
					var block_type = base_top_t
					if base_top_t == BlockId.Type.GRASS:
						if ly == base_h:
							block_type = BlockId.Type.GRASS
						elif ly >= base_h - 2:
							block_type = BlockId.Type.DIRT
						else:
							block_type = BlockId.Type.STONE
					cache[column_offset + ly * cache_z + lz] = block_type
				if base_h < config.water_level:
					var lake_info = ext_lake_info[col_key] as Vector2
					var river_factors = ext_river_factors[col_key] as Vector2
					var lf = lake_info.x
					var rf = _combined_river_factor(river_factors.x, river_factors.y)
					if lf > 0.01 or rf > 0.01 or base_top_t == BlockId.Type.SAND:
						for ly in range(base_h + 1, min(config.water_level, size_y - 1) + 1):
							cache[column_offset + ly * cache_z + lz] = BlockId.Type.WATER
		if generate_copper:
			out_copper_fast = _generate_copper_deposit(origin_x, origin_z, cs, size_y, cache_z, height_dict, cache)
		var overlays: Array[Dictionary] = [existing_copper_snap, out_copper_fast, existing_tree_snap, out_tree_fast]
		for overlay in overlays:
			for position in overlay:
				if not position is Vector3i:
					continue
				var p = position as Vector3i
				var lx = p.x - origin_x + 1
				var lz = p.z - origin_z + 1
				if lx < 0 or lx >= cache_x or p.y < 0 or p.y >= size_y or lz < 0 or lz >= cache_z:
					continue
				var idx = lx * size_y * cache_z + p.y * cache_z + lz
				cache[idx] = overlay[position]
		for position in removed_snap:
			if position is Vector3i:
				var p = position as Vector3i
				var lx = p.x - origin_x + 1
				var lz = p.z - origin_z + 1
				if lx >= 0 and lx < cache_x and p.y >= 0 and p.y < size_y and lz >= 0 and lz < cache_z:
					cache[lx * size_y * cache_z + p.y * cache_z + lz] = -1
		for position in placed_snap:
			if position is Vector3i:
				var p = position as Vector3i
				var lx = p.x - origin_x + 1
				var lz = p.z - origin_z + 1
				if lx >= 0 and lx < cache_x and p.y >= 0 and p.y < size_y and lz >= 0 and lz < cache_z:
					cache[lx * size_y * cache_z + p.y * cache_z + lz] = placed_snap[position]
		cache_dict = {
			"cache": cache,
			"origin_x": origin_x,
			"origin_z": origin_z,
			"size_x": cs,
			"size_z": cs,
			"size_y": size_y,
			"cache_x": cache_x,
			"cache_z": cache_z,
		}

	var result = {
		"cache_dict": cache_dict,
		"height": height_dict,
		"type": type_dict,
		"tree_block_fast": out_tree_fast,
		"copper_block_fast": out_copper_fast,
		"positions": tree_positions,
	}
	return result

func generate_all() -> Dictionary:
	setup_noises()
	var init_radius = int(config.meadow_radius + 20)
	var size = init_radius * 2
	var payload = build_cache_with_generation(-init_radius, -init_radius, size, config.max_build_y, {}, {}, {}, true)
	# Tree placement is seeded by chunk origin. Applying trees from this larger
	# startup region would conflict with the layouts produced by chunk builds.
	return {
		"height": payload.get("height", {}),
		"type": payload.get("type", {}),
		"tree_block_fast": {},
		"positions": [],
	}
