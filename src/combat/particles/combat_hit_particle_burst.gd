extends Node3D
class_name CombatHitParticleBurst

const UPWARD_BIAS: float = 0.65

@onready var _primary: CPUParticles3D = $Primary as CPUParticles3D
@onready var _accent: CPUParticles3D = $Accent as CPUParticles3D

func play(position: Vector3, hit_direction: Vector3, primary_color: Color, accent_color: Color):
	assert(position.is_finite())
	assert(hit_direction.is_finite() and not hit_direction.is_zero_approx())
	global_position = position
	var launch_direction := (hit_direction.normalized() + Vector3.UP * UPWARD_BIAS).normalized()
	_play_emitter(_primary, launch_direction, primary_color)
	_play_emitter(_accent, launch_direction, accent_color)

func _play_emitter(emitter: CPUParticles3D, launch_direction: Vector3, tint: Color):
	emitter.direction = launch_direction
	emitter.color = tint
	emitter.restart()
	emitter.emitting = true
