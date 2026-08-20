extends RefCounted
class_name PreparedDungeonRewardClaim

enum State {
	PREPARED,
	COMMITTED,
	NOTIFIED,
}

var _owner: DungeonProgressState
var _expected_revision: int
var _instance_id: StringName
var _reward_id: StringName
var _state: State = State.PREPARED

func _init(
	p_owner: DungeonProgressState,
	p_expected_revision: int,
	p_instance_id: StringName,
	p_reward_id: StringName,
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_instance_id = p_instance_id
	_reward_id = p_reward_id

func _is_for(owner: DungeonProgressState) -> bool:
	return _owner == owner

func _is_prepared() -> bool:
	return _state == State.PREPARED

func _get_expected_revision() -> int:
	return _expected_revision

func _get_instance_id() -> StringName:
	return _instance_id

func _get_reward_id() -> StringName:
	return _reward_id

func _mark_committed(owner: DungeonProgressState) -> bool:
	if not _is_for(owner) or _state != State.PREPARED:
		return false
	_state = State.COMMITTED
	return true

func _mark_notified(owner: DungeonProgressState) -> bool:
	if not _is_for(owner) or _state != State.COMMITTED:
		return false
	_state = State.NOTIFIED
	return true
