extends RefCounted
class_name BlockEdit

## BlockEdit - validated block change result, canonical AIR=0, uses BlockCatalog for rules

enum Result {
	SUCCESS = 0,
	FAIL_OUT_OF_BOUNDS = 1,
	FAIL_OCCUPIED = 2,
	FAIL_NOT_BREAKABLE = 3,
	FAIL_WORLD_EDGE = 4,
	FAIL_NO_SUPPORT = 5,
	FAIL_SAME_TYPE = 6,
	FAIL_INVALID_POS = 7,
	FAIL_Y_OUT_OF_RANGE = 8,
	FAIL_NO_TORCH_SUPPORT = 9,
	FAIL_STALE_REVISION = 10,
}

enum Operation {
	MINE = 0,
	PLACE = 1,
}

const RESULT_MESSAGES: Dictionary = {
	Result.SUCCESS: "Success",
	Result.FAIL_OUT_OF_BOUNDS: "Position out of world bounds",
	Result.FAIL_OCCUPIED: "Target occupied",
	Result.FAIL_NOT_BREAKABLE: "Block not breakable",
	Result.FAIL_WORLD_EDGE: "World border protected",
	Result.FAIL_NO_SUPPORT: "No support",
	Result.FAIL_SAME_TYPE: "Same block type",
	Result.FAIL_INVALID_POS: "Invalid position",
	Result.FAIL_Y_OUT_OF_RANGE: "Y out of build range",
	Result.FAIL_NO_TORCH_SUPPORT: "Torch requires adjacent opaque block",
	Result.FAIL_STALE_REVISION: "Stale revision",
}

var operation: Operation = Operation.PLACE
var pos: Vector3i = Vector3i.ZERO
var old_id: int = BlockId.Type.AIR
var new_id: int = BlockId.Type.AIR
var revision: int = 0
var prev_revision: int = 0
var result: Result = Result.SUCCESS
var reason: String = ""
var attach_dir: Vector3i = Vector3i.ZERO
var timestamp_ms: int = 0


func _init(p_op: Operation = Operation.PLACE, p_pos: Vector3i = Vector3i.ZERO):
	operation = p_op
	pos = p_pos
	timestamp_ms = Time.get_ticks_msec()

func is_success() -> bool:
	return result == Result.SUCCESS

func is_mine() -> bool:
	return operation == Operation.MINE

func is_place() -> bool:
	return operation == Operation.PLACE

func get_result_message() -> String:
	return RESULT_MESSAGES.get(result, "Unknown")

static func success_mine(p_pos: Vector3i, p_old_id: int, p_revision: int, p_prev_rev: int = 0) -> BlockEdit:
	var e = BlockEdit.new(Operation.MINE, p_pos)
	e.old_id = p_old_id
	e.new_id = BlockId.Type.AIR
	e.revision = p_revision
	e.prev_revision = p_prev_rev
	e.result = Result.SUCCESS
	return e

static func success_place(p_pos: Vector3i, p_new_id: int, p_revision: int, p_attach: Vector3i = Vector3i.ZERO, p_prev_rev: int = 0) -> BlockEdit:
	var e = BlockEdit.new(Operation.PLACE, p_pos)
	e.old_id = BlockId.Type.AIR
	e.new_id = p_new_id
	e.revision = p_revision
	e.prev_revision = p_prev_rev
	e.attach_dir = p_attach
	e.result = Result.SUCCESS
	return e

static func fail(p_pos: Vector3i, p_op: Operation, p_result: Result, p_reason: String = "") -> BlockEdit:
	var e = BlockEdit.new(p_op, p_pos)
	e.result = p_result
	e.reason = p_reason if p_reason != "" else RESULT_MESSAGES.get(p_result, "Failed")
	return e

func to_dict() -> Dictionary:
	return {
		"op": operation,
		"pos": pos,
		"old_id": old_id,
		"new_id": new_id,
		"rev": revision,
		"prev_rev": prev_revision,
		"result": result,
		"result_msg": get_result_message(),
		"reason": reason,
		"attach_dir": attach_dir,
		"timestamp": timestamp_ms,
		"success": is_success(),
	}

func _to_string() -> String:
	if is_success():
		if is_mine():
			return "[BlockEdit MINE %s %s->AIR rev %d]" % [pos, BlockId.get_display_name(old_id as BlockId.Type), revision]
		else:
			return "[BlockEdit PLACE %s AIR->%s rev %d attach %s]" % [pos, BlockId.get_display_name(new_id as BlockId.Type), revision, attach_dir]
	else:
		return "[BlockEdit FAIL %s %s: %s]" % [pos, Result.keys()[result] if result < Result.size() else result, reason]
