extends RefCounted
class_name InputBuffer

var move_dir: Vector2 = Vector2.ZERO
var jump_just: bool = false
var rotate_left_just: bool = false
var rotate_right_just: bool = false
var zoom_in_pressed: bool = false
var zoom_out_pressed: bool = false
var wheel_up: bool = false
var wheel_down: bool = false
var mine_pressed: bool = false
var place_just: bool = false
var mouse_right_pressed: bool = false
var mouse_left_pressed: bool = false

static var _instance: InputBuffer = null
static func shared() -> InputBuffer:
	if _instance == null:
		_instance = InputBuffer.new()
	return _instance

func poll():
	var move_right = Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D)
	var move_left = Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A)
	var move_forward = Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_W)
	var move_back = Input.is_action_pressed("move_back") or Input.is_key_pressed(KEY_S)
	var x = 0.0
	var y = 0.0
	if move_right:
		x += 1.0
	if move_left:
		x -= 1.0
	if move_forward:
		y += 1.0
	if move_back:
		y -= 1.0
	var v = Vector2(x, y)
	if v.length() > 1.0:
		v = v.normalized()
	move_dir = v
	zoom_in_pressed = Input.is_action_pressed("zoom_in")
	zoom_out_pressed = Input.is_action_pressed("zoom_out")
	mine_pressed = Input.is_action_pressed("mine")
	mouse_right_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	mouse_left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	jump_just = jump_just or Input.is_action_just_pressed("jump")
	rotate_left_just = rotate_left_just or Input.is_action_just_pressed("rotate_left")
	rotate_right_just = rotate_right_just or Input.is_action_just_pressed("rotate_right")
	place_just = place_just or Input.is_action_just_pressed("place")

func set_wheel(up: bool):
	if up:
		wheel_up = true
	else:
		wheel_down = true

func clear_wheel():
	wheel_up = false
	wheel_down = false

func consume_jump() -> bool:
	if jump_just:
		jump_just = false
		return true
	return false

func consume_rotate_left() -> bool:
	if rotate_left_just:
		rotate_left_just = false
		return true
	return false

func consume_rotate_right() -> bool:
	if rotate_right_just:
		rotate_right_just = false
		return true
	return false
