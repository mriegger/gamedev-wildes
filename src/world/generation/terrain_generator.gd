extends RefCounted
class_name TerrainGenerator

const BiomeScript = preload("res://world/generation/biome.gd")

var config: WorldConfig

var noise_continentalness: FastNoiseLite
var noise_erosion: FastNoiseLite
var noise_peaks_valleys: FastNoiseLite
var noise_temperature: FastNoiseLite
var noise_humidity: FastNoiseLite
var noise_river: FastNoiseLite

var _lake_grid_cache: Dictionary = {}
var _lake_grid_mutex: Mutex = Mutex.new()
var _noise_mutex: Mutex = Mutex.new()
var _thread_noises: Dictionary = {}

var biomes: Array = []
var _biomes_loaded: bool = false
# Rivers: wide channel contributes only a fraction of core strength.
# This weight was tuned so wide channels still trigger sand/water and beach
# logic, but don't dominate deep carving or over-widen beaches.
const RIVER_WIDE_WEIGHT: float = 0.42
const LAKE_GRID_CACHE_MAX: int = 1024
const LAKE_GRID_CACHE_KEEP: int = 768

func _init(p_config: WorldConfig = null):
	if p_config == null:
		p_config = WorldConfig.new()
	config = p_config
	if not config.validate():
		push_warning("[TerrainGenerator] Invalid config, clamped")
	_lake_grid_cache.clear()
	_lake_grid_mutex = Mutex.new()
	_noise_mutex = Mutex.new()
	_biomes_loaded = false
	biomes = []

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

func _river_factor_from_dict(factors: Dictionary) -> float:
	return _combined_river_factor(
		factors.get("core", 0.0) as float,
		factors.get("wide", 0.0) as float
	)

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
	_lake_grid_cache.clear()
	_lake_grid_mutex.unlock()

# --- Biome collection ---

func _load_biomes():
	if _biomes_loaded:
		return
	_biomes_loaded = true
	biomes.clear()
	var path: String = config.biome_collection_path if config else "res://world/generation/biomes"
	var dir = DirAccess.open(path)
	if dir == null:
		push_warning("[TerrainGenerator] Biome dir not found: %s, using fallback biomes" % path)
		_create_fallback_biomes()
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	var loaded: Array = []
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var full = path.path_join(fname)
			var res = ResourceLoader.load(full)
			if res != null and res.get_script() == BiomeScript:
				loaded.append(res)
			else:
				push_warning("[TerrainGenerator] Not a Biome: %s" % full)
		fname = dir.get_next()
	dir.list_dir_end()
	if loaded.is_empty():
		push_warning("[TerrainGenerator] No biomes found in %s, using fallback" % path)
		_create_fallback_biomes()
	else:
		biomes = loaded
	biomes.sort_custom(func(a, b): return (a.biome_id as String) < (b.biome_id as String))

