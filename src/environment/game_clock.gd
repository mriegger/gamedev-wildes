extends Node3D
class_name GameClock

## GameClock - advances game time and emits normalized time and phase changes
## Extracted from DayNightCycle into environment/ module

@export var cycle_duration_minutes: float = 20.0 # 10 day +10 night =20 total
@export var start_hour: float = 6.0 # sunrise
@export var enable_cycle: bool = true
@export var pause_at_start: bool = false

var cycle_duration_seconds: float:
	get:
		return cycle_duration_minutes * 60.0

var time_of_day: float = 6.0 # 0..24
var _paused: bool = false
var _dragging: bool = false # set by debug panel when slider dragged

signal time_changed(new_time: float)
signal normalized_time_changed(norm: float) # 0..1
signal phase_changed(new_phase: String)
signal hour_changed(hour: int, minute: int)
signal day_advanced()

var _last_phase: String = ""
var _last_hour: int = -1


func _ready():
	time_of_day = start_hour
	_paused = pause_at_start
	_last_phase = get_phase()
	_last_hour = int(time_of_day)


func _process(delta):
	if enable_cycle and not _paused and not _dragging and not get_tree().paused:
		var hours_per_sec = 24.0 / cycle_duration_seconds
		var prev = time_of_day
		time_of_day += delta * hours_per_sec
		if time_of_day >= 24.0:
			time_of_day -= 24.0
			day_advanced.emit()
		elif time_of_day < 0.0:
			time_of_day += 24.0
		if not is_equal_approx(prev, time_of_day):
			time_changed.emit(time_of_day)
			normalized_time_changed.emit(get_normalized())

	# hour + phase emit
	var cur_hour = int(time_of_day)
	if cur_hour != _last_hour:
		_last_hour = cur_hour
		var m = int((time_of_day - cur_hour) * 60.0)
		hour_changed.emit(cur_hour, m)

	var cur_phase = get_phase()
	if cur_phase != _last_phase:
		_last_phase = cur_phase
		phase_changed.emit(cur_phase)


func get_time_of_day() -> float:
	return time_of_day


func set_time_of_day(h: float):
	var prev_phase = get_phase()
	time_of_day = fmod(h, 24.0)
	if time_of_day < 0:
		time_of_day += 24.0
	time_changed.emit(time_of_day)
	normalized_time_changed.emit(get_normalized())
	var np = get_phase()
	if np != prev_phase:
		phase_changed.emit(np)


func get_normalized() -> float:
	return clamp(time_of_day / 24.0, 0.0, 1.0)


func get_phase() -> String:
	if time_of_day >= 19.0 or time_of_day < 6.0:
		return "Night (7PM-6AM)"
	elif time_of_day >= 6.0 and time_of_day < 8.0:
		return "Sunrise (6AM-8AM)"
	elif time_of_day >= 8.0 and time_of_day < 17.0:
		return "Daytime (8AM-5PM)"
	else:
		return "Sundown (5PM-7PM)"


func is_day() -> bool:
	return time_of_day >= 6.0 and time_of_day < 19.0


func is_night() -> bool:
	return not is_day()


func pause():
	_paused = true

func resume():
	_paused = false

func set_paused(p: bool):
	_paused = p

func is_paused() -> bool:
	return _paused

func set_dragging(d: bool):
	_dragging = d

func advance(delta_hours: float):
	set_time_of_day(time_of_day + delta_hours)


func get_formatted() -> String:
	var h = int(time_of_day)
	var m = int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]
