extends Node3D
class_name CameraRig

@export var min_ortho_size: float = 18.0
@export var max_ortho_size: float = 70.0
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

var _follow_target: Node3D = null
var _input_buffer: InputBuffer = null

var _right_obstruction_progress: float = 0.0
var _right_obstruction_width: float = 380.0

func set_right_obstruction_progress(progress: float):
	_right_obstruction_progress = clamp(progress, 0.0, 1.0)
	_update_right_obstruction_offset()

func set_right_obstruction_width(width_px: float):
	_right_obstruction_width = width_px
	_update_right_obstruction_offset()

func reset_right_obstruction():
	_right_obstruction_progress = 0.0
	_update_right_obstruction_offset()

func _update_right_obstruction_offset():
	if camera == null:
		return
	if _right_obstruction_progress == 0.0 and camera.h_offset == 0.0:
		return
	var viewport_size = Vector2(1280, 720)
	var vp = get_viewport()
	if vp != null:
		var rect = vp.get_visible_rect()
		if rect.size.y > 1.0:
			viewport_size = rect.size
	var world_per_px = camera.size / viewport_size.y if viewport_size.y > 0 else 0.0
	var pixel_shift = _right_obstruction_width * _right_obstruction_progress * 0.5
	var world_shift = pixel_shift * world_per_px
	camera.h_offset = world_shift
	camera.v_offset = 0.0

func setup(p_follow_target: Node3D, p_input_buffer: InputBuffer):
	_follow_target = p_follow_target
	_input_buffer = p_input_buffer
	target_position = p_follow_target.global_position
	set_process(true)
	set_process_unhandled_input(true)

func _ready():
	set_process(false)
	set_process_unhandled_input(false)
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
	get_viewport().size_changed.connect(_update_right_obstruction_offset)

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_input_buffer.set_wheel(true)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_input_buffer.set_wheel(false)
	elif event is InputEventMagnifyGesture:
		_zoom((1.0 - event.factor) * 35.0)
	elif event is InputEventPanGesture:
		if abs(event.delta.y) > 0.001:
			_zoom(event.delta.y * 4.0)

func _process(delta):
	var ib = _input_buffer
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

	if not is_equal_approx(current_yaw_deg, target_yaw_deg):
		current_yaw_deg = _lerp_angle_deg(current_yaw_deg, target_yaw_deg, delta * yaw_lerp_speed)
		rotation_degrees.y = current_yaw_deg

	if _follow_target:
		target_position = _follow_target.global_position
	if not global_position.is_equal_approx(target_position):
		global_position = global_position.lerp(target_position, delta * follow_lerp)

	if ib.zoom_in_pressed:
		_zoom(-zoom_speed * delta)
	if ib.zoom_out_pressed:
		_zoom(zoom_speed * delta)

func _zoom(amount: float):
	if camera == null:
		return
	camera.size = clamp(camera.size + amount, min_ortho_size, max_ortho_size)
	_update_right_obstruction_offset()

func _lerp_angle_deg(from_deg: float, to_deg: float, weight: float) -> float:
	var from_rad = deg_to_rad(from_deg)
	var to_rad = deg_to_rad(to_deg)
	var diff = wrapf(to_rad - from_rad, -PI, PI)
	return rad_to_deg(from_rad + diff * weight)

func get_camera_basis() -> Basis:
	return camera.global_transform.basis
