extends RefCounted
class_name TerrainGenerator

## TerrainGenerator - deterministically generates terrain, biomes, trees, and spawn candidates
## Extended with Lake biome - creates large water bodies via carved bowls.

enum Biome {
	MEADOW = 0,      # flat spawn area (grass)
	LOWLAND = 1,     # sand / water edge
	FOREST = 2,      # wooded rises (grass + trees)
	RIDGE = 3,       # stone ridges
	OVERLOOK = 4,    # flat plateaus with view
	LAKE = 5,        # lake basin - sand floor below water plane
	RIVER = 6,       # river channel - sand floor with flowing water
}

var config: WorldConfig
var rng: RandomNumberGenerator

var noise_hills: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_biome: FastNoiseLite
var noise_forest: FastNoiseLite
var noise_ridges: FastNoiseLite
var noise_river: FastNoiseLite

var height_map: Array = []
var type_map: Array = []
var biome_map: Array = [] # 2D Array of Biome enum
var tree_blocks: Array = [] # [{pos:Vector3i, type:int}]
var tree_block_fast: Dictionary = {} # Vector3i -> type

# Lakes storage
var lakes: Array = []
var _lake_grid_cache: Dictionary = {}
var _lake_grid_mutex: Mutex = Mutex.new()
var _lake_cache_hits: int = 0
var _lake_cache_misses: int = 0

# Rivers storage for finite worlds - each river has polyline points
var rivers: Array = [] # each: {"points":Array[Vector2i], "width":int, "depth":int, "id":int}

# Generation mutex
var _gen_mutex: Mutex = Mutex.new()


func _init(p_config: WorldConfig = null):
	if p_config == null:
		p_config = WorldConfig.new()
	config = p_config
	if not config.validate():
		push_warning("[TerrainGenerator] Invalid config, clamped")
	rng = RandomNumberGenerator.new()
	rng.seed = config.seed_value
	lakes.clear()
	rivers.clear()
	_lake_grid_cache.clear()
	_lake_grid_mutex = Mutex.new()
	_gen_mutex = Mutex.new()
	_lake_cache_hits = 0
	_lake_cache_misses = 0


func setup_noises():
	noise_hills = FastNoiseLite.new()
	noise_hills.seed = config.seed_value + config.hills_seed_offset
	noise_hills.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_hills.frequency = config.hills_frequency
	noise_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_hills.fractal_octaves = config.hills_octaves
	noise_hills.fractal_lacunarity = config.hills_lacunarity
	noise_hills.fractal_gain = config.hills_gain

	noise_detail = FastNoiseLite.new()
	noise_detail.seed = config.seed_value + config.detail_seed_offset
	noise_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_detail.frequency = config.detail_frequency
	noise_detail.fractal_octaves = config.detail_octaves
	noise_detail.fractal_gain = config.detail_gain

	noise_biome = FastNoiseLite.new()
	noise_biome.seed = config.seed_value + config.biome_seed_offset
	noise_biome.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_biome.frequency = config.biome_frequency
	noise_biome.fractal_octaves = config.biome_octaves

	noise_forest = FastNoiseLite.new()
	noise_forest.seed = config.seed_value + config.forest_seed_offset
	noise_forest.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_forest.frequency = config.forest_frequency
	noise_forest.fractal_octaves = config.forest_octaves

	noise_ridges = FastNoiseLite.new()
	noise_ridges.seed = config.seed_value + config.ridges_seed_offset
	noise_ridges.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_ridges.frequency = config.ridges_frequency
	noise_ridges.fractal_octaves = config.ridges_octaves

	noise_river = FastNoiseLite.new()
	noise_river.seed = config.seed_value + config.river_seed_offset
	noise_river.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_river.frequency = config.river_frequency
	noise_river.fractal_octaves = 3
	noise_river.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_river.fractal_gain = 0.5

	# Reset caches
	_lake_grid_mutex.lock()
	_lake_grid_cache.clear()
	_lake_grid_mutex.unlock()

	# Finite world pre-generation
	if not config.infinite_world:
		if config.lake_enabled:
			_generate_lakes_finite()
		if config.river_enabled:
			_generate_rivers_finite()

# ------------------------------------------------------------------
# Lake system - OPTIMIZED: grid cache + distance_squared + RNG reuse
# ------------------------------------------------------------------

func _generate_lakes_finite():
	lakes.clear()
	if not config.lake_enabled:
		return
	if config.lake_count <= 0:
		return
	var meadow_center = config.get_meadow_center()
	var rng_local = RandomNumberGenerator.new()
	rng_local.seed = config.seed_value + 7777
	var attempts = 0
	while lakes.size() < config.lake_count and attempts < 5000:
		attempts += 1
		var x = rng_local.randi_range(config.lake_radius_max, config.world_size - config.lake_radius_max)
		var z = rng_local.randi_range(config.lake_radius_max, config.world_size - config.lake_radius_max)
		var dx = float(x) - meadow_center.x
		var dz = float(z) - meadow_center.y
		if sqrt(dx * dx + dz * dz) < config.meadow_radius + config.lake_min_dist_from_meadow:
			continue
		var too_close = false
		for l in lakes:
			var cx = l["center"].x
			var cz = l["center"].y
			var ddx = float(x - cx)
			var ddz = float(z - cz)
			var min_dist = float(l["radius"] + config.lake_radius_max) * 0.95
			if ddx * ddx + ddz * ddz < min_dist * min_dist:
				too_close = true
				break
		if too_close:
			continue
		var radius = rng_local.randi_range(config.lake_radius_min, config.lake_radius_max)
		var depth = config.lake_depth + rng_local.randi_range(-1, 2)
		depth = clamp(depth, 1, 20)
		lakes.append({"center": Vector2i(x, z), "radius": radius, "radius_sq": radius * radius, "depth": depth})
	print("[TerrainGenerator] Finite lakes generated: %d / %d" % [lakes.size(), config.lake_count])

func _generate_rivers_finite():
	rivers.clear()
	if not config.river_enabled:
		return
	if config.river_count <= 0:
		return
	var meadow_center = config.get_meadow_center()
	var rng_local = RandomNumberGenerator.new()
	rng_local.seed = config.seed_value + 8888
	var attempts = 0
	while rivers.size() < config.river_count and attempts < 5000:
		attempts += 1
		# Pick start - 60% edge, 40% interior for more rivers
		var sx: int
		var sz: int
		if rng_local.randf() < 0.6:
			var edge = rng_local.randi_range(0,3)
			if edge == 0:
				sx = rng_local.randi_range(10, config.world_size - 10)
				sz = 5
			elif edge == 1:
				sx = rng_local.randi_range(10, config.world_size - 10)
				sz = config.world_size - 6
			elif edge == 2:
				sx = 5
				sz = rng_local.randi_range(10, config.world_size - 10)
			else:
				sx = config.world_size - 6
				sz = rng_local.randi_range(10, config.world_size - 10)
		else:
			sx = rng_local.randi_range(15, config.world_size - 15)
			sz = rng_local.randi_range(15, config.world_size - 15)
		var sdist = Vector2(sx, sz).distance_to(meadow_center)
		if sdist < config.meadow_radius + config.river_min_dist_from_meadow * 0.6:
			continue
		var width = rng_local.randi_range(config.river_width_min, config.river_width_max)
		var depth = config.river_depth + rng_local.randi_range(-1,1)
		depth = clamp(depth, 1, 8)
		var length = rng_local.randi_range(config.river_min_length, config.river_max_length)
		var points: Array[Vector2i] = []
		var cur = Vector2i(sx, sz)
		points.append(cur)
		var dir = (meadow_center - Vector2(sx, sz)).normalized()
		var angle = atan2(dir.y, dir.x)
		for _i in range(length):
			# Random walk with meander toward center slightly
			angle += rng_local.randf_range(-0.45, 0.45)
			# Bias slightly toward center
			var to_center = (meadow_center - Vector2(cur.x, cur.y)).normalized()
			var desired = atan2(to_center.y, to_center.x)
			var diff = desired - angle
			# Normalize diff to -PI..PI
			while diff > PI:
				diff -= TAU
			while diff < -PI:
				diff += TAU
			angle = angle + diff * 0.08
			var step_len = rng_local.randi_range(2,4)
			var nx = cur.x + int(round(cos(angle) * step_len))
			var nz = cur.y + int(round(sin(angle) * step_len))
			# Clamp inside world
			if nx < 5 or nx >= config.world_size -5 or nz <5 or nz >= config.world_size -5:
				break
			# Avoid meadow core
			if Vector2(nx, nz).distance_to(meadow_center) < config.meadow_radius - 2.0:
				break
			cur = Vector2i(nx, nz)
			points.append(cur)
			# Occasionally add intermediate points for smoother carve
			if step_len > 2:
				# fill gap
				pass
			if points.size() >= length:
				break
		if points.size() < config.river_min_length * 0.6:
			continue
		# Avoid overlapping existing rivers too closely - relaxed for more rivers
		var too_close = false
		for r in rivers:
			var other_pts = r["points"] as Array
			for p in points:
				for op in other_pts:
					if p.distance_squared_to(op) < 16:
						too_close = true
						break
				if too_close:
					break
			if too_close:
				break
		if too_close:
			continue
		rivers.append({"points": points, "width": width, "depth": depth, "id": rivers.size()})
	print("[TerrainGenerator] Finite rivers generated: %d / %d" % [rivers.size(), config.river_count])

