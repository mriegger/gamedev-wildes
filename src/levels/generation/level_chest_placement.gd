extends RefCounted
class_name LevelChestPlacement

var room_id: int
var cell: Vector3i
var loot_bundle: LootBundleDefinition

func _init(p_room_id: int, p_cell: Vector3i, p_loot_bundle: LootBundleDefinition) -> void:
	assert(p_room_id >= 0)
	assert(p_loot_bundle != null)
	room_id = p_room_id
	cell = p_cell
	loot_bundle = p_loot_bundle
