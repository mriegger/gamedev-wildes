extends Node
class_name EntityAnimationDriver

var actor: Node3D
var model_root: Node3D

func setup(p_actor: Node3D):
	actor = p_actor
	assert(actor != null)
	model_root = actor.get(&"model_root") as Node3D
	assert(model_root != null)

func advance(_delta: float):
	assert(false)

func play_attack(_duration: float):
	assert(false)

func play_hit(_local_hit_direction: Vector3 = Vector3.BACK):
	assert(false)

func play_death():
	assert(false)

func is_death_complete() -> bool:
	assert(false)
	return false

func get_death_time_remaining() -> float:
	assert(false)
	return 0.0