func _get_lake_for_grid_cell(gx: int, gz: int) -> Variant:
	if not config.lake_enabled:
		return null
	var key = Vector2i(gx, gz)
	_lake_grid_mutex.lock()
	if _lake_grid_cache.has(key):
		var cached = _lake_grid_cache[key]
		_lake_cache_hits += 1
		_lake_grid_mutex.unlock()
		return cached
	_lake_grid_mutex.unlock()

	_lake_cache_misses += 1
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
	# store in cache thread-safe
	_lake_grid_mutex.lock()
	if _lake_grid_cache.has(key):
		# another thread raced and inserted
		var existing = _lake_grid_cache[key]
		_lake_grid_mutex.unlock()
		return existing
	_lake_grid_cache[key] = result
	_lake_grid_mutex.unlock()
	return result

# Fast factor only, used in hot loops to avoid dict allocation when only factor needed
func _get_lake_factor_fast(x: int, z: int) -> float:
	if not config.lake_enabled:
		return 0.0
	var best = 0.0
	if not config.infinite_world:
		for lake in lakes:
			var dx = x - lake["center"].x
			var dz = z - lake["center"].y
			var r_sq = lake.get("radius_sq", lake["radius"] * lake["radius"])
			if float(dx * dx + dz * dz) >= float(r_sq):
				continue
			var dist = sqrt(float(dx * dx + dz * dz))
			var t = 1.0 - dist / float(lake["radius"])
			var smooth = t * t * (3.0 - 2.0 * t)
			if smooth > best:
				best = smooth
		return best
	else:
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
					if best > 0.95:
						return best
		return best

func _apply_lake_carve_to_height(base_h: float, x: int, z: int, lake_inf: Variant = null) -> float:
	# Legacy wrapper - now uses fast path without dict alloc when possible
	if not config.lake_enabled:
		return base_h
	if lake_inf != null:
		var inf: Dictionary = lake_inf as Dictionary
		var factor = inf["factor"] as float
		if factor <= 0.001 or inf["lake"] == null:
			return base_h
		var lake_depth = inf["depth"] as int
		var target_h = float(config.water_level) - 1.2 - float(lake_depth) * factor
		target_h = max(target_h, 1.0)
		var blended = lerp(base_h, target_h, factor * config.lake_rim_blend)
		if blended < base_h:
			if factor > 0.7:
				blended = min(blended, float(config.water_level) - 1.0)
			return blended
		return base_h
	# Fast path: no dict allocation, direct carve search
	return _apply_lake_carve_fast(base_h, x, z)

func _apply_lake_carve_fast(base_h: float, x: int, z: int) -> float:
	if not config.lake_enabled:
		return base_h
	var best_factor = 0.0
	var best_depth = 0
	# finite
	if not config.infinite_world:
		for lake in lakes:
			var cx = lake["center"].x
			var cz = lake["center"].y
			var dx = x - cx
			var dz = z - cz
			var r_sq = lake.get("radius_sq", lake["radius"] * lake["radius"])
			var dist_sq = float(dx * dx + dz * dz)
			if dist_sq >= float(r_sq):
				continue
			var dist = sqrt(dist_sq)
			var t = 1.0 - dist / float(lake["radius"])
			var smooth = t * t * (3.0 - 2.0 * t)
			if smooth > best_factor:
				best_factor = smooth
				best_depth = lake["depth"]
	else:
		var grid = config.lake_grid_size
		var gx = int(floor(float(x) / float(grid)))
		var gz = int(floor(float(z) / float(grid)))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var lake = _get_lake_for_grid_cell(gx + dx, gz + dz)
				if lake == null:
					continue
				var cx = lake["center"].x
				var cz = lake["center"].y
				var dx_ = x - cx
				var dz_ = z - cz
				if float(dx_ * dx_ + dz_ * dz_) >= float(lake["radius_sq"]):
					continue
				var dist = sqrt(float(dx_ * dx_ + dz_ * dz_))
				var t = 1.0 - dist / float(lake["radius"])
				var smooth = t * t * (3.0 - 2.0 * t)
				if smooth > best_factor:
					best_factor = smooth
					best_depth = lake["depth"]
					if best_factor > 0.95:
						break
			if best_factor > 0.95:
				break

	if best_factor <= 0.001:
		return base_h
	var target_h = float(config.water_level) - 1.2 - float(best_depth) * best_factor
	target_h = max(target_h, 1.0)
	var blended = lerp(base_h, target_h, best_factor * config.lake_rim_blend)
	if blended < base_h:
		if best_factor > 0.7:
			blended = min(blended, float(config.water_level) - 1.0)
		return blended
	return base_h

# ------------------------------------------------------------------
# River system - carves winding channels, more common lakes
# ------------------------------------------------------------------
func _dist_to_segment_sq(px: float, pz: float, ax: float, az: float, bx: float, bz: float) -> float:
	var abx = bx - ax
	var abz = bz - az
	var apx = px - ax
	var apz = pz - az
	var ab_len_sq = abx * abx + abz * abz
	if ab_len_sq <= 0.0001:
		return apx * apx + apz * apz
	var t = (apx * abx + apz * abz) / ab_len_sq
	t = clamp(t, 0.0, 1.0)
	var cx = ax + abx * t
	var cz = az + abz * t
	var dx = px - cx
	var dz = pz - cz
	return dx * dx + dz * dz

func _get_river_factors_fast(x: int, z: int) -> Dictionary:
	# Returns {core:float, wide:float} for gradual carving
	if not config.river_enabled:
		return {"core": 0.0, "wide": 0.0}
	var best_core = 0.0
	var best_wide = 0.0
	if not config.infinite_world:
		for river in rivers:
			var pts = river["points"] as Array
			if pts.is_empty():
				continue
			var width = river["width"] as int
			var core_w = float(width) * 0.90
			var valley_w = float(width) * 2.6 # wide shallow valley, less narrow but still gradual
			for i in range(pts.size() - 1):
				var a = pts[i] as Vector2i
				var b = pts[i+1] as Vector2i
				var dist_sq = _dist_to_segment_sq(float(x), float(z), float(a.x), float(a.y), float(b.x), float(b.y))
				if dist_sq > valley_w * valley_w:
					continue
				var dist = sqrt(dist_sq)
				if dist < valley_w:
					var tw = 1.0 - dist / valley_w
					var smooth_w = tw * tw * (3.0 - 2.0 * tw)
					if smooth_w > best_wide:
						best_wide = smooth_w
				if dist < core_w:
					var tc = 1.0 - dist / core_w
					var smooth_c = tc * tc * (3.0 - 2.0 * tc)
					if smooth_c > best_core:
						best_core = smooth_c
						if best_core > 0.96 and best_wide > 0.96:
							return {"core": best_core, "wide": best_wide}
		return {"core": best_core, "wide": best_wide}
	else:
		if noise_river == null:
			return {"core": 0.0, "wide": 0.0}
		var n = noise_river.get_noise_2d(float(x), float(z))
		var abs_n = absf(n)
		var core_thr = 0.09 # less narrow than 0.06
		var wide_thr = 0.15 # broad valley, but not too wide - gradual 4-6 blocks
		var core_f = 0.0
		var wide_f = 0.0
		if abs_n < wide_thr:
			var tw = 1.0 - abs_n / wide_thr
			wide_f = tw * tw * (3.0 - 2.0 * tw)
		if abs_n < core_thr:
			var tc = 1.0 - abs_n / core_thr
			core_f = tc * tc * (3.0 - 2.0 * tc)
			core_f = pow(core_f, 0.90)
		# Detail wobble for natural banks, small amplitude
		var n2 = noise_detail.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.06
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

