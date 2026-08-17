extends RefCounted
class_name EntityTargetObservation

const CAMERA_AXIS_MIN_SINE_SQUARED: float = 0.000001

var player_position: Vector3:
	get:
		return _player_position
var camera_origin: Vector3:
	get:
		return _camera_origin
var camera_forward: Vector3:
	get:
		return _camera_forward
var camera_right: Vector3:
	get:
		return _camera_right

var _player_position: Vector3
var _camera_origin: Vector3
var _camera_forward: Vector3
var _camera_right: Vector3

func _init(
	p_player_position: Vector3,
	p_camera_origin: Vector3,
	p_camera_forward: Vector3,
	p_camera_right: Vector3,
) -> void:
	assert(_values_are_valid(p_player_position, p_camera_origin, p_camera_forward, p_camera_right))
	_player_position = p_player_position
	_camera_origin = p_camera_origin
	_camera_forward = p_camera_forward.normalized()
	_camera_right = (p_camera_right - _camera_forward * p_camera_right.dot(_camera_forward)).normalized()

static func create(
	player_position: Vector3,
	camera_origin: Vector3,
	camera_forward: Vector3,
	camera_right: Vector3,
) -> EntityTargetObservation:
	if not _values_are_valid(player_position, camera_origin, camera_forward, camera_right):
		return null
	return EntityTargetObservation.new(player_position, camera_origin, camera_forward, camera_right)

static func from_camera_values(
	player_position: Vector3,
	camera_transform: Transform3D,
	horizontal_offset: float,
	vertical_offset: float,
) -> EntityTargetObservation:
	if not camera_transform.is_finite() or not is_finite(horizontal_offset) or not is_finite(vertical_offset):
		return null
	var camera_basis := camera_transform.basis.orthonormalized()
	var camera_origin := camera_transform.origin + camera_basis.x * horizontal_offset + camera_basis.y * vertical_offset
	return create(player_position, camera_origin, -camera_basis.z, camera_basis.x)

func validate() -> bool:
	return (
		_values_are_valid(_player_position, _camera_origin, _camera_forward, _camera_right)
		and is_equal_approx(_camera_forward.length_squared(), 1.0)
		and is_equal_approx(_camera_right.length_squared(), 1.0)
		and is_zero_approx(_camera_forward.dot(_camera_right))
	)

static func _values_are_valid(
	player_position: Vector3,
	camera_origin: Vector3,
	camera_forward: Vector3,
	camera_right: Vector3,
) -> bool:
	if not player_position.is_finite() or not camera_origin.is_finite():
		return false
	if not camera_forward.is_finite() or camera_forward.is_zero_approx():
		return false
	if not camera_right.is_finite() or camera_right.is_zero_approx():
		return false
	var normalized_forward := camera_forward.normalized()
	var normalized_right := camera_right.normalized()
	return normalized_forward.cross(normalized_right).length_squared() >= CAMERA_AXIS_MIN_SINE_SQUARED
