extends RefCounted
class_name InputBuffer

var move_dir: Vector2 = Vector2.ZERO
var sprint_pressed: bool = false
var jump_just: bool = false
var rotate_left_just: bool = false
var rotate_right_just: bool = false
var zoom_in_pressed: bool = false
var zoom_out_pressed: bool = false
var wheel_up: bool = false
var wheel_down: bool = false
var mine_pressed: bool = false
var place_just: bool = false
var place_pressed: bool = false

func poll():
	var move_right = Input.is_action_pressed("move_right")
	var move_left = Input.is_action_pressed("move_left")
	var move_forward = Input.is_action_pressed("move_forward")
	var move_back = Input.is_action_pressed("move_back")
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
	if v.length_squared() > 1.0:
		v = v.normalized()
	move_dir = v
	sprint_pressed = Input.is_action_pressed("sprint")
	zoom_in_pressed = Input.is_action_pressed("zoom_in")
	zoom_out_pressed = Input.is_action_pressed("zoom_out")
	mine_pressed = Input.is_action_pressed("mine")
	place_pressed = Input.is_action_pressed("place")
	jump_just = jump_just or Input.is_action_just_pressed("jump")
	rotate_left_just = rotate_left_just or Input.is_action_just_pressed("rotate_left")
	rotate_right_just = rotate_right_just or Input.is_action_just_pressed("rotate_right")
	place_just = place_just or Input.is_action_just_pressed("place")

func clear_gameplay():
	move_dir = Vector2.ZERO
	sprint_pressed = false
	jump_just = false
	rotate_left_just = false
	rotate_right_just = false
	zoom_in_pressed = false
	zoom_out_pressed = false
	wheel_up = false
	wheel_down = false
	mine_pressed = false
	place_just = false
	place_pressed = false

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
