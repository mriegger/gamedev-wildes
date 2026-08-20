extends RefCounted
class_name PreparedDungeonRunQualification

var _owner: RefCounted
var _expected_revision: int
var _committed: bool = false

func _init(p_owner: RefCounted, p_expected_revision: int) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _get_expected_revision() -> int:
	return _expected_revision

func _is_prepared() -> bool:
	return not _committed

func _mark_committed(owner: RefCounted) -> bool:
	if not _is_for(owner) or _committed:
		return false
	_committed = true
	return true
