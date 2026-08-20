extends RefCounted
class_name PreparedDungeonChestClaim

var _owner: RefCounted
var _expected_revision: int
var _reward_id: StringName
var _stacks: Array[InventoryStack]
var _committed: bool = false

func _init(
	p_owner: RefCounted,
	p_expected_revision: int,
	p_reward_id: StringName,
	p_stacks: Array[InventoryStack],
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_reward_id = p_reward_id
	_stacks = _copy_stacks(p_stacks)

func get_reward_id() -> StringName:
	return _reward_id

func get_stacks() -> Array[InventoryStack]:
	return _copy_stacks(_stacks)

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

static func _copy_stacks(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	for stack in source:
		copied.append(stack.copy())
	return copied
