extends RefCounted
class_name PreparedPlayerMeleeAttack

var _owner: Object
var _source: SelectedItemSource
var _action: MeleeAttackActionDefinition
var _target_runtime_ids: Array[int]
var _ray_origin: Vector3
var _ray_direction: Vector3
var _consumed: bool = false

func _init(
	p_owner: Object,
	p_source: SelectedItemSource,
	p_action: MeleeAttackActionDefinition,
	p_target_runtime_ids: Array[int],
	p_ray_origin: Vector3,
	p_ray_direction: Vector3,
) -> void:
	_owner = p_owner
	_source = p_source
	_action = p_action
	_target_runtime_ids = p_target_runtime_ids.duplicate()
	_ray_origin = p_ray_origin
	_ray_direction = p_ray_direction

func get_action() -> MeleeAttackActionDefinition:
	return _action

func get_profile() -> MeleeAttackProfile:
	return _action.attack_profile

func get_target_runtime_ids() -> Array[int]:
	return _target_runtime_ids.duplicate()

func has_targets() -> bool:
	return not _target_runtime_ids.is_empty()

func _consume(owner: Object) -> bool:
	if _owner != owner or _consumed:
		return false
	_consumed = true
	return true

func _is_for(owner: Object) -> bool:
	return _owner == owner

func _get_source() -> SelectedItemSource:
	return _source

func _get_ray_origin() -> Vector3:
	return _ray_origin

func _get_ray_direction() -> Vector3:
	return _ray_direction
