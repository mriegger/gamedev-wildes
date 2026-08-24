extends RefCounted
class_name PreparedApplePlantChange

enum State {
	PREPARED,
	COMMITTED,
	NOTIFIED,
}

var _owner: Object
var _expected_revision: int
var _soil_position: Vector3i
var _expected_block_revisions: Dictionary
var _state: State = State.PREPARED

func _init(
	p_owner: Object,
	p_expected_revision: int,
	p_soil_position: Vector3i,
	p_expected_block_revisions: Dictionary,
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_soil_position = p_soil_position
	_expected_block_revisions = p_expected_block_revisions.duplicate()

func _is_for(owner: Object) -> bool:
	return _owner == owner

func _is_prepared() -> bool:
	return _state == State.PREPARED

func _get_expected_revision() -> int:
	return _expected_revision

func _get_soil_position() -> Vector3i:
	return _soil_position

func _get_expected_block_revisions() -> Dictionary:
	return _expected_block_revisions.duplicate()

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