func _get_river_factor_fast(x: int, z: int) -> float:
	# Single float for type checks: combine wide*0.35 + core
	var f = _get_river_factors_fast(x, z)
	var c = f["core"] as float
	var w = f["wide"] as float
	# core dominates, wide contributes shallow
	return max(c, w * 0.42)

func _apply_river_carve_fast(base_h: float, x: int, z: int) -> float:
	if not config.river_enabled:
		return base_h
	var factors = _get_river_factors_fast(x, z)
	var core = factors["core"] as float
	var wide = factors["wide"] as float
	if core <= 0.001 and wide <= 0.001:
		return base_h
	# Gradual lowering: wide shallow valley + deep core channel
	var h = base_h
	if wide > 0.001:
		var shallow_target = float(config.water_level) + 1.5
		# Wide blend stays gentle for gradual slope
		var wide_blend = wide * 0.38
		if base_h > float(config.water_level) + 4.0:
			wide_blend = wide * 0.52
		h = lerp(h, shallow_target, clamp(wide_blend, 0.0, 0.70))

	if core > 0.001:
		var deep_target = float(config.water_level) - 0.5 - float(config.river_depth) * core
		deep_target = max(deep_target, float(config.water_level) - float(config.river_depth) - 1.0)
		deep_target = max(deep_target, 1.0)
		# Core blend is strong to ensure channel below water_level for water fill
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

# ------------------------------------------------------------------
# Combined generation + cache building (single background job)
# Reuses height/type payload for trees to avoid recomputing terrain
# ------------------------------------------------------------------
func build_cache_with_generation(
	origin_x: int,
	origin_z: int,
	chunk_size: int,
	max_y: int,
	placed_snap: Dictionary,
	removed_snap: Dictionary,
	existing_tree_snap: Dictionary
) -> Dictionary:
	# Builds height, type, biome for cache area and generates trees for main chunk,
	# then builds voxel cache array merging edits and trees - all in one pass.
	# Thread-safe: protected by _gen_mutex because GDScript VM is not fully concurrent
	_gen_mutex.lock()
	if noise_hills == null:
		setup_noises()
		# setup_noises resets lake cache with its own lock, keep gen lock held

	var cs = chunk_size
	var size_y = clamp(max_y, 6, 128)
	var cache_x = cs + 2
	var cache_z = cs + 2

	# Extended region for max_diff: need one extra beyond cache border
	var ext_min_x = origin_x - 2
	var ext_max_x = origin_x + cs + 1 # inclusive
	var ext_min_z = origin_z - 2
	var ext_max_z = origin_z + cs + 1

	var ext_h: Dictionary = {}
	var ext_lake_factor: Dictionary = {}
	var ext_river_factor: Dictionary = {}

	# First pass: compute heights + lake/river factors for extended region
	for x in range(ext_min_x, ext_max_x + 1):
		for z in range(ext_min_z, ext_max_z + 1):
			ext_h[Vector2i(x, z)] = compute_height_at_world(x, z)
			ext_lake_factor[Vector2i(x, z)] = _get_lake_factor_fast(x, z)
			ext_river_factor[Vector2i(x, z)] = _get_river_factor_fast(x, z)

	# Second pass: height/type/biome for cache area (origin-1 .. origin+cs)
	var height_dict: Dictionary = {}
	var type_dict: Dictionary = {}
	var biome_dict: Dictionary = {}

	for x in range(origin_x - 1, origin_x + cs + 1):
		for z in range(origin_z - 1, origin_z + cs + 1):
			var key = Vector2i(x, z)
			var h = ext_h.get(key, -1)
			if h == -1:
				h = compute_height_at_world(x, z)
				ext_h[key] = h
				ext_lake_factor[key] = _get_lake_factor_fast(x, z)
				ext_river_factor[key] = _get_river_factor_fast(x, z)
			height_dict[key] = h

			var lf = ext_lake_factor.get(key, 0.0) as float
			var rf = ext_river_factor.get(key, 0.0) as float
			var combined_water_factor = max(lf, rf)
			var max_diff = 0
			if combined_water_factor < 0.35:
				var h0 = h
				var n1 = ext_h.get(Vector2i(x + 1, z), h0)
				var n2 = ext_h.get(Vector2i(x - 1, z), h0)
				var n3 = ext_h.get(Vector2i(x, z + 1), h0)
				var n4 = ext_h.get(Vector2i(x, z - 1), h0)
				max_diff = max(abs(n1 - h0), abs(n2 - h0))
				max_diff = max(max_diff, abs(n3 - h0))
				max_diff = max(max_diff, abs(n4 - h0))

			var tb = _compute_type_from_cached(x, z, h, max_diff, lf, rf)
			type_dict[key] = tb["type"]
			biome_dict[key] = tb["biome"]

	# Third pass: trees for main chunk (origin .. origin+cs-1) reusing ext_h + type
	var out_tree_blocks: Array = []
	var out_tree_fast: Dictionary = {}
	var tree_positions: Array = []
	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = config.seed_value + origin_x * 73856093 + origin_z * 19349663
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius

	for x in range(origin_x, origin_x + cs):
		for z in range(origin_z, origin_z + cs):
			if not config.infinite_world and (x < 0 or x >= config.world_size or z < 0 or z >= config.world_size):
				continue
			var key = Vector2i(x, z)
			var h = height_dict.get(key, -1)
			if h == -1:
				h = ext_h.get(key, -1)
				if h == -1:
					continue
			if h <= config.water_level + 2:
				continue
			var lf = ext_lake_factor.get(key, 0.0) as float
			var rf = ext_river_factor.get(key, 0.0) as float
			if lf > 0.15 or rf > 0.12:
				continue
			var ttype = type_dict.get(key, -1)
			if ttype != BlockId.Type.GRASS:
				continue
			var biome = biome_dict.get(key, -1)
			if biome == Biome.LAKE or biome == Biome.RIVER:
				continue
			if Vector2(x, z).distance_to(meadow_center) < meadow_radius - 2.0:
				continue
			# max_diff already computed? Reuse from type pass: compute again quickly from ext_h
			var max_diff = 0
			if lf < 0.35:
				var h0 = h
				var n1 = ext_h.get(Vector2i(x + 1, z), h0)
				var n2 = ext_h.get(Vector2i(x - 1, z), h0)
				var n3 = ext_h.get(Vector2i(x, z + 1), h0)
				var n4 = ext_h.get(Vector2i(x, z - 1), h0)
				max_diff = max(abs(n1 - h0), abs(n2 - h0))
				max_diff = max(max_diff, abs(n3 - h0))
				max_diff = max(max_diff, abs(n4 - h0))
			if max_diff > 1:
				continue
			var n_forest = 0.0
			if noise_forest != null:
				n_forest = noise_forest.get_noise_2d(float(x), float(z))
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
			# Add tree blocks
			var trunk_h = config.tree_trunk_min + (chunk_rng.randi() % (config.tree_trunk_max - config.tree_trunk_min + 1))
			for y in range(h + 1, h + 1 + trunk_h):
				var pos = Vector3i(x, y, z)
				if out_tree_fast.has(pos) or existing_tree_snap.has(pos):
					continue
				out_tree_fast[pos] = BlockId.Type.LOG
				out_tree_blocks.append({"pos": pos, "type": BlockId.Type.LOG})
			var leaves_base_y = h + trunk_h + 1
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var p = Vector3i(x + dx, leaves_base_y, z + dz)
					if out_tree_fast.has(p) or existing_tree_snap.has(p):
						continue
					out_tree_fast[p] = BlockId.Type.LEAVES
					out_tree_blocks.append({"pos": p, "type": BlockId.Type.LEAVES})
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if abs(dx) == 1 and abs(dz) == 1 and chunk_rng.randf() < 0.5:
						continue
					var p = Vector3i(x + dx, leaves_base_y + 1, z + dz)
					if out_tree_fast.has(p) or existing_tree_snap.has(p):
						continue
					out_tree_fast[p] = BlockId.Type.LEAVES
					out_tree_blocks.append({"pos": p, "type": BlockId.Type.LEAVES})
			var top = Vector3i(x, leaves_base_y + 2, z)
			if not out_tree_fast.has(top) and not existing_tree_snap.has(top):
				out_tree_fast[top] = BlockId.Type.LEAVES
				out_tree_blocks.append({"pos": top, "type": BlockId.Type.LEAVES})

	# Fourth pass: build cache array
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
					var lf = ext_lake_factor.get(col_key, 0.0) as float
					var rf = ext_river_factor.get(col_key, 0.0) as float
					var tb = _compute_type_from_cached(wx, wz, base_h, 0, lf, rf)
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
						var col_key_w = Vector2i(wx, wz)
						var lf = ext_lake_factor.get(col_key_w, 0.0) as float
						var rf = ext_river_factor.get(col_key_w, 0.0) as float
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

	# NOTE: Removed overflow spread (water at wl+1 over banks) that caused floating faces
	# Water now only fills where terrain is below water_level and inside lake/river factor,
	# ensuring top surface is uniformly at water_level and no floating 1-block thick water appears above full water.
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
		"biome": biome_dict,
		"tree_blocks": out_tree_blocks,
		"tree_block_fast": out_tree_fast,
		"positions": tree_positions,
	}
	_gen_mutex.unlock()
	return result

