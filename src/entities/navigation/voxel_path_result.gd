extends RefCounted
class_name VoxelPathResult

enum Status {
	FOUND,
	NO_PATH,
	INVALID_START,
	INVALID_GOAL,
	LIMIT_REACHED,
}

var status: Status
var path: Array[Vector3i]
var visited_nodes: int

func _init(p_status: Status, p_path: Array[Vector3i], p_visited_nodes: int):
	status = p_status
	path = p_path
	visited_nodes = p_visited_nodes

func is_success() -> bool:
	return status == Status.FOUND