func _create_fallback_biomes():
	biomes.clear()
	var plains = BiomeScript.new()
	plains.biome_id = "plains"; plains.display_name = "Plains"
	plains.min_temperature = 0.25; plains.max_temperature = 0.65
	plains.min_humidity = 0.3; plains.max_humidity = 0.6
	plains.min_continentalness = 0.0; plains.max_continentalness = 0.38
	plains.min_erosion = 0.35; plains.max_erosion = 0.8
	plains.min_peaks_valleys = 0.0; plains.max_peaks_valleys = 0.45
	plains.surface_block = BlockId.Type.GRASS; plains.subsurface_block = BlockId.Type.DIRT; plains.filler_block = BlockId.Type.STONE; plains.shore_block = BlockId.Type.SAND; plains.shore_subsurface_block = BlockId.Type.SAND
	plains.subsurface_depth = 3; plains.tree_density = 0.005; plains.grass_tint = Color(0.55, 0.82, 0.32)
	biomes.append(plains)
	var forest = BiomeScript.new()
	forest.biome_id = "forest"; forest.display_name = "Forest"
	forest.min_temperature = 0.3; forest.max_temperature = 0.7
	forest.min_humidity = 0.45; forest.max_humidity = 0.85
	forest.min_continentalness = 0.2; forest.max_continentalness = 0.6
	forest.min_erosion = 0.1; forest.max_erosion = 0.5
	forest.min_peaks_valleys = 0.2; forest.max_peaks_valleys = 0.65
	forest.surface_block = BlockId.Type.GRASS; forest.subsurface_block = BlockId.Type.DIRT; forest.filler_block = BlockId.Type.STONE; forest.shore_block = BlockId.Type.SAND; forest.shore_subsurface_block = BlockId.Type.SAND
	forest.subsurface_depth = 3; forest.tree_density = 0.03; forest.grass_tint = Color(0.38, 0.62, 0.28)
	biomes.append(forest)
	var desert = BiomeScript.new()
	desert.biome_id = "desert"; desert.display_name = "Desert"
	desert.min_temperature = 0.72; desert.max_temperature = 1.0
	desert.min_humidity = 0.0; desert.max_humidity = 0.32
	desert.min_continentalness = 0.0; desert.max_continentalness = 0.45
	desert.min_erosion = 0.3; desert.max_erosion = 0.85
	desert.min_peaks_valleys = 0.0; desert.max_peaks_valleys = 0.35
	desert.surface_block = BlockId.Type.SAND; desert.subsurface_block = BlockId.Type.SAND; desert.filler_block = BlockId.Type.STONE; desert.shore_block = BlockId.Type.SAND; desert.shore_subsurface_block = BlockId.Type.SAND
	desert.subsurface_depth = 4; desert.tree_density = 0.0; desert.grass_tint = Color(0.82, 0.76, 0.48)
	biomes.append(desert)
	var mountains = BiomeScript.new()
	mountains.biome_id = "mountains"; mountains.display_name = "Mountains"
	mountains.min_temperature = 0.15; mountains.max_temperature = 0.55
	mountains.min_humidity = 0.2; mountains.max_humidity = 0.6
	mountains.min_continentalness = 0.62; mountains.max_continentalness = 1.0
	mountains.min_erosion = 0.0; mountains.max_erosion = 0.42
	mountains.min_peaks_valleys = 0.5; mountains.max_peaks_valleys = 1.0
	mountains.surface_block = BlockId.Type.STONE; mountains.subsurface_block = BlockId.Type.STONE; mountains.filler_block = BlockId.Type.STONE; mountains.shore_block = BlockId.Type.SAND; mountains.shore_subsurface_block = BlockId.Type.SAND
	mountains.subsurface_depth = 1; mountains.tree_density = 0.002; mountains.grass_tint = Color(0.6, 0.65, 0.62)
	biomes.append(mountains)
	var wetland = BiomeScript.new()
	wetland.biome_id = "wetland"; wetland.display_name = "Wetland"
	wetland.min_temperature = 0.35; wetland.max_temperature = 0.75
	wetland.min_humidity = 0.62; wetland.max_humidity = 1.0
	wetland.min_continentalness = 0.0; wetland.max_continentalness = 0.28
	wetland.min_erosion = 0.45; wetland.max_erosion = 0.92
	wetland.min_peaks_valleys = 0.0; wetland.max_peaks_valleys = 0.25
	wetland.surface_block = BlockId.Type.GRASS; wetland.subsurface_block = BlockId.Type.DIRT; wetland.filler_block = BlockId.Type.STONE; wetland.shore_block = BlockId.Type.SAND; wetland.shore_subsurface_block = BlockId.Type.SAND
	wetland.subsurface_depth = 3; wetland.tree_density = 0.012; wetland.grass_tint = Color(0.42, 0.72, 0.36)
	biomes.append(wetland)
	var highland = BiomeScript.new()
	highland.biome_id = "highland"; highland.display_name = "Highland"
	highland.min_temperature = 0.2; highland.max_temperature = 0.6
	highland.min_humidity = 0.15; highland.max_humidity = 0.55
	highland.min_continentalness = 0.55; highland.max_continentalness = 0.92
	highland.min_erosion = 0.5; highland.max_erosion = 0.95
	highland.min_peaks_valleys = 0.0; highland.max_peaks_valleys = 0.5
	highland.surface_block = BlockId.Type.GRASS; highland.subsurface_block = BlockId.Type.DIRT; highland.filler_block = BlockId.Type.STONE; highland.shore_block = BlockId.Type.SAND; highland.shore_subsurface_block = BlockId.Type.SAND
	highland.subsurface_depth = 3; highland.tree_density = 0.008; highland.grass_tint = Color(0.5, 0.72, 0.35)
	biomes.append(highland)

