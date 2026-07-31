extends Resource
class_name WorldConfig

## WorldConfig - stores seed, dimensions, chunk size, height limits, water level, and generation parameters
## Used as .tres file src/world/generation/world_config.tres and injected into TerrainGenerator

@export_group("Dimensions")
@export var seed_value: int = 1337
@export var world_size: int = 200
@export var chunk_size: int = 20
@export var max_height: int = 20
@export var build_extra: int = 8
@export var water_level: int = 5

@export_group("Infinite World")
@export var infinite_world: bool = true

var max_build_y: int:
	get:
		return max_height + build_extra + 8

@export_group("Biomes & Terrain")
@export var meadow_radius: float = 24.0
@export var meadow_target_height: float = 9.5
@export var base_height: float = 9.0
@export var stone_ridge_threshold: float = 0.78
@export var stone_ridge_soft_threshold: float = 0.70
@export var overlook_count: int = 12
@export var min_stone_cells: int = 250

@export_group("Vegetation")
@export var tree_density: float = 0.012
@export var min_trees: int = 60
@export var tree_trunk_min: int = 3
@export var tree_trunk_max: int = 4
@export var tree_spacing: float = 4.5

@export_group("Noise - Hills")
@export var hills_frequency: float = 0.012
@export var hills_octaves: int = 4
@export var hills_lacunarity: float = 2.0
@export var hills_gain: float = 0.45
@export var hills_seed_offset: int = 0

@export_group("Noise - Detail")
@export var detail_frequency: float = 0.045
@export var detail_octaves: int = 2
@export var detail_gain: float = 0.5
@export var detail_seed_offset: int = 101

@export_group("Noise - Biome")
@export var biome_frequency: float = 0.006
@export var biome_octaves: int = 3
@export var biome_seed_offset: int = 202

@export_group("Noise - Forest")
@export var forest_frequency: float = 0.022
@export var forest_octaves: int = 3
@export var forest_seed_offset: int = 303

@export_group("Noise - Ridges")
@export var ridges_frequency: float = 0.018
@export var ridges_octaves: int = 2
@export var ridges_seed_offset: int = 404

@export_group("Lakes")
@export var lake_enabled: bool = true
@export var lake_count: int = 5 # finite: more lakes
@export var lake_radius_min: int = 16
@export var lake_radius_max: int = 42
@export var lake_depth: int = 6
@export var lake_min_dist_from_meadow: float = 28.0
@export var lake_grid_size: int = 180 # infinite: smaller cell = more lakes
@export var lake_chance_per_cell: float = 0.68 # more common
@export var lake_rim_blend: float = 0.80

@export_group("Rivers")
@export var river_enabled: bool = true
@export var river_count: int = 4 # finite worlds
@export var river_width_min: int = 2 # less narrow than 1-3
@export var river_width_max: int = 4
@export var river_depth: int = 3
@export var river_min_length: int = 70
@export var river_max_length: int = 200
@export var river_grid_size: int = 350
@export var river_chance_per_cell: float = 0.55
@export var river_min_dist_from_meadow: float = 22.0
@export var river_carve_blend: float = 0.55 # gradual slope, not sharp drop
@export var river_frequency: float = 0.006 # slightly less twisty for wider feel
@export var river_seed_offset: int = 505

@export_group("Lighting / Rendering")
@export var enable_ao: bool = true
@export var ao_darkness: float = 0.22
@export var enable_shadows: bool = true
@export var shadow_cast_distance: float = 220.0

@export_group("Chunk Streaming")
@export var chunk_streaming_enabled: bool = true
@export var render_distance: int = 4
@export var unload_padding: int = 2
@export var max_chunk_loads_per_frame: int = 1 # 1 keeps main thread <10ms with lakes, mesh in thread
@export var max_chunk_unloads_per_frame: int = 4
@export var chunk_update_interval: float = 0.15


func get_meadow_center() -> Vector2:
	if infinite_world:
		return Vector2.ZERO
	return Vector2(world_size * 0.5, world_size * 0.5)

func get_effective_world_size() -> int:
	if infinite_world:
		return 1000000 # effectively infinite for clamping bypass
	return world_size

func to_dict() -> Dictionary:
	return {
		"seed": seed_value,
		"world_size": world_size,
		"chunk_size": chunk_size,
		"max_height": max_height,
		"build_extra": build_extra,
		"max_build_y": max_build_y,
		"water_level": water_level,
		"tree_density": tree_density,
		"meadow_radius": meadow_radius,
		"chunk_streaming_enabled": chunk_streaming_enabled,
		"render_distance": render_distance,
		"unload_padding": unload_padding,
	}