func generate_chunk_payload_for_terrain(origin_x: int, origin_z: int, chunk_size: int) -> Dictionary:
	# One-pass payload for chunk_manager: height/type/biome + trees sharing same ext heights
	# origin is already extended (origin-1) for cache? This wrapper expects main origin, but we handle both.
	if noise_hills == null:
		setup_noises()
	var cs_main = chunk_size
	# If origin is extended (e.g., main_origin-1), we still want to generate for that extended area
	# For simplicity, treat origin_x,origin_z as extended origin and chunk_size as extended size
	var ext_min_x = origin_x - 1
	var ext_max_x = origin_x + chunk_size
	var ext_min_z = origin_z - 1
	var ext_max_z = origin_z + chunk_size

	var ext_h: Dictionary = {}
	var ext_lake_factor: Dictionary = {}
	for x in range(ext_min_x, ext_max_x + 1):
		for z in range(ext_min_z, ext_max_z + 1):
			ext_h[Vector2i(x, z)] = compute_height_at_world(x, z)
			ext_lake_factor[Vector2i(x, z)] = _get_lake_factor_fast(x, z)

	var height_dict: Dictionary = {}
	var type_dict: Dictionary = {}
	var biome_dict: Dictionary = {}

	for x in range(origin_x, origin_x + chunk_size):
		for z in range(origin_z, origin_z + chunk_size):
			var key = Vector2i(x, z)
			var h = ext_h.get(key, -1)
			if h == -1:
				h = compute_height_at_world(x, z)
				ext_h[key] = h
				ext_lake_factor[key] = _get_lake_factor_fast(x, z)
			height_dict[key] = h
			var lf = ext_lake_factor.get(key, 0.0) as float
			var max_diff = 0
			if lf < 0.35:
				var h0 = h
				max_diff = max(abs(ext_h.get(Vector2i(x+1,z), h0) - h0), abs(ext_h.get(Vector2i(x-1,z), h0) - h0))
				max_diff = max(max_diff, abs(ext_h.get(Vector2i(x,z+1), h0) - h0))
				max_diff = max(max_diff, abs(ext_h.get(Vector2i(x,z-1), h0) - h0))
			var tb = _compute_type_from_cached(x, z, h, max_diff, lf)
			type_dict[key] = tb["type"]
			biome_dict[key] = tb["biome"]

	# Trees for inner area (main chunk without extra 1 border? we need to know main origin)
	# If this payload was requested for extended origin (main-1), the main chunk is origin+1
	# We will generate trees for the central part (origin+1 .. origin+chunk_size-2) which corresponds to main chunk
	var tree_origin_x = origin_x + 1
	var tree_origin_z = origin_z + 1
	var tree_size = chunk_size - 2
	if tree_size <= 0:
		tree_origin_x = origin_x
		tree_origin_z = origin_z
		tree_size = chunk_size

	var tree_payload = generate_trees_for_chunk(tree_origin_x, tree_origin_z, tree_size, tree_size)
	# Merge height/type with tree payload for convenience
	return {
		"height": height_dict,
		"type": type_dict,
		"biome": biome_dict,
		"tree_blocks": tree_payload.get("tree_blocks", []),
		"tree_block_fast": tree_payload.get("tree_block_fast", {}),
		"positions": tree_payload.get("positions", []),
	}

# --- Infinite-aware per-coordinate helpers ---
func compute_height_at_world(x: int, z: int) -> int:
	if noise_hills == null:
		setup_noises()
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var meadow_target_h = config.meadow_target_height

	var n_hills = noise_hills.get_noise_2d(float(x), float(z))
	var n_detail = noise_detail.get_noise_2d(float(x), float(z)) * 0.6
	var n_biome_n = noise_biome.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.8
	var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
	var ridge = 1.0 - abs(n_ridge_raw)

	var h = config.base_height + n_hills * 6.5 + n_detail * 1.8 + n_biome_n * 2.2
	if ridge > 0.72:
		h += (ridge - 0.72) * 8.0

	if not config.infinite_world:
		var cx = (float(x) - config.world_size * 0.5) / float(config.world_size)
		var cz = (float(z) - config.world_size * 0.5) / float(config.world_size)
		var dist_edge = sqrt(cx * cx + cz * cz)
		h -= dist_edge * 2.2

	var d_center = Vector2(x, z).distance_to(meadow_center)
	if d_center < meadow_radius:
		var t = 1.0 - d_center / meadow_radius
		h = lerp(h, meadow_target_h, t * 0.75)

	# Lake carving - large water bodies (more common)
	h = _apply_lake_carve_to_height(h, x, z)
	# River carving - winding channels with water
	h = _apply_river_carve_fast(h, x, z)

	var ih = int(round(h))
	ih = clamp(ih, 1, config.max_height)
	return ih

