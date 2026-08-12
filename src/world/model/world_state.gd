extends RefCounted
class_name WorldState

var seed: int
var placed_blocks: Dictionary
var removed_blocks: Dictionary
var torch_attachments: Dictionary
var player_position: Vector3
var copper_blocks: Dictionary
var generated_copper_chunks: Dictionary

func _init(p_seed: int, p_placed_blocks: Dictionary, p_removed_blocks: Dictionary, p_torch_attachments: Dictionary, p_player_position: Vector3, p_copper_blocks: Dictionary = {}, p_generated_copper_chunks: Dictionary = {}):
	seed = p_seed
	placed_blocks = p_placed_blocks
	removed_blocks = p_removed_blocks
	torch_attachments = p_torch_attachments
	player_position = p_player_position
	copper_blocks = p_copper_blocks
	generated_copper_chunks = p_generated_copper_chunks
