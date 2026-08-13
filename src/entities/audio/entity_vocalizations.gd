extends AudioStreamPlayer3D
class_name EntityVocalizations

@export var profile: EntityVocalizationProfile

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _remaining_seconds: float = 0.0
var _last_stream_index: int = -1


func _ready():
	set_process(false)


func setup(seed_value: int):
	assert(profile != null and profile.validate())
	stop()
	stream = null
	_rng.seed = seed_value ^ profile.rng_salt
	_last_stream_index = -1
	_remaining_seconds = _rng.randf_range(profile.initial_delay_min_seconds, profile.initial_delay_max_seconds)
	set_process(true)


func _process(delta: float):
	if playing:
		return
	_remaining_seconds -= delta
	if _remaining_seconds > 0.0:
		return
	_play_vocalization()
	_remaining_seconds = _rng.randf_range(profile.interval_min_seconds, profile.interval_max_seconds)


func stop_vocalizations():
	set_process(false)
	stop()
	stream = null


func _play_vocalization():
	var stream_index := _rng.randi_range(0, profile.streams.size() - 1)
	if profile.streams.size() > 1:
		while stream_index == _last_stream_index:
			stream_index = _rng.randi_range(0, profile.streams.size() - 1)
	_last_stream_index = stream_index
	stream = profile.streams[stream_index]
	pitch_scale = _rng.randf_range(profile.pitch_min, profile.pitch_max)
	play()


func _exit_tree():
	stop_vocalizations()
