extends Node
class_name AmbientSoundscape

@onready var _birds_player: AudioStreamPlayer = $BirdsPlayer

var _clock: GameClock
var _ambient_volume: float = 1.0
var _birds_enabled: bool = true
var _day_factor: float = 1.0
var _running: bool = false

var _birds_stream: AudioStream = preload("res://assets/audio/ambient/nri-DawnchorusinAmphitheater.mp3")


func setup(p_clock: GameClock):
	_clock = p_clock
	_clock.time_changed.connect(_on_time_changed)
	_day_factor = _get_day_factor(_clock.get_time_of_day())
	if _birds_player.stream == null:
		_birds_player.stream = _birds_stream
	_apply_volumes()


func start():
	_running = true
	_day_factor = _get_day_factor(_clock.get_time_of_day())
	_apply_volumes()
	if _day_factor > 0.01 and _birds_enabled:
		if not _birds_player.playing:
			_birds_player.play()


func stop():
	_running = false
	_birds_player.stop()


func _exit_tree():
	stop()
	if _clock != null and _clock.time_changed.is_connected(_on_time_changed):
		_clock.time_changed.disconnect(_on_time_changed)
	_clock = null
	if _birds_player:
		_birds_player.stream = null
	_birds_stream = null


func set_volume(volume: float):
	_ambient_volume = clampf(volume, 0.0, 1.0)
	_apply_volumes()


func set_birds_enabled(enabled: bool):
	_birds_enabled = enabled
	if not enabled:
		_birds_player.stop()
	elif _running and _day_factor > 0.01:
		if not _birds_player.playing:
			_birds_player.play()
	_apply_volumes()


func apply_settings(settings: GameSettings):
	set_volume(settings.ambient_volume)
	set_birds_enabled(settings.birds_enabled)


func _on_time_changed(new_time: float):
	_day_factor = _get_day_factor(new_time)
	_apply_volumes()
	if not _running:
		return
	if _day_factor <= 0.01:
		_birds_player.stop()
	else:
		if _birds_enabled and not _birds_player.playing:
			_birds_player.play()


func _apply_volumes():
	var birds_linear = _ambient_volume * _day_factor * 0.5 if _birds_enabled else 0.0
	_birds_player.volume_db = linear_to_db(birds_linear) if birds_linear > 0.001 else -80.0


func _get_day_factor(t: float) -> float:
	if t < 6.0 or t >= 19.0:
		return 0.0
	if t < 8.0:
		return inverse_lerp(6.0, 8.0, t)
	if t < 17.0:
		return 1.0
	return 1.0 - inverse_lerp(17.0, 19.0, t)