func _ensure_biomes():
	if not _biomes_loaded:
		_load_biomes()

func _find_closest_biome(params: PackedFloat32Array) -> Resource:
	_ensure_biomes()
	if biomes.is_empty():
		return null
	var best: Resource = biomes[0] as Resource
	var best_d: float = best.distance_squared_to(params)
	for i in range(1, biomes.size()):
		var b = biomes[i] as Resource
		var d = b.distance_squared_to(params)
		if d < best_d:
			best = b
			best_d = d
	return best

func get_biome_at(x: int, z: int, thread_noises: Variant = null) -> Resource:
	if noise_continentalness == null:
		setup_noises()
	_ensure_biomes()
	var step: int = config.param_lattice_step if config and config.param_lattice_step > 0 else 4
	var lx: int = int(floor(float(x) / float(step))) * step
	var lz: int = int(floor(float(z) / float(step))) * step
	var tn: Dictionary
	if thread_noises != null and thread_noises is Dictionary:
		tn = thread_noises as Dictionary
	else:
		tn = _get_thread_noises()
	var params = _raw_params_at(lx, lz, tn)
	return _find_closest_biome(params)

func get_biome_at_with_params(params: PackedFloat32Array) -> Resource:
	_ensure_biomes()
	return _find_closest_biome(params)

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

func _sample_params(x: int, z: int, tn: Dictionary, lattice_cache: Dictionary) -> PackedFloat32Array:
	var step: int = config.param_lattice_step if config else 4
	if step <= 1:
		return _raw_params_at(x, z, tn)
	var x0: int = int(floor(float(x) / float(step))) * step
	var z0: int = int(floor(float(z) / float(step))) * step
	var tx: float = float(x - x0) / float(step)
	var tz: float = float(z - z0) / float(step)
	tx = clamp(tx, 0.0, 1.0)
	tz = clamp(tz, 0.0, 1.0)
	var c00 = _get_lattice_raw(x0, z0, tn, lattice_cache)
	var c10 = _get_lattice_raw(x0 + step, z0, tn, lattice_cache)
	var c01 = _get_lattice_raw(x0, z0 + step, tn, lattice_cache)
	var c11 = _get_lattice_raw(x0 + step, z0 + step, tn, lattice_cache)
	var out = PackedFloat32Array()
	out.resize(5)
	for i in 5:
		var v00 = c00[i]
		var v10 = c10[i]
		var v01 = c01[i]
		var v11 = c11[i]
		var vx0 = lerp(v00, v10, tx)
		var vx1 = lerp(v01, v11, tx)
		out[i] = lerp(vx0, vx1, tz)
	return out

func _get_lake_for_grid_cell(gx: int, gz: int) -> Variant:
	if not config.lake_enabled:
		return null
	var key = Vector2i(gx, gz)
	_lake_grid_mutex.lock()
	if _lake_grid_cache.has(key):
		var cached = _lake_grid_cache[key]
		_lake_grid_mutex.unlock()
		return cached
	_lake_grid_mutex.unlock()

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
	_lake_grid_mutex.lock()
	if _lake_grid_cache.has(key):
		var existing = _lake_grid_cache[key]
		_lake_grid_mutex.unlock()
		return existing
	_lake_grid_cache[key] = result
	if _lake_grid_cache.size() > LAKE_GRID_CACHE_MAX:
		var keys = _lake_grid_cache.keys()
		var to_remove = _lake_grid_cache.size() - LAKE_GRID_CACHE_KEEP
		for i in range(to_remove):
			_lake_grid_cache.erase(keys[i])
	_lake_grid_mutex.unlock()
	return result

