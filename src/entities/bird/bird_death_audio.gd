extends AudioStreamPlayer3D
class_name BirdDeathAudio

@export var streams: Array[AudioStream] = []
@export_range(0.01, 4.0, 0.01) var pitch_min: float = 0.96
@export_range(0.01, 4.0, 0.01) var pitch_max: float = 1.08
@export var rng_salt: int = 0

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _death_started: bool = false

func has_valid_presentation() -> bool:
	if streams.is_empty() or not is_finite(pitch_min) or not is_finite(pitch_max) or pitch_min <= 0.0 or pitch_max < pitch_min:
		return false
	for audio_stream in streams:
		if audio_stream == null:
			return false
	return true

func setup(seed_value: int) -> void:
	assert(has_valid_presentation())
	_rng.seed = seed_value ^ rng_salt
	_death_started = false
	stop_audio()

func play_death() -> void:
	if _death_started:
		return
	_death_started = true
	stream = streams[_rng.randi_range(0, streams.size() - 1)]
	pitch_scale = _rng.randf_range(pitch_min, pitch_max)
	play()

func stop_audio() -> void:
	stop()
	stream = null

func _exit_tree() -> void:
	stop_audio()
