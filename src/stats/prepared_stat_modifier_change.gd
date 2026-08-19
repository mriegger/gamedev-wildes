extends RefCounted
class_name PreparedStatModifierChange

var _expected_revision: int
var _owner: RefCounted
var _modifiers: Dictionary
var _remaining_duration: Dictionary
var _current_hp: float
var _changes_state: bool
var _target_source_instance_ids: Array[StringName]
var _loadout_authorized: bool

func _init(
	p_owner: RefCounted,
	p_expected_revision: int,
	p_modifiers: Dictionary,
	p_remaining_duration: Dictionary,
	p_current_hp: float,
	p_changes_state: bool,
	p_target_source_instance_ids: Array[StringName],
	p_loadout_authorized: bool,
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_modifiers = _duplicate_modifiers(p_modifiers)
	_remaining_duration = p_remaining_duration.duplicate(true)
	_current_hp = p_current_hp
	_changes_state = p_changes_state
	_target_source_instance_ids = p_target_source_instance_ids.duplicate()
	_loadout_authorized = p_loadout_authorized

func get_expected_revision() -> int:
	return _expected_revision

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _copy_modifiers() -> Dictionary:
	return _duplicate_modifiers(_modifiers)

func _copy_remaining_duration() -> Dictionary:
	return _remaining_duration.duplicate(true)

func _get_current_hp() -> float:
	return _current_hp

func _has_state_change() -> bool:
	return _changes_state

func _get_target_source_instance_ids() -> Array[StringName]:
	return _target_source_instance_ids.duplicate()

func _targets_any_source_instance(source_instance_ids: Dictionary) -> bool:
	for source_instance_id in _target_source_instance_ids:
		if source_instance_ids.has(source_instance_id):
			return true
	return false

func _targets_only_source_instances(source_instance_ids: Dictionary) -> bool:
	for source_instance_id in _target_source_instance_ids:
		if not source_instance_ids.has(source_instance_id):
			return false
	return true

func _is_loadout_authorized() -> bool:
	return _loadout_authorized

func _duplicate_modifiers(source: Dictionary) -> Dictionary:
	var copied: Dictionary = {}
	for modifier_id in source:
		var modifier := source[modifier_id] as StatModifier
		assert(modifier != null)
		copied[modifier_id] = modifier.duplicate() as StatModifier
	return copied
