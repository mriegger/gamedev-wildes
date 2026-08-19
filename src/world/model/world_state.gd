extends RefCounted
class_name WorldState

var seed: int
var placed_blocks: Dictionary
var removed_blocks: Dictionary
var torch_attachments: Dictionary
var emplacements: Dictionary
var player_position: Vector3

func _init(p_seed: int, p_placed_blocks: Dictionary, p_removed_blocks: Dictionary, p_torch_attachments: Dictionary, p_emplacements: Dictionary, p_player_position: Vector3):
	seed = p_seed
	placed_blocks = p_placed_blocks
	removed_blocks = p_removed_blocks
	torch_attachments = p_torch_attachments
	emplacements = p_emplacements
	player_position = p_player_position
