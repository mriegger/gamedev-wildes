extends RefCounted
class_name PreparedChestStorageChange

var _owner: RefCounted
var _expected_revision: int
var _position: Vector3i
var _slots: Array[InventoryStack]
var _result_stack: InventoryStack
var _result_stacks: Array[InventoryStack]

func _init(
	p_owner: RefCounted,
	p_expected_revision: int,
	p_position: Vector3i,
	p_slots: Array[InventoryStack],
	p_result_stack: InventoryStack = null,
	p_result_stacks: Array[InventoryStack] = [],
) -> void:
	_owner = p_owner
	_expected_revision = p_expected_revision
	_position = p_position
	_slots = _copy_slots(p_slots)
	_result_stack = null if p_result_stack == null else p_result_stack.copy()
	_result_stacks = _copy_result_stacks(p_result_stacks)
	if _result_stacks.is_empty() and _result_stack != null:
		_result_stacks.append(_result_stack.copy())

func get_result_stack() -> InventoryStack:
	return null if _result_stack == null else _result_stack.copy()

func get_result_stacks() -> Array[InventoryStack]:
	return _copy_result_stacks(_result_stacks)

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _get_expected_revision() -> int:
	return _expected_revision

func _get_position() -> Vector3i:
	return _position

func _copy_committed_slots() -> Array[InventoryStack]:
	return _copy_slots(_slots)

static func _copy_slots(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	copied.resize(source.size())
	for index in range(source.size()):
		if source[index] != null:
			copied[index] = source[index].copy()
	return copied

static func _copy_result_stacks(source: Array[InventoryStack]) -> Array[InventoryStack]:
	var copied: Array[InventoryStack] = []
	for stack in source:
		if stack != null:
			copied.append(stack.copy())
	return copied
