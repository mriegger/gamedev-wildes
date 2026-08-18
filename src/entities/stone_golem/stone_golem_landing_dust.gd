extends CPUParticles3D
class_name StoneGolemLandingDust

var _play_count: int = 0

func _ready() -> void:
	top_level = true
	emitting = false

func play_at(world_position: Vector3) -> void:
	assert(world_position.is_finite())
	global_position = world_position
	_play_count += 1
	restart()
	emitting = true

func get_play_count() -> int:
	return _play_count
