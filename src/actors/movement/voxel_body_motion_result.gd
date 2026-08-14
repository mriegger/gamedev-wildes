extends RefCounted
class_name VoxelBodyMotionResult

var position: Vector3
var velocity: Vector3

func _init(p_position: Vector3, p_velocity: Vector3):
	position = p_position
	velocity = p_velocity
