extends Node3D
class_name GameEnvironment

signal sky_color_changed(sky_color: Color)

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _sun_fill: DirectionalLight3D = $SunFill
@onready var _clock: GameClock = $GameClock
@onready var _values: DayNightValues = $DayNightValues
@onready var _debug_clock_panel: DebugClockPanel = $DebugClockPanel
@onready var _ambient_soundscape: Node = $AmbientSoundscape

func _ready():
	_values.sky_color_changed.connect(sky_color_changed.emit)

func setup(time_of_day: float, shadow_cast_distance: float):
	_values.setup(_clock, _sun, _sun_fill, _world_environment, shadow_cast_distance)
	_clock.setup(time_of_day)
	_ambient_soundscape.setup(_clock)

func start_clock():
	_debug_clock_panel.inject(_clock, _values)
	_ambient_soundscape.start()
	_clock.start()

func apply_settings(settings: GameSettings):
	_values.volumetric_fog_enabled = settings.volumetric_fog_enabled
	_values.set_shadow_enabled(settings.sun_shadows_enabled)
	_values.set_shadow_max_distance(settings.get_shadow_distance())
	_ambient_soundscape.apply_settings(settings)

func get_time_of_day() -> float:
	return _clock.get_time_of_day()

func get_formatted_time() -> String:
	return _clock.get_formatted()
