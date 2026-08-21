extends Node3D
class_name GameEnvironment

signal sky_color_changed(sky_color: Color)

@onready var _world_environment: WorldEnvironment = $WorldEnvironment
@onready var _sun: DirectionalLight3D = $Sun
@onready var _sun_fill: DirectionalLight3D = $SunFill
@onready var _clock: GameClock = $GameClock
@onready var _values: DayNightValues = $DayNightValues
@onready var _debug_clock_panel: DebugClockPanel = $DebugClockPanel
@onready var _ambient_soundscape: AmbientSoundscape = $AmbientSoundscape as AmbientSoundscape
@onready var _music: ContextualMusicPlayer = $Music as ContextualMusicPlayer
@onready var _music_debug_panel: MusicDebugPanel = $MusicDebugPanel as MusicDebugPanel

func _ready():
	_values.sky_color_changed.connect(sky_color_changed.emit)

func setup(time_of_day: float, shadow_cast_distance: float, music_seed: int):
	_values.setup(_clock, _sun, _sun_fill, _world_environment, shadow_cast_distance)
	_clock.setup(time_of_day)
	_ambient_soundscape.setup(_clock)
	_music.setup(_clock, music_seed)

func start_clock():
	_debug_clock_panel.inject(_clock, _values)
	_music_debug_panel.setup(_music)
	_ambient_soundscape.start()
	_music.start()
	_clock.start()

func set_outdoor_presentation_enabled(enabled: bool):
	_world_environment.environment = _values.env if enabled else null
	_sun.visible = enabled
	_sun_fill.visible = enabled
	if enabled:
		_ambient_soundscape.start()
		_music.start()
	else:
		_ambient_soundscape.stop()
		_music.stop()

func set_dungeon_music_active(active: bool) -> void:
	if active:
		_music.set_dungeon_active(true)
		_music.start()
	else:
		_music.stop()
		_music.set_dungeon_active(false)

func apply_settings(settings: GameSettings):
	_values.volumetric_fog_enabled = settings.volumetric_fog_enabled
	_values.set_shadow_enabled(settings.sun_shadows_enabled)
	_values.set_shadow_max_distance(settings.get_shadow_distance())
	_ambient_soundscape.apply_settings(settings)
	_music.apply_settings(settings)

func get_time_of_day() -> float:
	return _clock.get_time_of_day()

func get_formatted_time() -> String:
	return _clock.get_formatted()

func set_clock_paused(paused: bool) -> void:
	_clock.set_paused(paused)

func is_clock_paused() -> bool:
	return _clock.is_paused()

func close_debug_panel():
	_debug_clock_panel.disable_input()
	_music_debug_panel.disable_input()

func restore_debug_panel_input():
	_debug_clock_panel.enable_input()
	_music_debug_panel.enable_input()

func is_debug_panel_open() -> bool:
	return _debug_clock_panel.is_open() or _music_debug_panel.is_open()

func is_debug_panel_input_enabled() -> bool:
	return _debug_clock_panel.is_input_enabled() and _music_debug_panel.is_input_enabled()


func set_combat_active(active: bool) -> void:
	_music.set_combat_active(active)
