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
@export var show_water: bool = true

@export_group("Infinite World")
@export var infinite_world: bool = true
@export var infinite_water_size: int = 1000

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

@export_group("Lighting / Rendering")
@export var enable_ao: bool = true
@export var ao_darkness: float = 0.22
@export var enable_shadows: bool = true
@export var shadow_cast_distance: float = 220.0

@export_group("Chunk Streaming")
@export var chunk_streaming_enabled: bool = true
@export var render_distance: int = 4
@export var unload_padding: int = 2
@export var max_chunk_loads_per_frame: int = 2 # 1-2 keeps main thread <8ms, mesh built in thread
@export var max_chunk_unloads_per_frame: int = 4
@export var chunk_update_interval: float = 0.1


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
	return true
