extends Node3D
class_name BowHeldView

const UPPER_STRING_TIP := Vector3(-0.18, 0.68, 0.0)
const LOWER_STRING_TIP := Vector3(-0.18, -0.68, 0.0)
const REST_STRING_CENTER := Vector3(-0.18, 0.0, 0.0)
const STRING_SEGMENT_LENGTH: float = 0.68

@onready var plane_pivot: Node3D = $DepthPivot/PlanePivot as Node3D
@onready var upper_string: MeshInstance3D = $DepthPivot/PlanePivot/UpperString as MeshInstance3D
@onready var lower_string: MeshInstance3D = $DepthPivot/PlanePivot/LowerString as MeshInstance3D

var _rest_basis: Basis
var _nocked_arrow: NockableArrowView
var _string_center: Vector3 = REST_STRING_CENTER

func _ready() -> void:
	_rest_basis = basis
	_set_string_center(REST_STRING_CENTER)

func set_draw_pose(active: bool, raise_progress: float, draw_progress: float, full_draw_distance: float, arrow_scene: PackedScene, launch_direction: Vector3) -> void:
	if not active:
		reset_draw_pose()
		return
	assert(arrow_scene != null)
	assert(launch_direction.is_finite() and not launch_direction.is_zero_approx())
	assert(is_finite(full_draw_distance) and full_draw_distance > 0.0 and full_draw_distance <= 1.0)
	var forward := launch_direction
	var launch_angle := asin(clampf(forward.y, -1.0, 1.0))
	forward.y = 0.0
	if forward.is_zero_approx():
		forward = Vector3.BACK
	else:
		forward = forward.normalized()
	var actor_right := Vector3.UP.cross(forward).normalized()
	var level_basis := Basis(actor_right, -forward, Vector3.UP)
	var target_basis := Basis(Quaternion(actor_right, -launch_angle)) * level_basis
	var parent_node := get_parent() as Node3D
	var parent_basis := parent_node.global_transform.basis.orthonormalized()
	var authored_global_basis := parent_basis * _rest_basis.orthonormalized()
	var pose_weight := smoothstep(0.0, 1.0, clampf(raise_progress, 0.0, 1.0))
	var desired_global_basis := authored_global_basis.slerp(target_basis, pose_weight)
	basis = (parent_basis.inverse() * desired_global_basis).orthonormalized().scaled(_rest_basis.get_scale())
	var draw_weight := smoothstep(0.0, 1.0, clampf(draw_progress, 0.0, 1.0))
	var authored_string_center := REST_STRING_CENTER + Vector3.LEFT * full_draw_distance * draw_weight
	var string_center := REST_STRING_CENTER.lerp(authored_string_center, pose_weight)
	_set_string_center(string_center)
	_ensure_nocked_arrow(arrow_scene)
	_position_nocked_arrow(string_center)

func reset_draw_pose() -> void:
	basis = _rest_basis
	_set_string_center(REST_STRING_CENTER)
	if _nocked_arrow != null:
		_nocked_arrow.free()
		_nocked_arrow = null

func get_nock_global_position() -> Vector3:
	return plane_pivot.to_global(_string_center)

func set_nocked_arrow_global_transform(projectile_transform: Transform3D) -> void:
	assert(_nocked_arrow != null and projectile_transform.is_finite())
	var nock_global_position := projectile_transform * _nocked_arrow.nock_local_position
	_set_string_center(plane_pivot.to_local(nock_global_position))
	_nocked_arrow.global_transform = projectile_transform

func _set_string_center(center: Vector3) -> void:
	_string_center = center
	_set_string_segment(upper_string, center, UPPER_STRING_TIP)
	_set_string_segment(lower_string, center, LOWER_STRING_TIP)

func _set_string_segment(segment: MeshInstance3D, start: Vector3, end: Vector3) -> void:
	var direction := end - start
	var length := direction.length()
	assert(length > 0.0)
	segment.position = (start + end) * 0.5
	segment.quaternion = Quaternion(Vector3.UP, direction.normalized())
	segment.scale = Vector3(1.0, length / STRING_SEGMENT_LENGTH, 1.0)

func _ensure_nocked_arrow(arrow_scene: PackedScene) -> void:
	if _nocked_arrow != null:
		return
	_nocked_arrow = arrow_scene.instantiate() as NockableArrowView
	assert(_nocked_arrow != null)
	plane_pivot.add_child(_nocked_arrow)
	_nocked_arrow.rotation = Vector3(0.0, 0.0, -PI * 0.5)

func _position_nocked_arrow(string_center: Vector3) -> void:
	_nocked_arrow.position = string_center - _nocked_arrow.basis * _nocked_arrow.nock_local_position
