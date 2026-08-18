extends RefCounted
class_name BlockEdit

enum Result {
	SUCCESS = 0,
	FAIL_OCCUPIED = 2,
	FAIL_NOT_BREAKABLE = 3,
	FAIL_NO_SUPPORT = 5,
	FAIL_INVALID_POS = 7,
	FAIL_Y_OUT_OF_RANGE = 8,
	FAIL_NO_TORCH_SUPPORT = 9,
	FAIL_PROTECTED = 10,
	FAIL_BLOCK_CHANGED = 11,
}

enum Operation {
	MINE = 0,
	PLACE = 1,
	REPLACE = 2,
	PICK_UP = 3,
}

const RESULT_MESSAGES: Dictionary = {
	Result.SUCCESS: "Success",
	Result.FAIL_OCCUPIED: "Target occupied",
	Result.FAIL_NOT_BREAKABLE: "Block not breakable",
	Result.FAIL_NO_SUPPORT: "No support",
	Result.FAIL_INVALID_POS: "Invalid position",
	Result.FAIL_Y_OUT_OF_RANGE: "Y out of build range",
	Result.FAIL_NO_TORCH_SUPPORT: "Torch requires adjacent opaque block",
	Result.FAIL_PROTECTED: "Protected structure",
	Result.FAIL_BLOCK_CHANGED: "Target block changed",
}

var operation: Operation = Operation.PLACE
var pos: Vector3i = Vector3i.ZERO
var old_id: int = BlockId.Type.AIR
var new_id: int = BlockId.Type.AIR
var revision: int = 0
var result: Result = Result.SUCCESS
var reason: String = ""
var attach_dir: Vector3i = Vector3i.ZERO

func _init(p_op: Operation, p_pos: Vector3i):
	operation = p_op
	pos = p_pos

func is_success() -> bool:
	return result == Result.SUCCESS

func is_mine() -> bool:
	return operation == Operation.MINE

func is_place() -> bool:
	return operation == Operation.PLACE

func is_replace() -> bool:
	return operation == Operation.REPLACE

func is_pick_up() -> bool:
	return operation == Operation.PICK_UP

static func success_mine(p_pos: Vector3i, p_old_id: int, p_revision: int) -> BlockEdit:
	var e = BlockEdit.new(Operation.MINE, p_pos)
	e.old_id = p_old_id
	e.new_id = BlockId.Type.AIR
	e.revision = p_revision
	e.result = Result.SUCCESS
	return e

static func success_place(p_pos: Vector3i, p_new_id: int, p_revision: int, p_attach: Vector3i) -> BlockEdit:
	var e = BlockEdit.new(Operation.PLACE, p_pos)
	e.old_id = BlockId.Type.AIR
	e.new_id = p_new_id
	e.revision = p_revision
	e.attach_dir = p_attach
	e.result = Result.SUCCESS
	return e

static func success_replace(p_pos: Vector3i, p_old_id: int, p_new_id: int, p_revision: int) -> BlockEdit:
	var e = BlockEdit.new(Operation.REPLACE, p_pos)
	e.old_id = p_old_id
	e.new_id = p_new_id
	e.revision = p_revision
	e.result = Result.SUCCESS
	return e

static func success_pick_up(p_pos: Vector3i, p_old_id: int, p_revision: int) -> BlockEdit:
	var e = BlockEdit.new(Operation.PICK_UP, p_pos)
	e.old_id = p_old_id
	e.new_id = BlockId.Type.AIR
	e.revision = p_revision
	e.result = Result.SUCCESS
	return e

static func fail(p_pos: Vector3i, p_op: Operation, p_result: Result, p_reason: String = "") -> BlockEdit:
	var e = BlockEdit.new(p_op, p_pos)
	e.result = p_result
	e.reason = p_reason if p_reason != "" else RESULT_MESSAGES.get(p_result, "Failed")
	return e

func _to_string() -> String:
	if is_success():
		if is_mine():
			return "[BlockEdit MINE %s %s->AIR rev %d]" % [pos, BlockId.get_display_name(old_id as BlockId.Type), revision]
		if is_replace():
			return "[BlockEdit REPLACE %s %s->%s rev %d]" % [pos, BlockId.get_display_name(old_id as BlockId.Type), BlockId.get_display_name(new_id as BlockId.Type), revision]
		if is_pick_up():
			return "[BlockEdit PICK_UP %s %s->AIR rev %d]" % [pos, BlockId.get_display_name(old_id as BlockId.Type), revision]
		return "[BlockEdit PLACE %s AIR->%s rev %d attach %s]" % [pos, BlockId.get_display_name(new_id as BlockId.Type), revision, attach_dir]
	return "[BlockEdit FAIL %s %s: %s]" % [pos, Result.find_key(result), reason]
