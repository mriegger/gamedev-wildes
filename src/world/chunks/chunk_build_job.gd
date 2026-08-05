extends RefCounted
class_name ChunkBuildJob

var coord: Vector2i
var generation: int
var terrain_only: bool
var placed_blocks: Dictionary
var removed_blocks: Dictionary
var tree_blocks: Dictionary

func _init(p_coord: Vector2i, p_generation: int, p_terrain_only: bool, p_placed_blocks: Dictionary, p_removed_blocks: Dictionary, p_tree_blocks: Dictionary):
	coord = p_coord
	generation = p_generation
	terrain_only = p_terrain_only
	placed_blocks = p_placed_blocks
	removed_blocks = p_removed_blocks
	tree_blocks = p_tree_blocks
