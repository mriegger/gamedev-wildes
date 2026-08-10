extends Node
class_name PlayerFootsteps

@onready var _player: AudioStreamPlayer = $FootstepPlayer

var _motor: PlayerMotor
var _profile: BlockyHumanoidAnimationProfile
var _step_timer: float = 0.0
var _last_idx: int = -1

var _streams: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_01.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_02.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_03.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_04.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_05.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_06.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_07.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_08.wav"),
	preload("res://assets/audio/footsteps/dirt/Footstep_Dirt_09.wav"),
]

const MIN_PLANAR_SPEED: float = 0.2


func setup(p_motor: PlayerMotor, p_profile: BlockyHumanoidAnimationProfile):
	_motor = p_motor
	_profile = p_profile
	if _player.stream == null and _streams.size() > 0:
		_player.stream = _streams[0]


func _process(delta: float):
	if _motor == null:
		return
	if not _motor.on_ground:
		_step_timer = 0.0
		return
	var planar = Vector2(_motor.velocity.x, _motor.velocity.z).length()
	if planar < MIN_PLANAR_SPEED:
		_step_timer = 0.0
		return
	var cycle_seconds = _profile.sprint_cycle_seconds if _motor.is_sprinting else _profile.walk_cycle_seconds
	var interval = cycle_seconds * 0.5
	_step_timer += delta
	if _step_timer >= interval:
		_step_timer = 0.0
		_play_step()


func _play_step():
	if _streams.is_empty():
		return
	var idx = randi_range(0, _streams.size() - 1)
	if _streams.size() > 1:
		while idx == _last_idx:
			idx = randi_range(0, _streams.size() - 1)
		_last_idx = idx
	_player.stream = _streams[idx]
	_player.pitch_scale = randf_range(0.92, 1.08)
	_player.play()


func _exit_tree():
	_motor = null
	_profile = null
	_streams.clear()
	if _player:
		_player.stream = null
		_player.stop()
