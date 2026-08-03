extends RefCounted
class_name TerrainGenerator

var config: WorldConfig

var noise_hills: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_biome: FastNoiseLite
var noise_forest: FastNoiseLite
var noise_ridges: FastNoiseLite
var noise_river: FastNoiseLite

var _lake_grid_cache: Dictionary = {}
var _lake_grid_mutex: Mutex = Mutex.new()
var _noise_mutex: Mutex = Mutex.new()
var _thread_noises: Dictionary = {}
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

func _make_noise_set() -> Dictionary:
	var n_hills = FastNoiseLite.new()
	n_hills.seed = config.seed_value + config.hills_seed_offset
	n_hills.noise_type = FastNoiseLite.TYPE_PERLIN
	n_hills.frequency = config.hills_frequency
	n_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_hills.fractal_octaves = config.hills_octaves
	n_hills.fractal_lacunarity = config.hills_lacunarity
	n_hills.fractal_gain = config.hills_gain

	var n_detail = FastNoiseLite.new()
	n_detail.seed = config.seed_value + config.detail_seed_offset
	n_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	n_detail.frequency = config.detail_frequency
	n_detail.fractal_octaves = config.detail_octaves
	n_detail.fractal_gain = config.detail_gain

	var n_biome = FastNoiseLite.new()
	n_biome.seed = config.seed_value + config.biome_seed_offset
	n_biome.noise_type = FastNoiseLite.TYPE_PERLIN
	n_biome.frequency = config.biome_frequency
	n_biome.fractal_octaves = config.biome_octaves

	var n_forest = FastNoiseLite.new()
	n_forest.seed = config.seed_value + config.forest_seed_offset
	n_forest.noise_type = FastNoiseLite.TYPE_PERLIN
	n_forest.frequency = config.forest_frequency
	n_forest.fractal_octaves = config.forest_octaves

	var n_ridges = FastNoiseLite.new()
	n_ridges.seed = config.seed_value + config.ridges_seed_offset
	n_ridges.noise_type = FastNoiseLite.TYPE_PERLIN
	n_ridges.frequency = config.ridges_frequency
	n_ridges.fractal_octaves = config.ridges_octaves

	var n_river = FastNoiseLite.new()
	n_river.seed = config.seed_value + config.river_seed_offset
	n_river.noise_type = FastNoiseLite.TYPE_PERLIN
	n_river.frequency = config.river_frequency
	n_river.fractal_octaves = 3
	n_river.fractal_type = FastNoiseLite.FRACTAL_FBM
	n_river.fractal_gain = 0.5

	return {
		"hills": n_hills,
		"detail": n_detail,
		"biome": n_biome,
		"forest": n_forest,
		"ridges": n_ridges,
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
			"hills": noise_hills,
			"detail": noise_detail,
			"biome": noise_biome,
			"forest": noise_forest,
			"ridges": noise_ridges,
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
	noise_hills = dict["hills"]
	noise_detail = dict["detail"]
	noise_biome = dict["biome"]
	noise_forest = dict["forest"]
	noise_ridges = dict["ridges"]
	noise_river = dict["river"]

	_lake_grid_mutex.lock()
	_lake_grid_cache.clear()
	_lake_grid_mutex.unlock()

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
	var detail_n = noise_detail
	if thread_noises != null:
		river_n = thread_noises.get("river", river_n)
		detail_n = thread_noises.get("detail", detail_n)
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
	var n2 = detail_n.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.06 if detail_n else 0.0
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

func _compute_base_height_at_world(x: int, z: int, thread_noises: Variant = null) -> float:
	if noise_hills == null:
		setup_noises()
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var meadow_target_h = config.meadow_target_height

	var hills_n = noise_hills
	var detail_n = noise_detail
	var biome_n = noise_biome
	var ridges_n = noise_ridges
	if thread_noises != null:
		hills_n = thread_noises.get("hills", hills_n)
		detail_n = thread_noises.get("detail", detail_n)
		biome_n = thread_noises.get("biome", biome_n)
		ridges_n = thread_noises.get("ridges", ridges_n)

	var n_hills = hills_n.get_noise_2d(float(x), float(z)) if hills_n else 0.0
	var n_detail = detail_n.get_noise_2d(float(x), float(z)) * 0.6 if detail_n else 0.0
	var n_biome_n = biome_n.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.8 if biome_n else 0.0
	var n_ridge_raw = ridges_n.get_noise_2d(float(x), float(z)) if ridges_n else 0.0
	var ridge = 1.0 - abs(n_ridge_raw)

	var h = config.base_height + n_hills * 6.5 + n_detail * 1.8 + n_biome_n * 2.2
	if ridge > 0.72:
		h += (ridge - 0.72) * 8.0

	var d_center = Vector2(x, z).distance_to(meadow_center)
	if d_center < meadow_radius:
		var t = 1.0 - d_center / meadow_radius
		h = lerp(h, meadow_target_h, t * 0.75)
	return h

func compute_height_at_world(x: int, z: int, thread_noises: Variant = null) -> Dictionary:
	var base = _compute_base_height_at_world(x, z, thread_noises)
	var lake_info = _get_lake_info_fast(x, z)
	var river_factors = _get_river_factors_fast(x, z, thread_noises)
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
	}