func compute_type_and_biome_at_world(x: int, z: int, h: int) -> Dictionary:
	if noise_forest == null or noise_ridges == null:
		setup_noises()
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius

	var n_forest = noise_forest.get_noise_2d(float(x), float(z))
	var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
	var ridge = 1.0 - abs(n_ridge_raw)
	var d_center = Vector2(x, z).distance_to(meadow_center)

	var max_diff = 0
	var quick_lake_factor = _get_lake_factor_fast(x, z)
	var quick_river_factor = _get_river_factor_fast(x, z)
	var combined_water = max(quick_lake_factor, quick_river_factor)
	if combined_water < 0.35:
		for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var nx = x + d.x
			var nz = z + d.y
			var nh = compute_height_at_world(nx, nz)
			var dh = abs(nh - h)
			if dh > max_diff:
				max_diff = dh
	else:
		max_diff = 0

	var lake_factor = quick_lake_factor
	var river_factor = quick_river_factor
	var is_lake_area = lake_factor > 0.01
	var is_river_area = river_factor > 0.01

	var t: int
	var b: Biome

	if d_center < meadow_radius - 2.0:
		if (is_lake_area and lake_factor > 0.5 and h <= config.water_level + 1) or (is_river_area and river_factor > 0.55 and h <= config.water_level + 1):
			t = BlockId.Type.SAND
			b = Biome.RIVER if is_river_area and river_factor > lake_factor else Biome.LAKE
		else:
			t = BlockId.Type.GRASS
			b = Biome.MEADOW
	elif is_river_area and river_factor > 0.52:
		t = BlockId.Type.SAND
		b = Biome.RIVER
	elif is_lake_area and lake_factor > 0.32:
		t = BlockId.Type.SAND
		b = Biome.LAKE
	elif h <= config.water_level + 1:
		t = BlockId.Type.SAND
		if is_river_area and river_factor > 0.15:
			b = Biome.RIVER
		elif is_lake_area and lake_factor > 0.08:
			b = Biome.LAKE
		else:
			b = Biome.LOWLAND
	elif h <= config.water_level + 2:
		var lowland = noise_biome.get_noise_2d(float(x) * 0.3, float(z) * 0.3)
		if is_river_area and river_factor > 0.40:
			t = BlockId.Type.SAND
			b = Biome.RIVER
		elif is_lake_area and lake_factor > 0.12:
			t = BlockId.Type.SAND
			b = Biome.LAKE
		elif lowland < 0.0 or d_center < meadow_radius + 8.0:
			if h <= config.water_level + 2 and lowland < -0.15:
				t = BlockId.Type.SAND
				b = Biome.LOWLAND
			else:
				if lowland > -0.1:
					t = BlockId.Type.GRASS
					b = Biome.MEADOW
				else:
					t = BlockId.Type.SAND
					b = Biome.LOWLAND
		else:
			t = BlockId.Type.SAND
			b = Biome.LOWLAND
	else:
		if is_river_area and river_factor > 0.12:
			if river_factor > 0.50 or h <= config.water_level + 3:
				t = BlockId.Type.SAND
				b = Biome.RIVER
			else:
				t = BlockId.Type.GRASS
				b = Biome.RIVER
		elif is_lake_area and lake_factor > 0.12:
			if lake_factor > 0.25 or h <= config.water_level + 3:
				t = BlockId.Type.SAND
				b = Biome.LAKE
			else:
				t = BlockId.Type.GRASS
				b = Biome.LAKE
		elif ridge > config.stone_ridge_threshold and h >= 11:
			t = BlockId.Type.STONE
			b = Biome.RIDGE
		elif ridge > config.stone_ridge_soft_threshold and h >= 13 and n_forest < 0.2:
			t = BlockId.Type.STONE
			b = Biome.RIDGE
		elif h >= 15:
			var stone_chance = (h - 14) * 0.26
			var rc = float((abs(x * 73856093 ^ z * 19349663) % 1000)) / 1000.0
			if rc < stone_chance or max_diff >= 3:
				t = BlockId.Type.STONE
				b = Biome.RIDGE
			else:
				t = BlockId.Type.GRASS
				b = Biome.FOREST if n_forest > 0.0 else Biome.MEADOW
		elif max_diff >= 3:
			t = BlockId.Type.STONE
			b = Biome.RIDGE
		elif max_diff == 2:
			var rc2 = float((abs(x * 83492791 ^ z * 234899) % 1000)) / 1000.0
			if rc2 < 0.5:
				t = BlockId.Type.STONE
				b = Biome.RIDGE
			else:
				t = BlockId.Type.GRASS
				b = Biome.FOREST if n_forest > -0.1 else Biome.MEADOW
		else:
			t = BlockId.Type.GRASS
			b = Biome.FOREST if n_forest > -0.1 else Biome.MEADOW

	return {"type": t, "biome": b, "max_diff": max_diff, "lake_factor": lake_factor}



func generate_height_map() -> Array:
	if noise_hills == null:
		setup_noises()

	height_map = []
	height_map.resize(config.world_size)
	for x in range(config.world_size):
		height_map[x] = []
		height_map[x].resize(config.world_size)

	for x in range(config.world_size):
		for z in range(config.world_size):
			height_map[x][z] = compute_height_at_world(x, z)

	return height_map


func generate_type_and_biome_maps() -> Dictionary:
	if height_map.is_empty():
		generate_height_map()
	if noise_forest == null or noise_ridges == null:
		setup_noises()

	type_map = []
	biome_map = []
	type_map.resize(config.world_size)
	biome_map.resize(config.world_size)
	for x in range(config.world_size):
		type_map[x] = []
		type_map[x].resize(config.world_size)
		biome_map[x] = []
		biome_map[x].resize(config.world_size)

	for x in range(config.world_size):
		for z in range(config.world_size):
			var h = height_map[x][z]
			var result = compute_type_and_biome_at_world(x, z, h)
			type_map[x][z] = result["type"]
			biome_map[x][z] = result["biome"]

	# Pass 2: Overlooks - flat stone/grass plateaus with view, no trees
	for _i in range(config.overlook_count):
		var ox = rng.randi_range(30, config.world_size - 30)
		var oz = rng.randi_range(30, config.world_size - 30)
		# Don't place overlook inside lake - fast check
		if max(_get_lake_factor_fast(ox, oz), _get_river_factor_fast(ox, oz)) > 0.2:
			continue
		var h = height_map[ox][oz]
		if h < 12:
			continue
		var flat = true
		for dx in range(-2, 3):
			for dz in range(-2, 3):
				var nx = ox + dx
				var nz = oz + dz
				if nx < 0 or nx >= config.world_size or nz < 0 or nz >= config.world_size:
					continue
				if abs(height_map[nx][nz] - h) > 1:
					flat = false
		if not flat:
			continue
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				var nx = ox + dx
				var nz = oz + dz
				if nx < 0 or nx >= config.world_size or nz < 0 or nz >= config.world_size:
					continue
				if Vector2(dx, dz).length() > 3.2:
					continue
				if max(_get_lake_factor_fast(nx, nz), _get_river_factor_fast(nx, nz)) > 0.15:
					continue
				height_map[nx][nz] = h
				if Vector2(dx, dz).length() > 2.0:
					type_map[nx][nz] = BlockId.Type.STONE
					biome_map[nx][nz] = Biome.RIDGE
				else:
					type_map[nx][nz] = BlockId.Type.GRASS
					biome_map[nx][nz] = Biome.OVERLOOK

	# Pass 3: Guarantee stone and grass so player never spawns without resources
	var stone_count = 0
	var grass_count = 0
	for x in range(config.world_size):
		for z in range(config.world_size):
			if type_map[x][z] == BlockId.Type.STONE:
				stone_count += 1
			if type_map[x][z] == BlockId.Type.GRASS:
				grass_count += 1
	if stone_count < config.min_stone_cells:
		var cells: Array = []
		for x in range(config.world_size):
			for z in range(config.world_size):
				if type_map[x][z] != BlockId.Type.STONE:
					# Avoid lake and river beds
					if biome_map[x][z] == Biome.LAKE or biome_map[x][z] == Biome.RIVER:
						continue
					cells.append(Vector3i(x, height_map[x][z], z))
		cells.sort_custom(func(a, b): return a.y > b.y)
		for k in range(min(300, cells.size())):
			var c = cells[k] as Vector3i
			type_map[c.x][c.z] = BlockId.Type.STONE
			biome_map[c.x][c.z] = Biome.RIDGE

	return {"type_map": type_map, "biome_map": biome_map, "height_map": height_map}


