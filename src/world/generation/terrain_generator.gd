extends RefCounted
class_name TerrainGenerator

## TerrainGenerator - deterministically generates terrain, biomes, trees, and spawn candidates
## Extracted from WorldController / world_generator.gd monolith into world/generation/
## Uses WorldConfig for parameters, FastNoiseLite for noise, and BlockId/Type for block classification.

enum Biome {
	MEADOW = 0,      # flat spawn area (grass)
	LOWLAND = 1,     # sand / water edge
	FOREST = 2,      # wooded rises (grass + trees)
	RIDGE = 3,       # stone ridges
	OVERLOOK = 4,    # flat plateaus with view
}

var config: WorldConfig
var rng: RandomNumberGenerator

var noise_hills: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_biome: FastNoiseLite
var noise_forest: FastNoiseLite
var noise_ridges: FastNoiseLite

var height_map: Array = []
var type_map: Array = []
var biome_map: Array = [] # 2D Array of Biome enum
var tree_blocks: Array = [] # [{pos:Vector3i, type:int}]
var tree_block_fast: Dictionary = {} # Vector3i -> type


func _init(p_config: WorldConfig = null):
	if p_config == null:
		p_config = WorldConfig.new()
	config = p_config
	if not config.validate():
		push_warning("[TerrainGenerator] Invalid config, clamped")
	rng = RandomNumberGenerator.new()
	rng.seed = config.seed_value


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


func generate_height_map() -> Array:
	if noise_hills == null:
		setup_noises()

	height_map = []
	height_map.resize(config.world_size)
	for x in range(config.world_size):
		height_map[x] = []
		height_map[x].resize(config.world_size)

	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius
	var meadow_target_h = config.meadow_target_height

	for x in range(config.world_size):
		for z in range(config.world_size):
			var n_hills = noise_hills.get_noise_2d(float(x), float(z))
			var n_detail = noise_detail.get_noise_2d(float(x), float(z)) * 0.6
			var n_biome = noise_biome.get_noise_2d(float(x) * 0.5, float(z) * 0.5) * 0.8
			var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
			var ridge = 1.0 - abs(n_ridge_raw)

			var h = config.base_height + n_hills * 6.5 + n_detail * 1.8 + n_biome * 2.2
			if ridge > 0.72:
				h += (ridge - 0.72) * 8.0

			var cx = (float(x) - config.world_size * 0.5) / float(config.world_size)
			var cz = (float(z) - config.world_size * 0.5) / float(config.world_size)
			var dist_edge = sqrt(cx * cx + cz * cz)
			h -= dist_edge * 2.2

			var d_center = Vector2(x, z).distance_to(meadow_center)
			if d_center < meadow_radius:
				var t = 1.0 - d_center / meadow_radius
				h = lerp(h, meadow_target_h, t * 0.75)

			var ih = int(round(h))
			ih = clamp(ih, 2, config.max_height)
			height_map[x][z] = ih

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

	var meadow_center = config.get_meadow_center()
	var meadow_radius = config.meadow_radius

	# Pass 1: base type + biome classification
	for x in range(config.world_size):
		for z in range(config.world_size):
			var h = height_map[x][z]
			var max_diff = 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >= 0 and nx < config.world_size and nz >= 0 and nz < config.world_size:
					var dh = abs(height_map[nx][nz] - h)
					if dh > max_diff:
						max_diff = dh

			var n_forest = noise_forest.get_noise_2d(float(x), float(z))
			var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
			var ridge = 1.0 - abs(n_ridge_raw)
			var d_center = Vector2(x, z).distance_to(meadow_center)

			var t: int
			var b: Biome

			if d_center < meadow_radius - 2.0:
				t = BlockId.Type.GRASS
				b = Biome.MEADOW
			elif h <= config.water_level + 1:
				t = BlockId.Type.SAND
				b = Biome.LOWLAND
			elif h <= config.water_level + 2:
				var lowland = noise_biome.get_noise_2d(float(x) * 0.3, float(z) * 0.3)
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
				if ridge > config.stone_ridge_threshold and h >= 11:
					t = BlockId.Type.STONE
					b = Biome.RIDGE
				elif ridge > config.stone_ridge_soft_threshold and h >= 13 and n_forest < 0.2:
					t = BlockId.Type.STONE
					b = Biome.RIDGE
				elif h >= 15:
					var stone_chance = (h - 14) * 0.26
					if rng.randf() < stone_chance or max_diff >= 3:
						t = BlockId.Type.STONE
						b = Biome.RIDGE
					else:
						t = BlockId.Type.GRASS
						b = Biome.FOREST if n_forest > 0.0 else Biome.MEADOW
				elif max_diff >= 3:
					t = BlockId.Type.STONE
					b = Biome.RIDGE
				elif max_diff == 2 and rng.randf() < 0.5:
					t = BlockId.Type.STONE
					b = Biome.RIDGE
				else:
					t = BlockId.Type.GRASS
					b = Biome.FOREST if n_forest > -0.1 else Biome.MEADOW

			type_map[x][z] = t
			biome_map[x][z] = b

	# Pass 2: Overlooks - flat stone/grass plateaus with view, no trees
	for _i in range(config.overlook_count):
		var ox = rng.randi_range(30, config.world_size - 30)
		var oz = rng.randi_range(30, config.world_size - 30)
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

	# Guarantee minimum tree count so wandering always finds wood
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
		return Biome.MEADOW
	return biome_map[x][z]

func get_height_at(x: int, z: int) -> int:
	if height_map.is_empty():
		return 0
	if x < 0 or x >= config.world_size or z < 0 or z >= config.world_size:
		return 0
	return height_map[x][z]

func get_type_at(x: int, z: int) -> int:
	if type_map.is_empty():
		return BlockId.Type.GRASS
	if x < 0 or x >= config.world_size or z < 0 or z >= config.world_size:
		return BlockId.Type.GRASS
	return type_map[x][z]

# ------------------------------------------------------------------
# Full deterministic pipeline
# ------------------------------------------------------------------

func generate_all() -> Dictionary:
	setup_noises()
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
	}

func get_stats() -> Dictionary:
	return {
		"world_size": config.world_size,
		"seed": config.seed_value,
		"height_cells": config.world_size * config.world_size,
		"trees": tree_blocks.size(),
		"biomes": {
			"meadow": _count_biome(Biome.MEADOW),
			"lowland": _count_biome(Biome.LOWLAND),
			"forest": _count_biome(Biome.FOREST),
			"ridge": _count_biome(Biome.RIDGE),
			"overlook": _count_biome(Biome.OVERLOOK),
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
