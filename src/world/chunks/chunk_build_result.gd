extends RefCounted
class_name ChunkBuildResult

var coord: Vector2i
var generation: int
var terrain_only: bool
var generation_payload: Dictionary
var terrain_mesh_data: Variant
var water_mesh_data: Variant
var foliage_cells: PackedInt32Array
var foliage_mesh_data: Variant

func _init(p_coord: Vector2i, p_generation: int, p_terrain_only: bool, p_generation_payload: Dictionary, p_terrain_mesh_data: Variant, p_water_mesh_data: Variant, p_foliage_cells: PackedInt32Array, p_foliage_mesh_data: Variant):
	coord = p_coord
	generation = p_generation
	terrain_only = p_terrain_only
	generation_payload = p_generation_payload
	terrain_mesh_data = p_terrain_mesh_data
	water_mesh_data = p_water_mesh_data
	foliage_cells = p_foliage_cells
	foliage_mesh_data = p_foliage_mesh_data
