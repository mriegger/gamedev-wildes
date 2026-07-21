extends Node3D

# Isometric orthographic camera that orbits around player
# Q/E = smooth 90° quarter orbit around player, wheel = zoom
# Pitch = -45° classic iso, camera at (0,0,dist) in Pitch local so it looks at rig origin (player)

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
var target_position: Vector3 = Vector3(100,0,100)
var _player: Node3D = null

func _ready():
	# preferred view is after two E presses from initial 45° -> 135°, but user still needed two more, so 225° is best
	# force start to 225° if coming from older scene
	current_yaw_deg = target_yaw_deg
	rotation_degrees.y = current_yaw_deg
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
	_find_player()
	print("[CameraRig] Ready pitch %.1f yaw %.1f dist %.1f" % [pitch_deg, current_yaw_deg, orbit_distance])

func _find_player():
	_player = get_node_or_null("../Player") as Node3D
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node3D

func _test_find_player():
	_find_player()

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-2.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(2.5)
	elif event is InputEventMagnifyGesture:
		# trackpad pinch zoom - factor >1 = zoom in (reduce ortho size)
		_zoom((1.0 - event.factor) * 35.0)
	elif event is InputEventPanGesture:
		# trackpad two-finger scroll - use vertical delta for zoom, horizontal ignore to avoid conflict
		if abs(event.delta.y) > 0.001:
			_zoom(event.delta.y * 4.0)

func _process(delta):
	if _player == null:
		_find_player()
	
	# Q/E orbit around player - 45° steps, 8 directions (fixes 180° double-trigger bug)
	if Input.is_action_just_pressed("rotate_left"):
		target_yaw_deg -= 45.0
	if Input.is_action_just_pressed("rotate_right"):
		target_yaw_deg += 45.0
	
	current_yaw_deg = _lerp_angle_deg(current_yaw_deg, target_yaw_deg, delta * yaw_lerp_speed)
	rotation_degrees.y = current_yaw_deg
	
	if pitch:
		pitch.rotation_degrees.x = pitch_deg
		if camera and not camera.transform.origin.is_equal_approx(Vector3(0,0,orbit_distance)):
			camera.transform.origin = Vector3(0,0,orbit_distance)
	
	if _player:
		target_position = _player.global_position
	global_position = global_position.lerp(target_position, delta * follow_lerp)
	
	if Input.is_action_pressed("zoom_in"):
		_zoom(-zoom_speed * delta)
	if Input.is_action_pressed("zoom_out"):
		_zoom(zoom_speed * delta)

# No direct KEY_Q handling here to avoid double-triggering with input actions (was causing back-and-forth swap)
func _input(_event):
	pass

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
		f = Vector3(0,0,-1)
	return f.normalized()

func get_flat_right() -> Vector3:
	var r = get_camera_basis().x
	r.y = 0
	if r.length_squared() < 0.0001:
		r = Vector3(1,0,0)
	return r.normalized()
