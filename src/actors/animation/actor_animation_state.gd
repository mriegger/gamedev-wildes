extends RefCounted
class_name ActorAnimationState

var local_velocity: Vector3 = Vector3.ZERO
var speed_ratio: float = 0.0
var sprinting: bool = false
var grounded: bool = false
var jump_anticipation: float = 0.0
var turn_rate: float = 0.0
var has_look_target: bool = false
var local_look_direction: Vector3 = Vector3.ZERO

func set_motion(p_local_velocity: Vector3, p_speed_ratio: float, p_sprinting: bool, p_grounded: bool, p_jump_anticipation: float, p_turn_rate: float, p_has_look_target: bool, p_local_look_direction: Vector3):
	local_velocity = p_local_velocity
	speed_ratio = p_speed_ratio
	sprinting = p_sprinting
	grounded = p_grounded
	jump_anticipation = p_jump_anticipation
	turn_rate = p_turn_rate
	has_look_target = p_has_look_target
	local_look_direction = p_local_look_direction
