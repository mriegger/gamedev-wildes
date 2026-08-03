extends Node3D
class_name CameraRig

@export var min_ortho_size: float = 18.0
@export var max_ortho_size: float = 90.0
@export var zoom_speed: float = 10.0
@export var follow_lerp: float = 10.0
@export var yaw_lerp_speed: float = 5.5
@export var pitch_deg: float = -45.0
@export var orbit_distance: float = 70.0

@onready var pitch: Node3D = $Pitch
@onready var camera: Camera3D = $Pitch/Camera3D

var target_yaw_deg: float = 225.0
var current_yaw_deg: float = 225.0
var target_position: Vector3 = Vector3(100, 0, 100)

var _player: PlayerMotor = null

func setup(p_player: PlayerMotor):
	_player = p_player
	target_position = p_player.global_position

func _ready():
	current_yaw_deg = target_yaw_deg
	rotation_degrees.y = current_yaw_deg
	if pitch:
		pitch.rotation_degrees.x = pitch_deg
	if camera:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.transform.origin = Vector3(0, 0, orbit_distance)
		camera.size = 42.0
		camera.near = 0.1
		camera.far = 1000.0
		camera.current = true

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			InputBuffer.shared().set_wheel(true)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			InputBuffer.shared().set_wheel(false)
	elif event is InputEventMagnifyGesture:
		_zoom((1.0 - event.factor) * 35.0)
	elif event is InputEventPanGesture:
		if abs(event.delta.y) > 0.001:
			_zoom(event.delta.y * 4.0)

func _process(delta):
	var ib = InputBuffer.shared()
	if ib.consume_rotate_left():
		target_yaw_deg -= 45.0
	if ib.consume_rotate_right():
		target_yaw_deg += 45.0

	if ib.wheel_up:
		_zoom(-2.5)
		ib.clear_wheel()
	if ib.wheel_down:
		_zoom(2.5)
		ib.clear_wheel()

	current_yaw_deg = _lerp_angle_deg(current_yaw_deg, target_yaw_deg, delta * yaw_lerp_speed)
	rotation_degrees.y = current_yaw_deg

	if pitch:
		pitch.rotation_degrees.x = pitch_deg
		if camera and not camera.transform.origin.is_equal_approx(Vector3(0, 0, orbit_distance)):
			camera.transform.origin = Vector3(0, 0, orbit_distance)

	if _player:
		target_position = _player.global_position
	global_position = global_position.lerp(target_position, delta * follow_lerp)

	if ib.zoom_in_pressed:
		_zoom(-zoom_speed * delta)
	if ib.zoom_out_pressed:
		_zoom(zoom_speed * delta)

func _zoom(amount: float):
	if camera == null:
		return
	camera.size = clamp(camera.size + amount, min_ortho_size, max_ortho_size)

func _lerp_angle_deg(from_deg: float, to_deg: float, weight: float) -> float:
	var from_rad = deg_to_rad(from_deg)
	var to_rad = deg_to_rad(to_deg)
	var diff = wrapf(to_rad - from_rad, -PI, PI)
	return rad_to_deg(from_rad + diff * weight)

func get_camera_basis() -> Basis:
	if camera:
		return camera.global_transform.basis
	return global_transform.basis

func get_flat_forward() -> Vector3:
	var f = -get_camera_basis().z
	f.y = 0
	if f.length_squared() < 0.0001:
		f = Vector3(0, 0, -1)
	return f.normalized()

func get_flat_right() -> Vector3:
	var r = get_camera_basis().x
	r.y = 0
	if r.length_squared() < 0.0001:
		r = Vector3(1, 0, 0)
	return r.normalized()
