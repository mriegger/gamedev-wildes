extends AudioStreamPlayer3D
class_name ZombieVocalizations

const INITIAL_DELAY_MIN_SECONDS: float = 2.0
const INITIAL_DELAY_MAX_SECONDS: float = 8.0
const INTERVAL_MIN_SECONDS: float = 6.0
const INTERVAL_MAX_SECONDS: float = 14.0
const PITCH_MIN: float = 0.96
const PITCH_MAX: float = 1.04
const RNG_SALT: int = 49734139

var _streams: Array[AudioStream] = [
	preload("res://assets/audio/entities/zombie/vocalizations/Zombie_02.mp3"),
	preload("res://assets/audio/entities/zombie/vocalizations/Zombie_04.mp3"),
	preload("res://assets/audio/entities/zombie/vocalizations/Zombie_05.mp3"),
	preload("res://assets/audio/entities/zombie/vocalizations/Zombie_12.mp3"),
	preload("res://assets/audio/entities/zombie/vocalizations/Zombie_13.mp3"),
	preload("res://assets/audio/entities/zombie/vocalizations/Zombie_14.mp3"),
]
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _remaining_seconds: float = 0.0
var _last_stream_index: int = -1


func _ready():
	set_process(false)


func setup(seed_value: int):
	assert(not _streams.is_empty())
	stop()
	stream = null
	_rng.seed = seed_value ^ RNG_SALT
	_last_stream_index = -1
	_remaining_seconds = _rng.randf_range(INITIAL_DELAY_MIN_SECONDS, INITIAL_DELAY_MAX_SECONDS)
	set_process(true)


func _process(delta: float):
	if playing:
		return
	_remaining_seconds -= delta
	if _remaining_seconds > 0.0:
		return
	_play_vocalization()
	_remaining_seconds = _rng.randf_range(INTERVAL_MIN_SECONDS, INTERVAL_MAX_SECONDS)


func stop_vocalizations():
	set_process(false)
	stop()
	stream = null


func _play_vocalization():
	var stream_index := _rng.randi_range(0, _streams.size() - 1)
	if _streams.size() > 1:
		while stream_index == _last_stream_index:
			stream_index = _rng.randi_range(0, _streams.size() - 1)
	_last_stream_index = stream_index
	stream = _streams[stream_index]
	pitch_scale = _rng.randf_range(PITCH_MIN, PITCH_MAX)
	play()


func _exit_tree():
	stop_vocalizations()
	_streams.clear()
