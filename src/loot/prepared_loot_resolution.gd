extends RefCounted
class_name PreparedLootResolution

var _owner: EquipmentInstanceFactory
var _expected_next_instance_id: int
var _pending_next_instance_id: int
var _drops: Array[InventoryStack]
var _committed: bool = false

func _init(
	p_owner: EquipmentInstanceFactory,
	p_expected_next_instance_id: int,
	p_pending_next_instance_id: int,
	p_drops: Array[InventoryStack],
) -> void:
	_owner = p_owner
	_expected_next_instance_id = p_expected_next_instance_id
	_pending_next_instance_id = p_pending_next_instance_id
	_drops = _copy_drops(p_drops)

func get_drops() -> Array[InventoryStack]:
	return _copy_drops(_drops)

func _get_pending_next_instance_id() -> int:
	return _pending_next_instance_id

func _is_for(owner: EquipmentInstanceFactory) -> bool:
	return _owner == owner

func _is_prepared() -> bool:
	return not _committed

func _get_expected_next_instance_id() -> int:
	return _expected_next_instance_id

func _mark_committed(owner: EquipmentInstanceFactory) -> bool:
	if not _is_for(owner) or _committed:
		return false
	_committed = true
	return true

static func _copy_drops(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	for stack in source:
		copied.append(stack.copy())
	return copied