func _compute_type_from_cached(x: int, z: int, h: int, max_diff: int, lake_factor: float, river_factor: float = 0.0, thread_noises: Variant = null) -> Dictionary:
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var forest_n = noise_forest
	var ridges_n = noise_ridges
	var biome_n = noise_biome
	if thread_noises != null:
		forest_n = thread_noises.get("forest", forest_n)
		ridges_n = thread_noises.get("ridges", ridges_n)
		biome_n = thread_noises.get("biome", biome_n)
	var n_forest = 0.0
	var ridge = 0.0
	if forest_n != null:
		n_forest = forest_n.get_noise_2d(float(x), float(z))
	if ridges_n != null:
		var n_ridge_raw = ridges_n.get_noise_2d(float(x), float(z))
		ridge = 1.0 - abs(n_ridge_raw)
	var d_center = Vector2(x, z).distance_to(meadow_center)
	var is_lake_area = lake_factor > 0.01
	var is_river_area = river_factor > 0.01

	var t: int

	if d_center < meadow_radius - 2.0:
		if (is_lake_area and lake_factor > 0.5 and h <= config.water_level + 1) or (is_river_area and river_factor > 0.55 and h <= config.water_level + 1):
			t = BlockId.Type.SAND
		else:
			t = BlockId.Type.GRASS
	elif is_river_area and river_factor > 0.52:
		t = BlockId.Type.SAND
	elif is_lake_area and lake_factor > 0.32:
		t = BlockId.Type.SAND
	elif h <= config.water_level + 1:
		t = BlockId.Type.SAND
	elif h <= config.water_level + 2:
		if is_river_area and river_factor > 0.40:
			t = BlockId.Type.SAND
		elif is_lake_area and lake_factor > 0.12:
			t = BlockId.Type.SAND
		else:
			var lowland = 0.0
			if biome_n != null:
				lowland = biome_n.get_noise_2d(float(x) * 0.3, float(z) * 0.3)
			if lowland < 0.0 or d_center < meadow_radius + 8.0:
				if h <= config.water_level + 2 and lowland < -0.15:
					t = BlockId.Type.SAND
				else:
					if lowland > -0.1:
						t = BlockId.Type.GRASS
					else:
						t = BlockId.Type.SAND
			else:
				t = BlockId.Type.SAND
	else:
		if is_river_area and river_factor > 0.12:
			if river_factor > 0.50 or h <= config.water_level + 3:
				t = BlockId.Type.SAND
			else:
				t = BlockId.Type.GRASS
		elif is_lake_area and lake_factor > 0.12:
			if lake_factor > 0.25 or h <= config.water_level + 3:
				t = BlockId.Type.SAND
			else:
				t = BlockId.Type.GRASS
		elif ridge > config.stone_ridge_threshold and h >= 11:
			t = BlockId.Type.STONE
		elif ridge > config.stone_ridge_soft_threshold and h >= 13 and n_forest < 0.2:
			t = BlockId.Type.STONE
		elif h >= 15:
			var stone_chance = (h - 14) * 0.26
			var rc = float((abs(x * 73856093 ^ z * 19349663) % 1000)) / 1000.0
			if rc < stone_chance or max_diff >= 3:
				t = BlockId.Type.STONE
			else:
				t = BlockId.Type.GRASS
		elif max_diff >= 3:
			t = BlockId.Type.STONE
		elif max_diff == 2:
			var rc2 = float((abs(x * 83492791 ^ z * 234899) % 1000)) / 1000.0
			if rc2 < 0.5:
				t = BlockId.Type.STONE
			else:
				t = BlockId.Type.GRASS
		else:
			t = BlockId.Type.GRASS

	return {"type": t}

