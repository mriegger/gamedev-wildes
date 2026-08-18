extends Node3D
class_name StoneGolemAudio

const MINIMUM_WALK_SPEED_RATIO: float = 0.05

@export var profile: StoneGolemAudioProfile
@export_node_path("AudioStreamPlayer3D") var walk_player_path: NodePath
@export_node_path("AudioStreamPlayer3D") var impact_player_path: NodePath
@export_node_path("AudioStreamPlayer3D") var death_player_path: NodePath

var walk_player: AudioStreamPlayer3D
var impact_player: AudioStreamPlayer3D
var death_player: AudioStreamPlayer3D
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _gait_contact_index: int = 0
var _last_walk_index: int = -1
var _last_impact_index: int = -1
var _last_death_index: int = -1
var _death_started: bool = false

func has_valid_presentation() -> bool:
	if profile == null or not profile.validate():
		return false
	if walk_player_path.is_empty() or impact_player_path.is_empty() or death_player_path.is_empty():
		return false
	return (
		get_node_or_null(walk_player_path) is AudioStreamPlayer3D
		and get_node_or_null(impact_player_path) is AudioStreamPlayer3D
		and get_node_or_null(death_player_path) is AudioStreamPlayer3D
	)

func setup(seed_value: int, gait_cycle_position: float) -> void:
	assert(has_valid_presentation())
	assert(is_finite(gait_cycle_position) and gait_cycle_position >= 0.0 and gait_cycle_position < 1.0)
	walk_player = get_node(walk_player_path) as AudioStreamPlayer3D
	impact_player = get_node(impact_player_path) as AudioStreamPlayer3D
	death_player = get_node(death_player_path) as AudioStreamPlayer3D
	_rng.seed = seed_value ^ profile.rng_salt
	_gait_contact_index = _get_gait_contact_index(gait_cycle_position)
	_last_walk_index = -1
	_last_impact_index = -1
	_last_death_index = -1
	_death_started = false
	_stop_player(walk_player)
	_stop_player(impact_player)
	_stop_player(death_player)

func advance_gait(gait_cycle_position: float, speed_ratio: float, grounded: bool) -> void:
	assert(is_finite(gait_cycle_position) and gait_cycle_position >= 0.0 and gait_cycle_position < 1.0)
	assert(is_finite(speed_ratio) and speed_ratio >= 0.0)
	if _death_started:
		return
	var gait_contact_index := _get_gait_contact_index(gait_cycle_position)
	if not grounded or speed_ratio <= MINIMUM_WALK_SPEED_RATIO:
		_gait_contact_index = gait_contact_index
		return
	if gait_contact_index == _gait_contact_index:
		return
	_gait_contact_index = gait_contact_index
	_last_walk_index = _play_random(
		walk_player,
		profile.walk_streams,
		_last_walk_index,
		profile.walk_pitch_min,
		profile.walk_pitch_max,
	)

func play_impact() -> void:
	if _death_started:
		return
	_last_impact_index = _play_random(
		impact_player,
		profile.impact_streams,
		_last_impact_index,
		profile.impact_pitch_min,
		profile.impact_pitch_max,
	)

func play_death() -> void:
	if _death_started:
		return
	_death_started = true
	_stop_player(walk_player)
	_stop_player(impact_player)
	_last_death_index = _play_random(
		death_player,
		profile.death_streams,
		_last_death_index,
		profile.death_pitch_min,
		profile.death_pitch_max,
	)

func stop_audio() -> void:
	_stop_player(walk_player)
	_stop_player(impact_player)
	_stop_player(death_player)

func _get_gait_contact_index(gait_cycle_position: float) -> int:
	return 0 if gait_cycle_position < 0.5 else 1

func _play_random(
	player: AudioStreamPlayer3D,
	streams: Array[AudioStream],
	last_index: int,
	pitch_min: float,
	pitch_max: float,
) -> int:
	var stream_index := _rng.randi_range(0, streams.size() - 1)
	if streams.size() > 1:
		while stream_index == last_index:
			stream_index = _rng.randi_range(0, streams.size() - 1)
	player.stop()
	player.stream = streams[stream_index]
	player.pitch_scale = _rng.randf_range(pitch_min, pitch_max)
	player.play()
	return stream_index

func _stop_player(player: AudioStreamPlayer3D) -> void:
	if player == null:
		return
	player.stop()
	player.stream = null

func _exit_tree() -> void:
	stop_audio()
