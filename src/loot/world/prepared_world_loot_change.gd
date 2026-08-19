extends RefCounted
class_name PreparedWorldLootChange

var _owner: RefCounted
var _expected_revision: int
var _entries: Dictionary
var _entry_ids: Array[int]
var _next_entry_id: int
var _result_stack: InventoryStack
var _changes_entry_set: bool
var _minimum_next_equipment_instance_id: int
var _available: bool = true

func _init(
	p_owner: RefCounted,
	p_expected_revision: int,
	p_entries: Dictionary,
	p_entry_ids: Array[int],
	p_next_entry_id: int,
	p_result_stack: InventoryStack = null,
	p_changes_entry_set: bool = true,
	p_minimum_next_equipment_instance_id: int = 0,
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_entries = _copy_entries(p_entries)
	_entry_ids = p_entry_ids.duplicate()
	_next_entry_id = p_next_entry_id
	_result_stack = null if p_result_stack == null else p_result_stack.copy()
	_changes_entry_set = p_changes_entry_set
	_minimum_next_equipment_instance_id = p_minimum_next_equipment_instance_id

func get_expected_revision() -> int:
	return _expected_revision

func get_result_stack() -> InventoryStack:
	return null if _result_stack == null else _result_stack.copy()

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _is_available() -> bool:
	return _available

func _consume(owner: RefCounted) -> bool:
	if not _available or _owner != owner:
		return false
	_available = false
	return true

func _copy_committed_entries() -> Dictionary:
	return _copy_entries(_entries)

func _copy_committed_entry_ids() -> Array[int]:
	return _entry_ids.duplicate()

func _get_next_entry_id() -> int:
	return _next_entry_id

func _changes_entries() -> bool:
	return _changes_entry_set

func _get_minimum_next_equipment_instance_id() -> int:
	return _minimum_next_equipment_instance_id

static func _copy_entries(source: Dictionary) -> Dictionary:
	var copied: Dictionary = {}
	for entry_id in source:
		var entry := source[entry_id] as WorldLootEntry
		assert(entry != null)
		copied[entry_id] = entry.copy()
	return copied
