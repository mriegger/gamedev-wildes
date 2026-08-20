extends Node
class_name PlayerFootsteps

signal step_committed(surface_block_id: int)

@export var catalog: FootstepAudioCatalog

@onready var _player: AudioStreamPlayer = $FootstepPlayer

var _motor: PlayerMotor
var _profile: BlockyHumanoidAnimationProfile
var _step_timer: float = 0.0
var _last_stream: AudioStream
var _water_state_initialized: bool = false
var _was_in_water: bool = false
var _base_volume_db: float

const MIN_PLANAR_SPEED: float = 0.2


func _ready():
	_base_volume_db = _player.volume_db


func setup(p_motor: PlayerMotor, p_profile: BlockyHumanoidAnimationProfile):
	assert(catalog != null and catalog.validate())
	_motor = p_motor
	_profile = p_profile
	_water_state_initialized = false
	if _player.stream == null:
		var fallback_profile := catalog.fallback_profile
		_player.stream = fallback_profile.streams[0]
		_player.volume_db = _base_volume_db + fallback_profile.volume_offset_db


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
			_commit_step(BlockId.Type.WATER)
			return
	if not _motor.on_ground:
		_step_timer = 0.0
		return
	var planar = Vector2(_motor.velocity.x, _motor.velocity.z).length()
	if planar < MIN_PLANAR_SPEED:
		_step_timer = 0.0
		return
	var cycle_seconds = _profile.sprint_cycle_seconds if _motor.is_sprinting else _profile.walk_cycle_seconds
	var interval = cycle_seconds * 0.5 / _motor.get_locomotion_speed_ratio()
	_step_timer += delta
	if _step_timer >= interval:
		_step_timer = 0.0
		_play_step()


func _play_step():
	_commit_step(_motor.get_footstep_surface_block_id())


func _commit_step(surface_block_id: int):
	_play_random_stream(catalog.get_profile(surface_block_id))
	step_committed.emit(surface_block_id)


func _play_random_stream(profile: FootstepAudioProfile):
	var stream := _select_random_stream(profile.streams)
	if stream == null:
		return
	_player.stop()
	_player.stream = stream
	_player.volume_db = _base_volume_db + profile.volume_offset_db
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
	if _player:
		_player.stop()
		_player.stream = null
		_player.volume_db = _base_volume_db
