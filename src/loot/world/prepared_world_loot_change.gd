extends RefCounted
class_name PreparedWorldLootChange

var _owner: RefCounted
var _expected_revision: int
var _entries: Dictionary
var _entry_ids: Array[int]
var _next_entry_id: int
var _minimum_next_equipment_instance_id: int
var _available: bool = true

func _init(
	p_owner: RefCounted,
	p_expected_revision: int,
	p_entries: Dictionary,
	p_entry_ids: Array[int],
	p_next_entry_id: int,
	p_minimum_next_equipment_instance_id: int,
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_entries = _copy_entries(p_entries, p_entry_ids)
	_entry_ids = p_entry_ids.duplicate()
	_next_entry_id = p_next_entry_id
	_minimum_next_equipment_instance_id = p_minimum_next_equipment_instance_id

func get_expected_revision() -> int:
	return _expected_revision

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _is_available() -> bool:
	return _available

func _get_minimum_next_equipment_instance_id() -> int:
	return _minimum_next_equipment_instance_id

func _copy_committed_entries() -> Dictionary:
	return _copy_entries(_entries, _entry_ids)

func _copy_committed_entry_ids() -> Array[int]:
	return _entry_ids.duplicate()

func _get_next_entry_id() -> int:
	return _next_entry_id

func _consume(owner: RefCounted) -> bool:
	if not _available or not _is_for(owner):
		return false
	_available = false
	return true

static func _copy_entries(source: Dictionary, entry_ids: Array[int]) -> Dictionary:
	var copied: Dictionary = {}
	for entry_id in entry_ids:
		copied[entry_id] = (source[entry_id] as WorldLootEntry).copy()
	return copied
