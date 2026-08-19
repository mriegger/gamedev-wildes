extends RefCounted
class_name PreparedHarvestChange

enum State {
	PREPARED,
	COMMITTED,
	NOTIFIED,
}

var _owner: Object
var _expected_revision: int
var _target_id: int
var _harvest_item_ids: Array[StringName]
var _state: State = State.PREPARED

func _init(
	p_owner: Object,
	p_expected_revision: int,
	p_target_id: int,
	p_harvest_item_ids: Array[StringName],
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_target_id = p_target_id
	_harvest_item_ids = p_harvest_item_ids.duplicate()

func get_harvest_item_ids() -> Array[StringName]:
	return _harvest_item_ids.duplicate()

func _is_for(owner: Object) -> bool:
	return _owner == owner

func _is_prepared() -> bool:
	return _state == State.PREPARED

func _get_expected_revision() -> int:
	return _expected_revision

func _get_target_id() -> int:
	return _target_id

func _mark_committed(owner: Object) -> bool:
	if not _is_for(owner) or _state != State.PREPARED:
		return false
	_state = State.COMMITTED
	return true

func _mark_notified(owner: Object) -> bool:
	if not _is_for(owner) or _state != State.COMMITTED:
		return false
	_state = State.NOTIFIED
	return true
