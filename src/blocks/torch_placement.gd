extends RefCounted
class_name TorchPlacement

const ATTACH_OFFSET: float = 0.32
const DOWN_Y_OFFSET: float = 0.15
const CARDINAL_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
]

static func world_position(block_pos: Vector3i, attach_dir: Vector3i) -> Vector3:
	var base_pos = Vector3(block_pos.x + 0.5, block_pos.y + 0.5, block_pos.z + 0.5)
	if attach_dir != Vector3i.ZERO:
		base_pos += Vector3(attach_dir.x, attach_dir.y, attach_dir.z) * ATTACH_OFFSET
		if attach_dir == Vector3i.DOWN:
			base_pos.y = float(block_pos.y) + DOWN_Y_OFFSET
	return base_pos
