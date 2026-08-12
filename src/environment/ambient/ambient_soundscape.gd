extends Node
class_name AmbientSoundscape

const BIRDS_VOLUME_SCALE: float = 0.5
const NIGHT_VOLUME_SCALE: float = 0.05

@onready var _birds_player: AudioStreamPlayer = $BirdsPlayer
@onready var _night_player: AudioStreamPlayer = $NightPlayer

var _clock: GameClock
var _ambient_volume: float = 1.0
var _birds_enabled: bool = true
var _day_factor: float = 1.0
var _night_factor: float = 0.0
var _running: bool = false

var _birds_stream: AudioStream = preload("res://assets/audio/ambient/nri-DawnchorusinAmphitheater.mp3")
var _night_stream: AudioStream = preload("res://assets/audio/ambient/forest_night_avocado.ogg")


func setup(p_clock: GameClock):
	_clock = p_clock
	_clock.time_changed.connect(_on_time_changed)
	_day_factor = _get_day_factor(_clock.get_time_of_day())
	_night_factor = 1.0 - _day_factor
	if _birds_player.stream == null:
		_birds_player.stream = _birds_stream
	if _night_player.stream == null:
		_night_player.stream = _night_stream
	_apply_volumes()


func start():
	_running = true
	_day_factor = _get_day_factor(_clock.get_time_of_day())
	_night_factor = 1.0 - _day_factor
	_apply_volumes()
	_sync_playback()


func stop():
	_running = false
	_birds_player.stop()
	_night_player.stop()


func _exit_tree():
	stop()
	if _clock != null and _clock.time_changed.is_connected(_on_time_changed):
		_clock.time_changed.disconnect(_on_time_changed)
	_clock = null
	if _birds_player:
		_birds_player.stream = null
	if _night_player:
		_night_player.stream = null
	_birds_stream = null
	_night_stream = null


func set_volume(volume: float):
	_ambient_volume = clampf(volume, 0.0, 1.0)
	_apply_volumes()


func set_birds_enabled(enabled: bool):
	_birds_enabled = enabled
	_apply_volumes()
	if _running:
		_sync_playback()


func apply_settings(settings: GameSettings):
	set_volume(settings.ambient_volume)
	set_birds_enabled(settings.birds_enabled)


func _on_time_changed(new_time: float):
	_day_factor = _get_day_factor(new_time)
	_night_factor = 1.0 - _day_factor
	_apply_volumes()
	if not _running:
		return
	_sync_playback()


func _apply_volumes():
	var birds_linear = _ambient_volume * _day_factor * BIRDS_VOLUME_SCALE if _birds_enabled else 0.0
	var night_linear = _ambient_volume * _night_factor * NIGHT_VOLUME_SCALE
	_birds_player.volume_db = linear_to_db(birds_linear) if birds_linear > 0.001 else -80.0
	_night_player.volume_db = linear_to_db(night_linear) if night_linear > 0.001 else -80.0


func _sync_playback():
	if _birds_enabled and _day_factor > 0.01:
		if not _birds_player.playing:
			_birds_player.play()
	else:
		_birds_player.stop()
	if _night_factor > 0.01:
		if not _night_player.playing:
			_night_player.play()
	else:
		_night_player.stop()


func _get_day_factor(t: float) -> float:
	if t < 6.0 or t >= 19.0:
		return 0.0
	if t < 8.0:
		return inverse_lerp(6.0, 8.0, t)
	if t < 17.0:
		return 1.0
	return 1.0 - inverse_lerp(17.0, 19.0, t)