func _get_lake_info_fast(x: int, z: int) -> Dictionary:
	if not config.lake_enabled:
		return {"factor": 0.0, "depth": 0}
	var best = 0.0
	var best_depth = 0
	var grid = config.lake_grid_size
	var gx = int(floor(float(x) / float(grid)))
	var gz = int(floor(float(z) / float(grid)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var lake = _get_lake_for_grid_cell(gx + dx, gz + dz)
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
					return {"factor": best, "depth": best_depth}
	return {"factor": best, "depth": best_depth}

func _apply_lake_carve_with_info(base_h: float, info: Dictionary) -> float:
	if not config.lake_enabled:
		return base_h
	var factor = info.get("factor", 0.0) as float
	if factor <= 0.001:
		return base_h
	var depth = info.get("depth", 0) as int
	var target_h = float(config.water_level) - 1.2 - float(depth) * factor
	target_h = max(target_h, 1.0)
	var blended = lerp(base_h, target_h, factor * config.lake_rim_blend)
	if blended < base_h:
		if factor > 0.7:
			blended = min(blended, float(config.water_level) - 1.0)
		return blended
	return base_h

func _get_river_factors_fast(x: int, z: int, thread_noises: Variant = null) -> Dictionary:
	if not config.river_enabled:
		return {"core": 0.0, "wide": 0.0}
	var river_n = noise_river
	var erosion_n = noise_erosion
	if thread_noises != null:
		river_n = thread_noises.get("river", river_n)
		erosion_n = thread_noises.get("erosion", erosion_n)
	if river_n == null:
		return {"core": 0.0, "wide": 0.0}
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
	var n2 = erosion_n.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.06 if erosion_n else 0.0
	if wide_f > 0.0:
		wide_f = clamp(wide_f + n2 * 0.5, 0.0, 1.0)
	if core_f > 0.0:
		core_f = clamp(core_f + n2, 0.0, 1.0)
	var d_center = Vector2(x, z).length()
	if d_center < config.meadow_radius + config.river_min_dist_from_meadow - 5.0:
		var fade = clamp((d_center - (config.meadow_radius - 5.0)) / (config.river_min_dist_from_meadow), 0.0, 1.0)
		wide_f *= fade
		core_f *= fade
	return {"core": core_f, "wide": wide_f}

func _apply_river_carve_with_factors(base_h: float, factors: Dictionary) -> float:
	if not config.river_enabled:
		return base_h
	var core = factors.get("core", 0.0) as float
	var wide = factors.get("wide", 0.0) as float
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

func _compute_base_height_with_params(x: int, z: int, params: PackedFloat32Array) -> float:
	var continentalness: float = clamp(params[Biome.IDX_CONTINENTALNESS], 0.0, 1.0)
	var erosion: float = clamp(params[Biome.IDX_EROSION], 0.0, 1.0)
	var pv: float = clamp(params[Biome.IDX_PEAKS_VALLEYS], 0.0, 1.0)
	var cont_offset: float = config.sample_spline(continentalness, config.continentalness_curve)
	var amp: float = config.sample_spline(erosion, config.erosion_amplitude_curve)
	amp = clamp(amp, 0.0, 1.0)
	var h: float = config.base_height + cont_offset + pv * amp * config.relief_scale
	var meadow_center = config.get_meadow_center()
	var d_center = Vector2(x, z).distance_to(meadow_center)
	if d_center < config.meadow_radius:
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

func compute_height_at_world(x: int, z: int, thread_noises: Variant = null) -> Dictionary:
	if noise_continentalness == null:
		setup_noises()
	var tn: Dictionary
	if thread_noises != null and thread_noises is Dictionary:
		tn = thread_noises as Dictionary
	else:
		tn = _get_thread_noises()
	var params: PackedFloat32Array
	if thread_noises != null and thread_noises is Dictionary:
		var lattice_cache: Dictionary = {}
		params = _sample_params(x, z, tn, lattice_cache)
	else:
		params = _raw_params_at(x, z, tn)
	var base = _compute_base_height_with_params(x, z, params)
	var lake_info = _get_lake_info_fast(x, z)
	var river_factors = _get_river_factors_fast(x, z, tn)
	var hf = _apply_lake_carve_with_info(base, lake_info)
	hf = _apply_river_carve_with_factors(hf, river_factors)
	var ih = int(round(clamp(hf, 1.0, float(config.max_height))))
	var rf = _river_factor_from_dict(river_factors)
	return {
		"h": ih,
		"lake_factor": lake_info.get("factor", 0.0) as float,
		"lake_info": lake_info,
		"river_factors": river_factors,
		"river_factor": rf,
		"params": params,
	}

func _compute_type_with_params(x: int, z: int, h: int, params: PackedFloat32Array, lake_factor: float, river_factor: float) -> Dictionary:
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var d_center = Vector2(x, z).distance_to(meadow_center)
	var is_lake = lake_factor > 0.01
	var is_river = river_factor > 0.01
	if d_center < meadow_radius - 2.0:
		if (is_lake and lake_factor > 0.5 and h <= config.water_level + 1) or (is_river and river_factor > 0.55 and h <= config.water_level + 1):
			return {"type": BlockId.Type.SAND}
		else:
			return {"type": BlockId.Type.GRASS}
	var water_influence: float = max(lake_factor, river_factor)
	if _is_shore(h, water_influence):
		var shore_biome = _find_closest_biome(params)
		if shore_biome != null:
			return {"type": shore_biome.shore_block}
		return {"type": BlockId.Type.SAND}
	var biome = _find_closest_biome(params)
	if biome == null:
		return {"type": BlockId.Type.GRASS}
	return {"type": biome.surface_block}

func _compute_type_with_biome(x: int, z: int, h: int, biome: Resource, lake_factor: float, river_factor: float) -> Dictionary:
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var d_center = Vector2(x, z).distance_to(meadow_center)
	var is_lake = lake_factor > 0.01
	var is_river = river_factor > 0.01
	if d_center < meadow_radius - 2.0:
		if (is_lake and lake_factor > 0.5 and h <= config.water_level + 1) or (is_river and river_factor > 0.55 and h <= config.water_level + 1):
			return {"type": BlockId.Type.SAND}
		else:
			return {"type": BlockId.Type.GRASS}
	var water_influence: float = max(lake_factor, river_factor)
	if _is_shore(h, water_influence):
		if biome != null:
			return {"type": biome.shore_block}
		return {"type": BlockId.Type.SAND}
	if biome == null:
		return {"type": BlockId.Type.GRASS}
	return {"type": biome.surface_block}

func _compute_type_from_cached(x: int, z: int, h: int, lake_factor: float, river_factor: float = 0.0, thread_noises: Variant = null) -> Dictionary:
	var params: PackedFloat32Array
	if thread_noises != null and thread_noises is Dictionary:
		var tn = thread_noises as Dictionary
		var cache: Dictionary = {}
		params = _sample_params(x, z, tn, cache)
	else:
		var tn2 = _get_thread_noises()
		params = _raw_params_at(x, z, tn2)
	return _compute_type_with_params(x, z, h, params, lake_factor, river_factor)

func build_cache_with_generation(
	origin_x: int,
	origin_z: int,
	chunk_size: int,
	max_y: int,
	placed_snap: Dictionary,
	removed_snap: Dictionary,
	existing_tree_snap: Dictionary
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
			var params = _sample_params(x, z, tn, lattice_cache)
			var base = _compute_base_height_with_params(x, z, params)
			var lake_info = _get_lake_info_fast(x, z)
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

	var step: int = config.param_lattice_step if config else 4
	var lattice_biome_cache: Dictionary = {}

	for x in range(origin_x - 1, origin_x + cs + 1):
		for z in range(origin_z - 1, origin_z + cs + 1):
			var key = Vector2i(x, z)
			var h = ext_h.get(key, -1)
			if h == -1:
				var p2 = _sample_params(x, z, tn, lattice_cache)
				var b2 = _compute_base_height_with_params(x, z, p2)
				var li2 = _get_lake_info_fast(x, z)
				var rf2 = _get_river_factors_fast(x, z, tn)
				var hf2 = _apply_lake_carve_with_info(b2, li2)
				hf2 = _apply_river_carve_with_factors(hf2, rf2)
				h = int(round(clamp(hf2, 1.0, float(config.max_height))))
				ext_h[key] = h
				ext_lake_info[key] = li2
				ext_river_factors[key] = rf2
			height_dict[key] = h
			var lake_info = ext_lake_info.get(key, {"factor": 0.0, "depth": 0}) as Dictionary
			var river_factors = ext_river_factors.get(key, {"core": 0.0, "wide": 0.0}) as Dictionary
			var lf = lake_info.get("factor", 0.0) as float
			var rf = _river_factor_from_dict(river_factors)
			var max_diff = 0
			var combined = max(lf, rf)
			if combined < 0.35:
				var h0 = h
				var n1 = ext_h.get(Vector2i(x + 1, z), h0)
				var n2 = ext_h.get(Vector2i(x - 1, z), h0)
				var n3 = ext_h.get(Vector2i(x, z + 1), h0)
				var n4 = ext_h.get(Vector2i(x, z - 1), h0)
				max_diff = max(abs(n1 - h0), abs(n2 - h0))
				max_diff = max(max_diff, abs(n3 - h0))
				max_diff = max(max_diff, abs(n4 - h0))
			# Biome per lattice cell (4 block resolution) - params already lattice interpolated
			var lx: int = int(floor(float(x) / float(step))) * step
			var lz: int = int(floor(float(z) / float(step))) * step
			var lattice_key = Vector2i(lx, lz)
			var biome: Resource = lattice_biome_cache.get(lattice_key, null) as Resource
			if biome == null:
				var cell_params = _raw_params_at(lx, lz, tn)
				biome = _find_closest_biome(cell_params)
				lattice_biome_cache[lattice_key] = biome
			if biome != null:
				biome_dict[key] = biome
			var tb = _compute_type_with_biome(x, z, h, biome, lf, rf)
			type_dict[key] = tb.get("type", BlockId.Type.GRASS) as int
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
			var h = height_dict.get(key, -1)
			if h == -1:
				h = ext_h.get(key, -1)
				if h == -1:
					continue
			if h <= config.water_level + 2:
				continue
			var lake_info = ext_lake_info.get(key, {"factor": 0.0, "depth": 0}) as Dictionary
			var river_factors = ext_river_factors.get(key, {"core": 0.0, "wide": 0.0}) as Dictionary
			var lf = lake_info.get("factor", 0.0) as float
			var rf = _river_factor_from_dict(river_factors)
			if lf > 0.15 or rf > 0.12:
				continue
			var ttype = type_dict.get(key, -1)
			if ttype != BlockId.Type.GRASS:
				continue
			if Vector2(x, z).distance_to(meadow_center) < meadow_radius - 2.0:
				continue
			var max_diff = max_diff_dict.get(key, 0) as int
			if max_diff > 1:
				continue
			var biome = biome_dict.get(key, null) as Resource
			var biome_density: float = 0.012
			if biome != null:
				biome_density = biome.tree_density
			else:
				biome_density = config.tree_density
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
					if Vector2i(x, z).distance_to(p) < config.tree_spacing:
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

	var cache: Array = []
	cache.resize(cache_x * size_y * cache_z)

	for lx in range(cache_x):
		var wx = origin_x + lx - 1
		for lz in range(cache_z):
			var wz = origin_z + lz - 1
			var col_key = Vector2i(wx, wz)
			var base_h = height_dict.get(col_key, -1) as int
			var base_top_t = type_dict.get(col_key, -1) as int
			if base_h == -1:
				base_h = ext_h.get(col_key, -1) as int
				if base_h != -1:
					var lake_info = ext_lake_info.get(col_key, {"factor": 0.0, "depth": 0}) as Dictionary
					var river_factors = ext_river_factors.get(col_key, {"core": 0.0, "wide": 0.0}) as Dictionary
					var lf = lake_info.get("factor", 0.0) as float
					var rf = _river_factor_from_dict(river_factors)
					var tb = _compute_type_from_cached(wx, wz, base_h, lf, rf, thread_noises)
					base_top_t = tb["type"]
			for ly in range(size_y):
				var idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				var wy = ly
				var p = Vector3i(wx, wy, wz)

				if placed_snap.has(p):
					cache[idx] = placed_snap[p]
					continue
				if removed_snap.has(p):
					cache[idx] = -1
					continue
				if out_tree_fast.has(p):
					cache[idx] = out_tree_fast[p]
					continue
				if existing_tree_snap.has(p):
					cache[idx] = existing_tree_snap[p]
					continue

				if base_h == -1:
					cache[idx] = -1
					continue
				if wy > base_h:
					if wy <= config.water_level and base_h < config.water_level:
						var lf = 0.0
						var rf = 0.0
						var li = ext_lake_info.get(col_key, null)
						if li != null:
							lf = li.get("factor", 0.0) as float
						var rfi = ext_river_factors.get(col_key, null)
						if rfi != null:
							rf = _river_factor_from_dict(rfi)
						if lf > 0.01 or rf > 0.01 or base_top_t == BlockId.Type.SAND:
							cache[idx] = BlockId.Type.WATER
						else:
							cache[idx] = -1
					else:
						cache[idx] = -1
					continue
				if base_top_t == -1:
					cache[idx] = -1
					continue
				if base_top_t == BlockId.Type.SAND:
					cache[idx] = BlockId.Type.SAND
				elif base_top_t == BlockId.Type.STONE:
					cache[idx] = BlockId.Type.STONE
				elif base_top_t == BlockId.Type.GRASS:
					if wy == base_h:
						cache[idx] = BlockId.Type.GRASS
					elif wy >= base_h - 2:
						cache[idx] = BlockId.Type.DIRT
					else:
						cache[idx] = BlockId.Type.STONE
				elif base_top_t == BlockId.Type.DIRT:
					cache[idx] = BlockId.Type.DIRT
				else:
					cache[idx] = base_top_t

	var cache_dict = {
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
		"positions": tree_positions,
		"biome": biome_dict,
	}
	return result

func generate_chunk_payload_for_terrain(origin_x: int, origin_z: int, chunk_size: int) -> Dictionary:
	var payload = build_cache_with_generation(origin_x, origin_z, chunk_size, config.max_build_y, {}, {}, {})
	return {
		"height": payload.get("height", {}),
		"type": payload.get("type", {}),
		"tree_block_fast": payload.get("tree_block_fast", {}),
		"positions": payload.get("positions", []),
		"biome": payload.get("biome", {}),
	}

func generate_all() -> Dictionary:
	setup_noises()
	var init_radius = int(config.meadow_radius + 20)
	var size = init_radius * 2
	var payload = generate_chunk_payload_for_terrain(-init_radius, -init_radius, size)
	var tree_block_fast = payload.get("tree_block_fast", {}) as Dictionary
	return {
		"height_map": payload.get("height", {}),
		"type_map": payload.get("type", {}),
		"tree_block_fast": tree_block_fast,
		"positions": payload.get("positions", []),
	}