func generate_trees() -> Dictionary:
	if height_map.is_empty() or type_map.is_empty():
		generate_height_map()
		generate_type_and_biome_maps()

	tree_blocks.clear()
	tree_block_fast.clear()

	var positions: Array = []
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius

	for x in range(4, config.world_size - 4):
		for z in range(4, config.world_size - 4):
			if type_map[x][z] != BlockId.Type.GRASS:
				continue
			var h = height_map[x][z]
			if h <= config.water_level + 2:
				continue
			if max(_get_lake_factor_fast(x, z), _get_river_factor_fast(x, z)) > 0.15:
				continue
			if biome_map[x][z] == Biome.LAKE or biome_map[x][z] == Biome.RIVER:
				continue
			var d_center = Vector2(x, z).distance_to(meadow_center)
			if d_center < meadow_radius - 2.0:
				continue

			var max_diff = 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >= 0 and nx < config.world_size and nz >= 0 and nz < config.world_size:
					max_diff = max(max_diff, abs(height_map[nx][nz] - h))
			if max_diff > 1:
				continue

			var n_forest = noise_forest.get_noise_2d(float(x), float(z))
			var forest_factor = clamp((n_forest + 0.2) * 1.2, 0.0, 1.2)
			var height_factor = clamp((h - config.base_height) / 6.0, 0.2, 1.0)
			var effective_density = config.tree_density * (0.6 + forest_factor * 0.9 + height_factor * 0.5)

			if h >= 13 and max_diff == 0 and rng.randf() < 0.15:
				continue

			if rng.randf() > effective_density:
				continue

			var too_close = false
			for p in positions:
				if abs(p.x - x) < 4 and abs(p.y - z) < 4:
					if Vector2i(x, z).distance_to(p) < config.tree_spacing:
						too_close = true
						break
			if too_close:
				continue
			positions.append(Vector2i(x, z))
			_add_tree_at(x, h, z)

	# Guarantee minimum tree count
	if positions.size() < config.min_trees:
		var tries = 0
		while positions.size() < config.min_trees and tries < 5000:
			tries += 1
			var x = rng.randi_range(10, config.world_size - 10)
			var z = rng.randi_range(10, config.world_size - 10)
			if type_map[x][z] != BlockId.Type.GRASS:
				continue
			if Vector2(x, z).distance_to(meadow_center) < meadow_radius:
				continue
			var h = height_map[x][z]
			if h <= config.water_level + 2:
				continue
			if biome_map[x][z] == Biome.LAKE or biome_map[x][z] == Biome.RIVER:
				continue
			if max(_get_lake_factor_fast(x, z), _get_river_factor_fast(x, z)) > 0.15:
				continue
			var too_close = false
			for p in positions:
				if Vector2i(x, z).distance_to(p) < config.tree_spacing:
					too_close = true
					break
			if too_close:
				continue
			positions.append(Vector2i(x, z))
			_add_tree_at(x, h, z)

	return {"tree_blocks": tree_blocks, "tree_block_fast": tree_block_fast, "positions": positions}


func _add_tree_at(x: int, ground_h: int, z: int):
	var trunk_h = config.tree_trunk_min + (rng.randi() % (config.tree_trunk_max - config.tree_trunk_min + 1))
	var trunk_top = ground_h + trunk_h
	for y in range(ground_h + 1, ground_h + 1 + trunk_h):
		_add_tree_block(Vector3i(x, y, z), BlockId.Type.LOG)
	var leaves_base_y = trunk_top + 1
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var nx = x + dx
			var nz = z + dz
			if nx < 0 or nx >= config.world_size or nz < 0 or nz >= config.world_size:
				continue
			_add_tree_block(Vector3i(nx, leaves_base_y, nz), BlockId.Type.LEAVES)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if abs(dx) == 1 and abs(dz) == 1 and rng.randf() < 0.5:
				continue
			var nx = x + dx
			var nz = z + dz
			if nx < 0 or nx >= config.world_size or nz < 0 or nz >= config.world_size:
				continue
			_add_tree_block(Vector3i(nx, leaves_base_y + 1, nz), BlockId.Type.LEAVES)
	_add_tree_block(Vector3i(x, leaves_base_y + 2, z), BlockId.Type.LEAVES)


func _add_tree_block(p: Vector3i, t: int):
	if tree_block_fast.has(p):
		return
	tree_block_fast[p] = t
	tree_blocks.append({"pos": p, "type": t})


# ------------------------------------------------------------------
# Spawn & Biome helpers
# ------------------------------------------------------------------

func get_spawn_candidates() -> Array[Vector3]:
	var candidates: Array[Vector3] = []
	if height_map.is_empty() or type_map.is_empty():
		generate_height_map()
		generate_type_and_biome_maps()

	var cx = config.world_size / 2
	var cz = config.world_size / 2
	var meadow_radius = config.meadow_radius

	for dx in range(-int(meadow_radius), int(meadow_radius) + 1):
		for dz in range(-int(meadow_radius), int(meadow_radius) + 1):
			var x = cx + dx
			var z = cz + dz
			if x < 2 or x >= config.world_size - 2 or z < 2 or z >= config.world_size - 2:
				continue
			if Vector2(x, z).distance_to(Vector2(cx, cz)) > meadow_radius:
				continue
			if type_map[x][z] != BlockId.Type.GRASS:
				continue
			if biome_map[x][z] == Biome.LAKE or biome_map[x][z] == Biome.RIVER:
				continue
			if max(_get_lake_factor_fast(x, z), _get_river_factor_fast(x, z)) > 0.1:
				continue
			var h = height_map[x][z]
			var slope = 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >= 0 and nx < config.world_size and nz >= 0 and nz < config.world_size:
					slope = max(slope, abs(height_map[nx][nz] - h))
			if slope > 0:
				continue
			candidates.append(Vector3(x + 0.5, float(h) + 1.0, z + 0.5))
	candidates.sort_custom(func(a, b): return Vector2(a.x, a.z).distance_to(Vector2(cx, cz)) < Vector2(b.x, b.z).distance_to(Vector2(cx, cz)))
	return candidates


func get_spawn_position() -> Vector3:
	var candidates = get_spawn_candidates()
	if candidates.is_empty():
		return Vector3(config.world_size * 0.5 + 0.5, 10.5, config.world_size * 0.5 + 0.5)
	return candidates[0]


func get_biome_at(x: int, z: int) -> Biome:
	if biome_map.is_empty() or x < 0 or x >= config.world_size or z < 0 or z >= config.world_size:
		# For infinite, infer from type method
		if config.infinite_world:
			var h = compute_height_at_world(x, z)
			var res = compute_type_and_biome_at_world(x, z, h)
			return res["biome"]
		return Biome.MEADOW
	return biome_map[x][z]

func get_height_at(x: int, z: int) -> int:
	if height_map.is_empty():
		return 0
	if x < 0 or x >= config.world_size or z < 0 or z >= config.world_size:
		if config.infinite_world:
			return compute_height_at_world(x, z)
		return 0
	return height_map[x][z]

func get_type_at(x: int, z: int) -> int:
	if type_map.is_empty():
		return BlockId.Type.GRASS
	if x < 0 or x >= config.world_size or z < 0 or z >= config.world_size:
		if config.infinite_world:
			var h = compute_height_at_world(x, z)
			var res = compute_type_and_biome_at_world(x, z, h)
			return res["type"]
		return BlockId.Type.GRASS
	return type_map[x][z]

# ------------------------------------------------------------------
# Full deterministic pipeline
# ------------------------------------------------------------------

