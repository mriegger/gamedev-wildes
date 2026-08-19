extends RefCounted
class_name PreparedVoxelWorldChange

enum State {
	PREPARED,
	COMMITTED,
	NOTIFIED,
}

var _owner: RefCounted
var _expected_revisions: Dictionary
var _expected_contents: Dictionary
var _expected_transaction_sequence: int
var _operation: BlockEdit.Operation
var _position: Vector3i
var _new_id: int
var _attach_dir: Vector3i
var _cascade_positions: Array[Vector3i]
var _edits: Array[BlockEdit]
var _state: State = State.PREPARED

func _init(
	p_owner: RefCounted,
	p_expected_revisions: Dictionary,
	p_expected_contents: Dictionary,
	p_expected_transaction_sequence: int,
	p_operation: BlockEdit.Operation,
	p_position: Vector3i,
	p_new_id: int,
	p_attach_dir: Vector3i,
	p_cascade_positions: Array[Vector3i],
	p_edits: Array[BlockEdit],
) -> void:
	_owner = p_owner
	_expected_revisions = p_expected_revisions.duplicate()
	_expected_contents = p_expected_contents.duplicate(true)
	_expected_transaction_sequence = p_expected_transaction_sequence
	_operation = p_operation
	_position = p_position
	_new_id = p_new_id
	_attach_dir = p_attach_dir
	_cascade_positions = p_cascade_positions.duplicate()
	_edits = _copy_edits(p_edits)

func get_edits() -> Array[BlockEdit]:
	return _copy_edits(_edits)

func get_primary_edit() -> BlockEdit:
	if _edits.is_empty():
		return null
	return _edits[0].copy()

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _is_prepared() -> bool:
	return _state == State.PREPARED

func _get_expected_revisions() -> Dictionary:
	return _expected_revisions.duplicate()

func _get_expected_contents() -> Dictionary:
	return _expected_contents.duplicate(true)

func _get_expected_transaction_sequence() -> int:
	return _expected_transaction_sequence

func _get_operation() -> BlockEdit.Operation:
	return _operation

func _get_position() -> Vector3i:
	return _position

func _get_new_id() -> int:
	return _new_id

func _get_attach_dir() -> Vector3i:
	return _attach_dir

func _get_cascade_positions() -> Array[Vector3i]:
	return _cascade_positions.duplicate()

func _mark_committed(owner: RefCounted) -> bool:
	if not _is_for(owner) or _state != State.PREPARED:
		return false
	_state = State.COMMITTED
	return true

func _mark_notified(owner: RefCounted) -> bool:
	if not _is_for(owner) or _state != State.COMMITTED:
		return false
	_state = State.NOTIFIED
	return true

func _copy_committed_edits() -> Array[BlockEdit]:
	return _copy_edits(_edits)

static func _copy_edits(source: Array[BlockEdit]) -> Array[BlockEdit]:
	var copied: Array[BlockEdit] = []
	for edit in source:
		copied.append(edit.copy())
	return copied
