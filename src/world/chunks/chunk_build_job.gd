extends RefCounted
class_name ChunkBuildJob

var coord: Vector2i
var generation: int
var terrain_only: bool
var placed_blocks: Dictionary
var removed_blocks: Dictionary
var foliage_clearance: Dictionary
var tree_blocks: Dictionary
var copper_blocks: Dictionary
var generate_copper: bool

func _init(p_coord: Vector2i, p_generation: int, p_terrain_only: bool, p_placed_blocks: Dictionary, p_removed_blocks: Dictionary, p_foliage_clearance: Dictionary, p_tree_blocks: Dictionary, p_copper_blocks: Dictionary, p_generate_copper: bool):
	coord = p_coord
	generation = p_generation
	terrain_only = p_terrain_only
	placed_blocks = p_placed_blocks
	removed_blocks = p_removed_blocks
	foliage_clearance = p_foliage_clearance
	tree_blocks = p_tree_blocks
	copper_blocks = p_copper_blocks
	generate_copper = p_generate_copper
