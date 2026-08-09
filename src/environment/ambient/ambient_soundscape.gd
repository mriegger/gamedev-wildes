extends Node
class_name AmbientSoundscape

@onready var _birds_player: AudioStreamPlayer = $BirdsPlayer
@onready var _insects_player: AudioStreamPlayer = $InsectsPlayer
@onready var _birds_timer: Timer = $TimerBirds
@onready var _insects_timer: Timer = $TimerInsects

var _clock: GameClock
var _ambient_volume: float = 1.0
var _birds_enabled: bool = true
var _insects_enabled: bool = true
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
	if (1.0 - _day_factor) > 0.01 and _insects_enabled and _insects_timer.is_stopped():
		_insects_timer.start(randf_range(3.0, 7.0))


func stop():
	_running = false
	_birds_timer.stop()
	_insects_timer.stop()
	_birds_player.stop()
	_insects_player.stop()


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


func set_insects_enabled(enabled: bool):
	_insects_enabled = enabled
	if not enabled:
		_insects_timer.stop()
		_insects_player.stop()
	elif _running and (1.0 - _day_factor) > 0.01 and _insects_timer.is_stopped():
		_insects_timer.start(randf_range(1.0, 4.0))
	_apply_volumes()


func apply_settings(settings: GameSettings):
	set_volume(settings.ambient_volume)
	set_birds_enabled(settings.birds_enabled)
	set_insects_enabled(settings.insects_enabled)


func _on_time_changed(new_time: float):
	_day_factor = _get_day_factor(new_time)
	_apply_volumes()
	if not _running:
		return
	var night_factor = 1.0 - _day_factor
	if _day_factor <= 0.01:
		_birds_player.stop()
	else:
		if _birds_enabled and not _birds_player.playing:
			_birds_player.play()
	if night_factor <= 0.01:
		_insects_timer.stop()
	else:
		if _insects_enabled and _insects_timer.is_stopped():
			_insects_timer.start(randf_range(4.0, 10.0))


func _apply_volumes():
	var birds_linear = _ambient_volume * _day_factor if _birds_enabled else 0.0
	var insects_linear = _ambient_volume * (1.0 - _day_factor) if _insects_enabled else 0.0
	_birds_player.volume_db = linear_to_db(birds_linear) if birds_linear > 0.001 else -80.0
	_insects_player.volume_db = linear_to_db(insects_linear) if insects_linear > 0.001 else -80.0


func _get_day_factor(t: float) -> float:
	if t < 6.0 or t >= 19.0:
		return 0.0
	if t < 8.0:
		return inverse_lerp(6.0, 8.0, t)
	if t < 17.0:
		return 1.0
	return 1.0 - inverse_lerp(17.0, 19.0, t)


func _on_birds_timer_timeout():
	if not _birds_enabled or _day_factor <= 0.01:
		return
	if not _running:
		return
	if not _birds_player.playing:
		_birds_player.play()


func _on_insects_timer_timeout():
	if not _insects_enabled:
		return
	var night_factor = 1.0 - _day_factor
	if night_factor <= 0.01:
		return
	if not _running:
		return
	if _insects_player.stream == null:
		_insects_timer.start(randf_range(5.0, 15.0))
		return
	_insects_player.pitch_scale = randf_range(0.95, 1.05)
	if not _insects_player.playing:
		_insects_player.play()
	_insects_timer.start(randf_range(5.0, 15.0))
