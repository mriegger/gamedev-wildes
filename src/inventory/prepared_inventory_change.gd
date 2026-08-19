extends RefCounted
class_name PreparedInventoryChange

var _expected_revision: int
var _owner: RefCounted
var _expected_next_instance_id: int
var _next_instance_id: int
var _slots: Array[InventoryStack]
var _selected_slot: int
var _starter_item_migration_version: int
var _result_stack: InventoryStack

func _init(
	p_owner: RefCounted,
	p_expected_revision: int,
	p_expected_next_instance_id: int,
	p_next_instance_id: int,
	p_slots: Array[InventoryStack],
	p_selected_slot: int,
	p_starter_item_migration_version: int,
	p_result_stack: InventoryStack = null,
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_expected_next_instance_id = p_expected_next_instance_id
	_next_instance_id = p_next_instance_id
	_slots = _copy_slots(p_slots)
	_selected_slot = p_selected_slot
	_starter_item_migration_version = p_starter_item_migration_version
	_result_stack = null if p_result_stack == null else p_result_stack.copy()

func get_expected_revision() -> int:
	return _expected_revision

func get_size() -> int:
	return _slots.size()

func get_slot(index: int) -> InventoryStack:
	if index < 0 or index >= _slots.size():
		return null
	return null if _slots[index] == null else _slots[index].copy()

func get_selected_slot() -> int:
	return _selected_slot

func get_selected_data() -> InventoryStack:
	return get_slot(_selected_slot)

func get_result_stack() -> InventoryStack:
	return null if _result_stack == null else _result_stack.copy()

func _get_expected_next_instance_id() -> int:
	return _expected_next_instance_id

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _get_next_instance_id() -> int:
	return _next_instance_id

func _get_starter_item_migration_version() -> int:
	return _starter_item_migration_version

func _copy_committed_slots() -> Array[InventoryStack]:
	return _copy_slots(_slots)

static func _copy_slots(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	copied.resize(source.size())
	for index in range(source.size()):
		if source[index] != null:
			copied[index] = source[index].copy()
	return copied