func _calc_max_diff(x: int, z: int, h: int, lake_factor: float, river_factor: float) -> int:
	var max_diff = 0
	if max(lake_factor, river_factor) >= 0.35:
		return 0
	for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
		var nh = compute_height_at_world(x + d.x, z + d.y).get("h", 0) as int
		max_diff = max(max_diff, abs(nh - h))
	return max_diff

func build_cache_with_generation(
	origin_x: int,
	origin_z: int,
	chunk_size: int,
	max_y: int,
	placed_snap: Dictionary,
	removed_snap: Dictionary,
	existing_tree_snap: Dictionary
) -> Dictionary:
	if noise_hills == null:
		setup_noises()

	var thread_noises: Variant = null
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		thread_noises = _get_thread_noises()

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

	for x in range(ext_min_x, ext_max_x + 1):
		for z in range(ext_min_z, ext_max_z + 1):
			var res = compute_height_at_world(x, z, thread_noises)
			var key = Vector2i(x, z)
			ext_h[key] = res.get("h", 1) as int
			ext_lake_info[key] = res.get("lake_info", {"factor":0.0,"depth":0}) as Dictionary
			ext_river_factors[key] = res.get("river_factors", {"core":0.0,"wide":0.0}) as Dictionary

	var height_dict: Dictionary = {}
	var type_dict: Dictionary = {}
	var max_diff_dict: Dictionary = {}

	for x in range(origin_x - 1, origin_x + cs + 1):
		for z in range(origin_z - 1, origin_z + cs + 1):
			var key = Vector2i(x, z)
			var h = ext_h.get(key, -1)
			if h == -1:
				var res2 = compute_height_at_world(x, z, thread_noises)
				h = res2.get("h", 1) as int
				ext_h[key] = h
				ext_lake_info[key] = res2.get("lake_info", {"factor":0.0,"depth":0}) as Dictionary
				ext_river_factors[key] = res2.get("river_factors", {"core":0.0,"wide":0.0}) as Dictionary
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

			var tb = _compute_type_from_cached(x, z, h, max_diff, lf, rf, thread_noises)
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
			var n_forest = 0.0
			var forest_n = noise_forest
			if thread_noises != null:
				forest_n = thread_noises.get("forest", forest_n)
			if forest_n != null:
				n_forest = forest_n.get_noise_2d(float(x), float(z))
			var forest_factor = clamp((n_forest + 0.2) * 1.2, 0.0, 1.2)
			var height_factor = clamp((float(h) - config.base_height) / 6.0, 0.2, 1.0)
			var effective_density = config.tree_density * (0.6 + forest_factor * 0.9 + height_factor * 0.5)
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
					var tb = _compute_type_from_cached(wx, wz, base_h, 0, lf, rf, thread_noises)
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
	}
	return result

func generate_chunk_payload_for_terrain(origin_x: int, origin_z: int, chunk_size: int) -> Dictionary:
	var payload = build_cache_with_generation(origin_x, origin_z, chunk_size, config.max_build_y, {}, {}, {})
	return {
		"height": payload.get("height", {}),
		"type": payload.get("type", {}),
		"tree_block_fast": payload.get("tree_block_fast", {}),
		"positions": payload.get("positions", []),
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

