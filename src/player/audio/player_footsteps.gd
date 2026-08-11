extends Node
class_name PlayerFootsteps

@onready var _player: AudioStreamPlayer = $FootstepPlayer

var _motor: PlayerMotor
var _profile: BlockyHumanoidAnimationProfile
var _step_timer: float = 0.0
var _last_stream: AudioStream
var _water_state_initialized: bool = false
var _was_in_water: bool = false

var _dirt_streams: Array[AudioStream] = [
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

var _water_streams: Array[AudioStream] = [
	preload("res://assets/audio/footsteps/water/Footstep_Water_00.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_01.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_02.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_03.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_04.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_05.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_06.wav"),
	preload("res://assets/audio/footsteps/water/Footstep_Water_07.wav"),
]

const MIN_PLANAR_SPEED: float = 0.2


func setup(p_motor: PlayerMotor, p_profile: BlockyHumanoidAnimationProfile):
	_motor = p_motor
	_profile = p_profile
	_water_state_initialized = false
	if _player.stream == null and not _dirt_streams.is_empty():
		_player.stream = _dirt_streams[0]


func _process(delta: float):
	if _motor == null:
		return
	var is_in_water := _motor.is_in_water()
	if not _water_state_initialized:
		_water_state_initialized = true
		_was_in_water = is_in_water
	elif is_in_water != _was_in_water:
		_was_in_water = is_in_water
		if is_in_water:
			_step_timer = 0.0
			_play_random_stream(_water_streams)
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
	var streams := _water_streams if _motor.is_in_water() else _dirt_streams
	_play_random_stream(streams)


func _play_random_stream(streams: Array[AudioStream]):
	var stream := _select_random_stream(streams)
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.pitch_scale = randf_range(0.92, 1.08)
	_player.play()


func _select_random_stream(streams: Array[AudioStream]) -> AudioStream:
	if streams.is_empty():
		return null
	var idx := randi_range(0, streams.size() - 1)
	if streams.size() > 1:
		while streams[idx] == _last_stream:
			idx = randi_range(0, streams.size() - 1)
	_last_stream = streams[idx]
	return _last_stream


func _exit_tree():
	_motor = null
	_profile = null
	_last_stream = null
	_water_state_initialized = false
	_was_in_water = false
	_dirt_streams.clear()
	_water_streams.clear()
	if _player:
		_player.stop()
		_player.stream = null