func validate() -> bool:
	if not infinite_world:
		if world_size <= 0 or world_size > 500:
			push_error("[WorldConfig] world_size %d invalid, must be 1..500" % world_size)
			return false
		if chunk_size <= 0 or chunk_size > world_size:
			push_error("[WorldConfig] chunk_size %d invalid, must be 1..world_size" % chunk_size)
			return false
		if world_size % chunk_size != 0:
			push_error("[WorldConfig] world_size %d must be multiple of chunk_size %d (breaks generator ranges)" % [world_size, chunk_size])
			return false
	else:
		if chunk_size <= 0 or chunk_size > 100:
			push_error("[WorldConfig] chunk_size %d invalid for infinite" % chunk_size)
			return false
	if max_height <= 0 or max_height > 128:
		push_error("[WorldConfig] max_height %d invalid, must be 1..128" % max_height)
		return false
	if build_extra < 0 or build_extra > 64:
		push_error("[WorldConfig] build_extra %d invalid" % build_extra)
		return false
	if max_build_y <= 0 or max_build_y > 128:
		push_error("[WorldConfig] max_build_y %d invalid, must be 1..128 (increase limit to 128)" % max_build_y)
		return false
	if water_level < 0 or water_level >= max_height:
		push_error("[WorldConfig] water_level %d must be >=0 and < max_height %d" % [water_level, max_height])
		return false
	if tree_density < 0.0 or tree_density > 1.0:
		push_error("[WorldConfig] tree_density %f must be 0..1" % tree_density)
		return false
	if not infinite_world:
		if meadow_radius < 0.0 or meadow_radius > world_size * 0.5:
			push_error("[WorldConfig] meadow_radius %f invalid" % meadow_radius)
			return false
	else:
		if meadow_radius < 0.0 or meadow_radius > 100.0:
			push_error("[WorldConfig] meadow_radius %f invalid for infinite" % meadow_radius)
			return false
	if tree_spacing < 0.1:
		push_error("[WorldConfig] tree_spacing too small")
		return false
	if render_distance < 1 or render_distance > 20:
		push_error("[WorldConfig] render_distance %d invalid, must be 1..20" % render_distance)
		return false
	if unload_padding < 0 or unload_padding > 10:
		push_error("[WorldConfig] unload_padding %d invalid, must be 0..10" % unload_padding)
		return false
	if max_chunk_loads_per_frame < 1 or max_chunk_loads_per_frame > 10:
		push_error("[WorldConfig] max_chunk_loads_per_frame %d invalid, must be 1..10" % max_chunk_loads_per_frame)
		return false
	if max_chunk_unloads_per_frame < 1 or max_chunk_unloads_per_frame > 20:
		push_error("[WorldConfig] max_chunk_unloads_per_frame %d invalid" % max_chunk_unloads_per_frame)
		return false
	if chunk_update_interval < 0.05 or chunk_update_interval > 2.0:
		push_error("[WorldConfig] chunk_update_interval %.2f invalid" % chunk_update_interval)
		return false
	# Lakes validation
	if lake_count < 0 or lake_count > 20:
		push_error("[WorldConfig] lake_count %d invalid, must be 0..20" % lake_count)
		return false
	if lake_radius_min < 5 or lake_radius_min > 200:
		push_error("[WorldConfig] lake_radius_min %d invalid" % lake_radius_min)
		return false
	if lake_radius_max < lake_radius_min or lake_radius_max > 300:
		push_error("[WorldConfig] lake_radius_max %d invalid, must be >= min and <=300" % lake_radius_max)
		return false
	if lake_depth < 1 or lake_depth > 20:
		push_error("[WorldConfig] lake_depth %d invalid, must be 1..20" % lake_depth)
		return false
	if lake_grid_size < 50 or lake_grid_size > 1000:
		push_error("[WorldConfig] lake_grid_size %d invalid, must be 50..1000" % lake_grid_size)
		return false
	if lake_chance_per_cell < 0.0 or lake_chance_per_cell > 1.0:
		push_error("[WorldConfig] lake_chance_per_cell %f invalid" % lake_chance_per_cell)
		return false
	if lake_rim_blend < 0.0 or lake_rim_blend > 1.0:
		push_error("[WorldConfig] lake_rim_blend %f invalid" % lake_rim_blend)
		return false
	# Rivers validation
	if river_count < 0 or river_count > 20:
		push_error("[WorldConfig] river_count %d invalid" % river_count)
		return false
	if river_width_min < 1 or river_width_min > 20:
		push_error("[WorldConfig] river_width_min %d invalid" % river_width_min)
		return false
	if river_width_max < river_width_min or river_width_max > 40:
		push_error("[WorldConfig] river_width_max %d invalid" % river_width_max)
		return false
	if river_depth < 1 or river_depth > 10:
		push_error("[WorldConfig] river_depth %d invalid" % river_depth)
		return false
	if river_min_length < 10 or river_min_length > 500:
		push_error("[WorldConfig] river_min_length %d invalid" % river_min_length)
		return false
	if river_max_length < river_min_length or river_max_length > 1000:
		push_error("[WorldConfig] river_max_length %d invalid" % river_max_length)
		return false
	if river_grid_size < 50 or river_grid_size > 2000:
		push_error("[WorldConfig] river_grid_size %d invalid" % river_grid_size)
		return false
	if river_chance_per_cell < 0.0 or river_chance_per_cell > 1.0:
		push_error("[WorldConfig] river_chance_per_cell %f invalid" % river_chance_per_cell)
		return false
	if river_carve_blend < 0.0 or river_carve_blend > 1.0:
		push_error("[WorldConfig] river_carve_blend %f invalid" % river_carve_blend)
		return false
	if river_frequency <= 0.0 or river_frequency > 0.05:
		push_error("[WorldConfig] river_frequency %f invalid" % river_frequency)
		return false
	return true