func generate_all() -> Dictionary:
	setup_noises()
	if config.infinite_world:
		var init_radius = int(config.meadow_radius + 20)
		var gen = generate_chunk_region(-init_radius, -init_radius, init_radius*2, init_radius*2)
		var tree_gen = generate_trees_for_chunk(-init_radius, -init_radius, init_radius*2, init_radius*2)
		tree_blocks = tree_gen["tree_blocks"]
		tree_block_fast = tree_gen["tree_block_fast"]
		var spawn = Vector3(0.5, float(compute_height_at_world(0,0)) + 1.0, 0.5)
		var candidates: Array[Vector3] = []
		for dx in range(-int(config.meadow_radius), int(config.meadow_radius)+1):
			for dz in range(-int(config.meadow_radius), int(config.meadow_radius)+1):
				if Vector2(dx, dz).length() > config.meadow_radius:
					continue
				if max(_get_lake_factor_fast(dx, dz), _get_river_factor_fast(dx, dz)) > 0.15:
					continue
				var h = compute_height_at_world(dx, dz)
				candidates.append(Vector3(dx+0.5, float(h)+1.0, dz+0.5))
		return {
			"config": config,
			"height_map": gen["height"],
			"type_map": gen["type"],
			"biome_map": gen["biome"],
			"tree_blocks": tree_blocks,
			"tree_block_fast": tree_block_fast,
			"spawn_position": spawn,
			"spawn_candidates": candidates,
			"seed": config.seed_value,
			"infinite": true,
		}
	else:
		generate_height_map()
		generate_type_and_biome_maps()
		generate_trees()
		var spawn = get_spawn_position()
		var spawn_candidates = get_spawn_candidates()

		return {
			"config": config,
			"height_map": height_map,
			"type_map": type_map,
			"biome_map": biome_map,
			"tree_blocks": tree_blocks,
			"tree_block_fast": tree_block_fast,
			"spawn_position": spawn,
			"spawn_candidates": spawn_candidates,
			"seed": config.seed_value,
			"infinite": false,
		}

func get_stats() -> Dictionary:
	return {
		"world_size": config.world_size,
		"seed": config.seed_value,
		"height_cells": config.world_size * config.world_size,
		"trees": tree_blocks.size(),
		"lakes": lakes.size() if not config.infinite_world else _lake_grid_cache.size(),
		"rivers": rivers.size(),
		"lake_cache_hits": _lake_cache_hits,
		"river_cache_hits": 0,
		"biomes": {
			"meadow": _count_biome(Biome.MEADOW),
			"lowland": _count_biome(Biome.LOWLAND),
			"forest": _count_biome(Biome.FOREST),
			"ridge": _count_biome(Biome.RIDGE),
			"overlook": _count_biome(Biome.OVERLOOK),
			"lake": _count_biome(Biome.LAKE),
			"river": _count_biome(Biome.RIVER),
		},
		"spawn_candidates": get_spawn_candidates().size(),
	}

func _count_biome(b: Biome) -> int:
	if biome_map.is_empty():
		return 0
	var c = 0
	for x in range(config.world_size):
		for z in range(config.world_size):
			if biome_map[x][z] == b:
				c += 1
	return c

# ------------------------------------------------------------------
# Chunk streaming helpers - on-demand per-chunk generation (infinite ready)
# ------------------------------------------------------------------

func generate_chunk_region(origin_x: int, origin_z: int, size_x: int, size_z: int) -> Dictionary:
	if noise_hills == null:
		setup_noises()

	var out_h: Dictionary = {}
	var out_t: Dictionary = {}
	var out_b: Dictionary = {}

	if config.infinite_world:
		# Two-pass optimized to avoid 5x height recomputation for max_diff
		# First pass: heights for extended area (region + 1 border for slope checks)
		var ext_h: Dictionary = {}
		# Include one extra border around requested region for max_diff neighbor lookups
		for x in range(origin_x - 1, origin_x + size_x + 1):
			for z in range(origin_z - 1, origin_z + size_z + 1):
				ext_h[Vector2i(x, z)] = compute_height_at_world(x, z)
		# Second pass: type/biome using cached ext heights and fast lake/river factor
		for x in range(origin_x, origin_x + size_x):
			for z in range(origin_z, origin_z + size_z):
				var h = ext_h.get(Vector2i(x, z), config.water_level) as int
				out_h[Vector2i(x, z)] = h

				var lake_factor = _get_lake_factor_fast(x, z)
				var river_factor = _get_river_factor_fast(x, z)

				var max_diff = 0
				var combined = max(lake_factor, river_factor)
				if combined < 0.35:
					var h0 = h
					var neigh = [
						Vector2i(x + 1, z),
						Vector2i(x - 1, z),
						Vector2i(x, z + 1),
						Vector2i(x, z - 1),
					]
					for nk in neigh:
						var nh = ext_h.get(nk, h0) as int
						var dh = abs(nh - h0)
						if dh > max_diff:
							max_diff = dh

				var tb = _compute_type_from_cached(x, z, h, max_diff, lake_factor, river_factor)
				out_t[Vector2i(x, z)] = tb["type"]
				out_b[Vector2i(x, z)] = tb["biome"]

		return {"height": out_h, "type": out_t, "biome": out_b}

	# Finite path - still inside generate_chunk_region
	if height_map.is_empty():
		height_map.resize(config.world_size)
		for _fx in range(config.world_size):
			if _fx >= height_map.size(): continue
			if height_map[_fx] == null or height_map[_fx].is_empty():
				height_map[_fx] = []
				height_map[_fx].resize(config.world_size)

	for x in range(origin_x, origin_x + size_x):
		if x < 0 or x >= config.world_size:
			continue
		for z in range(origin_z, origin_z + size_z):
			if z < 0 or z >= config.world_size:
				continue
			var h: int
			if x < height_map.size() and z < height_map[x].size() and height_map[x][z] is int:
				h = height_map[x][z]
			else:
				h = compute_height_at_world(x, z)
				if x < height_map.size() and z < height_map[x].size():
					height_map[x][z] = h

			if not type_map.is_empty() and x < type_map.size() and type_map[x] and z < type_map[x].size() and type_map[x][z] != null:
				out_h[Vector2i(x,z)] = h
				out_t[Vector2i(x,z)] = type_map[x][z]
				if not biome_map.is_empty() and x < biome_map.size() and biome_map[x] and z < biome_map[x].size():
					out_b[Vector2i(x,z)] = biome_map[x][z]
				continue

			var tb2 = compute_type_and_biome_at_world(x, z, h)
			out_h[Vector2i(x,z)] = h
			out_t[Vector2i(x,z)] = tb2["type"]
			out_b[Vector2i(x,z)] = tb2["biome"]

	return {"height": out_h, "type": out_t, "biome": out_b}

