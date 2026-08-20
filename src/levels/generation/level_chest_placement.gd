extends RefCounted
class_name LevelChestPlacement

var room_id: int
var cell: Vector3i
var loot_pool: LootPoolDefinition
var post_first_completion_loot_pool: LootPoolDefinition

func _init(
	p_room_id: int,
	p_cell: Vector3i,
	p_loot_pool: LootPoolDefinition,
	p_post_first_completion_loot_pool: LootPoolDefinition,
) -> void:
	assert(p_room_id >= 0)
	assert(p_loot_pool != null)
	room_id = p_room_id
	cell = p_cell
	loot_pool = p_loot_pool
	post_first_completion_loot_pool = p_post_first_completion_loot_pool
