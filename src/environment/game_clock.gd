extends Node3D
class_name GameClock

const HOURS_PER_DAY: float = 24.0

@export var cycle_duration_minutes: float = 20.0
@export var start_hour: float = 6.0
@export var enable_cycle: bool = true
@export var pause_at_start: bool = false

var cycle_duration_seconds: float:
	get:
		return cycle_duration_minutes * 60.0

var time_of_day: float = 6.0
var _paused: bool = false
var _dragging: bool = false

signal time_changed(new_time: float)

func _ready():
	time_of_day = start_hour
	_paused = pause_at_start

func _process(delta):
	if enable_cycle and not _paused and not _dragging and not get_tree().paused:
		var hours_per_sec = HOURS_PER_DAY / cycle_duration_seconds
		var prev = time_of_day
		time_of_day += delta * hours_per_sec
		if time_of_day >= HOURS_PER_DAY:
			time_of_day -= HOURS_PER_DAY
		elif time_of_day < 0.0:
			time_of_day += HOURS_PER_DAY
		if not is_equal_approx(prev, time_of_day):
			time_changed.emit(time_of_day)

func get_time_of_day() -> float:
	return time_of_day

func set_time_of_day(h: float):
	time_of_day = fmod(h, HOURS_PER_DAY)
	if time_of_day < 0:
		time_of_day += HOURS_PER_DAY
	time_changed.emit(time_of_day)

func get_normalized() -> float:
	return clamp(time_of_day / HOURS_PER_DAY, 0.0, 1.0)

func get_phase() -> String:
	if not DayNightProfile.is_day_time(time_of_day):
		return "Night (7PM-6AM)"
	elif time_of_day >= 6.0 and time_of_day < 8.0:
		return "Sunrise (6AM-8AM)"
	elif time_of_day >= 8.0 and time_of_day < 17.0:
		return "Daytime (8AM-5PM)"
	else:
		return "Sundown (5PM-7PM)"

func set_paused(p: bool):
	_paused = p

func is_paused() -> bool:
	return _paused

func set_dragging(d: bool):
	_dragging = d

func get_formatted() -> String:
	var h = int(time_of_day)
	var m = int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]