# Helper for chunk region second pass - now supports rivers too
func _compute_type_from_cached(x: int, z: int, h: int, max_diff: int, lake_factor: float, river_factor: float = 0.0) -> Dictionary:
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var n_forest = 0.0
	var ridge = 0.0
	if noise_forest != null:
		n_forest = noise_forest.get_noise_2d(float(x), float(z))
	if noise_ridges != null:
		var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
		ridge = 1.0 - abs(n_ridge_raw)
	var d_center = Vector2(x, z).distance_to(meadow_center)
	var is_lake_area = lake_factor > 0.01
	var is_river_area = river_factor > 0.01

	var t: int
	var b: Biome

	if d_center < meadow_radius - 2.0:
		if (is_lake_area and lake_factor > 0.5 and h <= config.water_level + 1) or (is_river_area and river_factor > 0.55 and h <= config.water_level + 1):
			t = BlockId.Type.SAND
			b = Biome.RIVER if is_river_area and river_factor > lake_factor else Biome.LAKE
		else:
			t = BlockId.Type.GRASS
			b = Biome.MEADOW
	elif is_river_area and river_factor > 0.52:
		# core channel only -> sand, wide valley remains grass for gradual slope
		t = BlockId.Type.SAND
		b = Biome.RIVER
	elif is_lake_area and lake_factor > 0.32:
		t = BlockId.Type.SAND
		b = Biome.LAKE
	elif h <= config.water_level + 1:
		t = BlockId.Type.SAND
		if is_river_area and river_factor > 0.15:
			b = Biome.RIVER
		elif is_lake_area and lake_factor > 0.08:
			b = Biome.LAKE
		else:
			b = Biome.LOWLAND
	elif h <= config.water_level + 2:
		if is_river_area and river_factor > 0.40:
			t = BlockId.Type.SAND
			b = Biome.RIVER
		elif is_lake_area and lake_factor > 0.12:
			t = BlockId.Type.SAND
			b = Biome.LAKE
		else:
			var lowland = 0.0
			if noise_biome != null:
				lowland = noise_biome.get_noise_2d(float(x) * 0.3, float(z) * 0.3)
			if lowland < 0.0 or d_center < meadow_radius + 8.0:
				if h <= config.water_level + 2 and lowland < -0.15:
					t = BlockId.Type.SAND
					b = Biome.LOWLAND
				else:
					if lowland > -0.1:
						t = BlockId.Type.GRASS
						b = Biome.MEADOW
					else:
						t = BlockId.Type.SAND
						b = Biome.LOWLAND
			else:
				t = BlockId.Type.SAND
				b = Biome.LOWLAND
	else:
		if is_river_area and river_factor > 0.12:
			if river_factor > 0.50 or h <= config.water_level + 3:
				t = BlockId.Type.SAND
				b = Biome.RIVER
			else:
				t = BlockId.Type.GRASS
				b = Biome.RIVER
		elif is_lake_area and lake_factor > 0.12:
			if lake_factor > 0.25 or h <= config.water_level + 3:
				t = BlockId.Type.SAND
				b = Biome.LAKE
			else:
				t = BlockId.Type.GRASS
				b = Biome.LAKE
		elif ridge > config.stone_ridge_threshold and h >= 11:
			t = BlockId.Type.STONE
			b = Biome.RIDGE
		elif ridge > config.stone_ridge_soft_threshold and h >= 13 and n_forest < 0.2:
			t = BlockId.Type.STONE
			b = Biome.RIDGE
		elif h >= 15:
			var stone_chance = (h - 14) * 0.26
			var rc = float((abs(x * 73856093 ^ z * 19349663) % 1000)) / 1000.0
			if rc < stone_chance or max_diff >= 3:
				t = BlockId.Type.STONE
				b = Biome.RIDGE
			else:
				t = BlockId.Type.GRASS
				b = Biome.FOREST if n_forest > 0.0 else Biome.MEADOW
		elif max_diff >= 3:
			t = BlockId.Type.STONE
			b = Biome.RIDGE
		elif max_diff == 2:
			var rc2 = float((abs(x * 83492791 ^ z * 234899) % 1000)) / 1000.0
			if rc2 < 0.5:
				t = BlockId.Type.STONE
				b = Biome.RIDGE
			else:
				t = BlockId.Type.GRASS
				b = Biome.FOREST if n_forest > -0.1 else Biome.MEADOW
		else:
			t = BlockId.Type.GRASS
			b = Biome.FOREST if n_forest > -0.1 else Biome.MEADOW

	return {"type": t, "biome": b, "max_diff": max_diff, "lake_factor": lake_factor, "river_factor": river_factor}

func generate_for_chunk(cx: int, cz: int, p_chunk_size: int) -> Dictionary:
	var origin_x = cx * p_chunk_size
	var origin_z = cz * p_chunk_size
	return generate_chunk_region(origin_x, origin_z, p_chunk_size, p_chunk_size)

func ensure_region_generated(origin_x: int, origin_z: int, size_x: int, size_z: int):
	if config.infinite_world:
		generate_chunk_region(origin_x, origin_z, size_x, size_z)
		return
	if height_map.is_empty():
		generate_height_map()
	if type_map.is_empty() or biome_map.is_empty():
		generate_type_and_biome_maps()
	generate_chunk_region(origin_x, origin_z, size_x, size_z)

func generate_trees_for_chunk(origin_x: int, origin_z: int, size_x: int, size_z: int, existing_positions: Array = []) -> Dictionary:
	if noise_forest == null:
		setup_noises()
	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var out_blocks: Array = []
	var out_fast: Dictionary = {}

	var chunk_rng = RandomNumberGenerator.new()
	chunk_rng.seed = config.seed_value + origin_x * 73856093 + origin_z * 19349663

	var positions: Array = existing_positions.duplicate()

	# Two-pass for tree generation: precompute heights + lake/river factors + type cache
	var ext_h: Dictionary = {}
	var ext_lake_factor: Dictionary = {}
	var ext_river_factor: Dictionary = {}
	var ext_type: Dictionary = {}
	for x in range(origin_x - 1, origin_x + size_x + 1):
		for z in range(origin_z - 1, origin_z + size_z + 1):
			if config.infinite_world == false and (x < 0 or x >= config.world_size or z < 0 or z >= config.world_size):
				continue
			ext_h[Vector2i(x, z)] = compute_height_at_world(x, z)
			ext_lake_factor[Vector2i(x, z)] = _get_lake_factor_fast(x, z)
			ext_river_factor[Vector2i(x, z)] = _get_river_factor_fast(x, z)

	# Second pass uses cached heights for slope and type checks
	for x in range(origin_x, origin_x + size_x):
		for z in range(origin_z, origin_z + size_z):
			if config.infinite_world == false and (x < 0 or x >= config.world_size or z < 0 or z >= config.world_size):
				continue
			var h = ext_h.get(Vector2i(x, z), -1)
			if h == -1:
				continue
			if h <= config.water_level + 2:
				continue
			var lf = ext_lake_factor.get(Vector2i(x, z), 0.0) as float
			var rf = ext_river_factor.get(Vector2i(x, z), 0.0) as float
			if lf > 0.15 or rf > 0.12:
				continue

			var max_diff = 0
			var combined = max(lf, rf)
			if combined < 0.35:
				var h0 = h
				for off in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
					var nh = ext_h.get(Vector2i(x + off.x, z + off.y), h0)
					if nh is int:
						var dh = abs(nh - h0)
						if dh > max_diff:
							max_diff = dh

			var tb = _compute_type_from_cached(x, z, h, max_diff, lf, rf)
			ext_type[Vector2i(x, z)] = tb
			if tb["type"] != BlockId.Type.GRASS:
				continue
			if tb["biome"] == Biome.LAKE or tb["biome"] == Biome.RIVER:
				continue
			var d_center = Vector2(x, z).distance_to(meadow_center)
			if d_center < meadow_radius - 2.0:
				continue
			if max_diff > 1:
				continue

			var n_forest = noise_forest.get_noise_2d(float(x), float(z))
			var forest_factor = clamp((n_forest + 0.2) * 1.2, 0.0, 1.2)
			var height_factor = clamp((h - config.base_height) / 6.0, 0.2, 1.0)
			var effective_density = config.tree_density * (0.6 + forest_factor * 0.9 + height_factor * 0.5)

			if chunk_rng.randf() > effective_density:
				continue

			var too_close = false
			for p in positions:
				if abs(p.x - x) < 4 and abs(p.y - z) < 4:
					if Vector2i(x, z).distance_to(p) < config.tree_spacing:
						too_close = true
						break
			if too_close:
				continue
			positions.append(Vector2i(x, z))

			var trunk_h = config.tree_trunk_min + (chunk_rng.randi() % (config.tree_trunk_max - config.tree_trunk_min + 1))
			for y in range(h + 1, h + 1 + trunk_h):
				var pos = Vector3i(x, y, z)
				if not out_fast.has(pos):
					out_fast[pos] = BlockId.Type.LOG
					out_blocks.append({"pos": pos, "type": BlockId.Type.LOG})
			var leaves_base_y = h + trunk_h + 1
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					var nx = x + dx
					var nz = z + dz
					var p = Vector3i(nx, leaves_base_y, nz)
					if not out_fast.has(p):
						out_fast[p] = BlockId.Type.LEAVES
						out_blocks.append({"pos": p, "type": BlockId.Type.LEAVES})
			for dx in range(-1, 2):
				for dz in range(-1, 2):
					if abs(dx) == 1 and abs(dz) == 1 and chunk_rng.randf() < 0.5:
						continue
					var nx = x + dx
					var nz = z + dz
					var p = Vector3i(nx, leaves_base_y + 1, nz)
					if not out_fast.has(p):
						out_fast[p] = BlockId.Type.LEAVES
						out_blocks.append({"pos": p, "type": BlockId.Type.LEAVES})
			var top = Vector3i(x, leaves_base_y + 2, z)
			if not out_fast.has(top):
				out_fast[top] = BlockId.Type.LEAVES
				out_blocks.append({"pos": top, "type": BlockId.Type.LEAVES})

	return {"tree_blocks": out_blocks, "tree_block_fast": out_fast, "positions": positions}
