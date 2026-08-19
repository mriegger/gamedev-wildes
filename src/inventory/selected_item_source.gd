extends RefCounted
class_name SelectedItemSource

var _owner: RefCounted
var _slot_index: int
var _item_id: StringName
var _equipment_instance_id: int
var _stack_fingerprint: String

func _init(
	p_owner: RefCounted,
	p_slot_index: int,
	p_item_id: StringName,
	p_equipment_instance_id: int,
	p_stack_fingerprint: String,
) -> void:
	_owner = p_owner
	_slot_index = p_slot_index
	_item_id = p_item_id
	_equipment_instance_id = p_equipment_instance_id
	_stack_fingerprint = p_stack_fingerprint

func get_item_id() -> StringName:
	return _item_id

func _matches(
	p_owner: RefCounted,
	p_slot_index: int,
	p_item_id: StringName,
	p_equipment_instance_id: int,
	p_stack_fingerprint: String,
) -> bool:
	return (
		_owner == p_owner
		and _slot_index == p_slot_index
		and _item_id == p_item_id
		and _equipment_instance_id == p_equipment_instance_id
		and _stack_fingerprint == p_stack_fingerprint
	)
