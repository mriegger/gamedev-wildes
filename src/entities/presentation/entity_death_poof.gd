extends CPUParticles3D
class_name EntityDeathPoof

var _played: bool = false
var _elapsed: float = 0.0

func play():
	assert(not _played)
	_played = true
	_elapsed = 0.0
	restart()
	emitting = true

func advance(delta: float) -> bool:
	assert(is_finite(delta) and delta >= 0.0)
	if not _played:
		return false
	_elapsed = minf(_elapsed + delta, lifetime)
	return _elapsed >= lifetime

func has_played() -> bool:
	return _played
