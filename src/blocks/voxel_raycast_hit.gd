extends RefCounted
class_name VoxelRaycastHit

var target_cell: Vector3i:
	get:
		return _target_cell

var placement_cell: Vector3i:
	get:
		return _placement_cell

var face_normal: Vector3i:
	get:
		return _face_normal

var ray_distance: float:
	get:
		return _ray_distance

var _target_cell: Vector3i
var _placement_cell: Vector3i
var _face_normal: Vector3i
var _ray_distance: float

func _init(p_target_cell: Vector3i, p_placement_cell: Vector3i, p_face_normal: Vector3i, p_ray_distance: float) -> void:
	_target_cell = p_target_cell
	_placement_cell = p_placement_cell
	_face_normal = p_face_normal
	_ray_distance = p_ray_distance
