extends RefCounted
class_name VoxelPathFollowResult

var desired_velocity: Vector3
var should_jump: bool
var path_failed: bool

func _init(p_desired_velocity: Vector3, p_should_jump: bool, p_path_failed: bool):
	desired_velocity = p_desired_velocity
	should_jump = p_should_jump
	path_failed = p_path_failed
