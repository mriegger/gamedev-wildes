extends Node3D
class_name MenuExperience

signal play_requested
signal settings_changed(settings: GameSettings)

enum EntryMode {
	FIRST_LAUNCH,
	RECOVERY,
	GAMEPLAY_RETURN,
}

const SESSION_FADE_SECONDS := 0.8
const LOADING_BAR_FADE_SECONDS := 0.25
const RETURN_LOADING_BAR_FADE_SECONDS := 0.1
const QUICK_REVEAL_SECONDS := 0.25
const MUSIC_SILENCE_DB := -80.0

@export var profile: MenuCinematicProfile
@export var block_catalog: BlockCatalog
@export var foliage_catalog: FoliageCatalog
@export var entity_catalog: EntityCatalog

@onready var world: WorldController = $World
@onready var game_environment: GameEnvironment = $Environment
@onready var population: MenuCinematicPopulation = $Population
@onready var streaming_focus: Node3D = $StreamingFocus
@onready var camera_rig: Node3D = $CameraRig
@onready var camera_pitch: Node3D = $CameraRig/Pitch
@onready var camera: Camera3D = $CameraRig/Pitch/Camera3D
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var world_cover: ColorRect = $WorldCoverLayer/WorldCover
@onready var main_menu: MainMenu = $Interface/MainMenu
@onready var settings_layer: Control = $Interface/SettingsLayer
@onready var settings_panel: Panel = $Interface/SettingsLayer/Center/Panel
@onready var settings_screen: SettingsScreen = $Interface/SettingsLayer/Center/Panel/SettingsScreen
@onready var full_fade: ColorRect = $Interface/FullFade

var _settings: GameSettings
var _entry_mode: EntryMode = EntryMode.FIRST_LAUNCH
var _configured := false
var _world_ready := false
var _population_ready := false
var _input_enabled := false
var _intro_running := false
var _skip_requested := false
var _shot_index := 0
var _shot_elapsed := 0.0
var _shot_transitioning := false
var _primary_menu_visible := true
var _session_transitioning := false
var _shutting_down := false
var _camera_height := 0.0

func setup(settings: GameSettings, entry_mode: EntryMode) -> void:
	assert(not _configured and settings != null)
	_settings = settings
	_entry_mode = entry_mode
	_configured = true

func _ready() -> void:
	assert(_configured)
	assert(profile != null and profile.validate(entity_catalog))
	assert(block_catalog != null and block_catalog.validate())
	assert(foliage_catalog != null and foliage_catalog.validate(block_catalog))
	set_process(false)
	set_process_unhandled_input(true)
	main_menu.play_requested.connect(_on_play_requested)
	main_menu.settings_requested.connect(_show_settings)
	settings_screen.settings_changed.connect(_on_settings_changed)
	settings_screen.back_requested.connect(_hide_settings)
	settings_screen.setup(_settings)
	WildesStyle.apply_frosted_panel(settings_panel, WildesStyle.make_modal(), 4.5, false)
	settings_layer.visible = false
	var returning_from_gameplay := _entry_mode == EntryMode.GAMEPLAY_RETURN
	world_cover.modulate.a = 0.0 if returning_from_gameplay else 1.0
	full_fade.modulate.a = 1.0 if returning_from_gameplay else 0.0
	full_fade.mouse_filter = Control.MOUSE_FILTER_STOP if returning_from_gameplay else Control.MOUSE_FILTER_IGNORE
	main_menu.set_logo_alpha(0.0 if _entry_mode == EntryMode.FIRST_LAUNCH else 1.0)
	main_menu.set_loading_bar_centered_overlay(returning_from_gameplay)
	main_menu.set_loading_progress(0.0)
	main_menu.set_loading_description("Preparing cinematic world")
	main_menu.set_loading_bar_alpha(1.0 if returning_from_gameplay else 0.0)
	main_menu.set_controls_alpha(0.0 if _entry_mode == EntryMode.FIRST_LAUNCH else 1.0)
	main_menu.set_interaction_enabled(false)
	_apply_music_volume()
	if _entry_mode != EntryMode.GAMEPLAY_RETURN:
		_start_music_after_boot()
	_initialize_world()
	if _entry_mode == EntryMode.FIRST_LAUNCH:
		_run_launch_intro()
	else:
		_run_quick_reveal()

func _initialize_world() -> void:
	var first_shot := profile.shots[0]
	game_environment.setup(first_shot.time_of_day, _settings.get_shadow_distance(), profile.world_seed)
	game_environment.apply_settings(_settings)
	world.block_catalog = block_catalog
	world.foliage_catalog = foliage_catalog
	world.configure_settings(_settings)
	world.generation_progress.connect(_on_menu_generation_progress)
	world.configure_start_state(WorldState.new(
		profile.world_seed,
		{},
		{},
		{},
		{},
		Vector3(0.5, 0.0, 0.5),
	))
	await world.initialize_world_async()
	if _shutting_down:
		return
	game_environment.sky_color_changed.connect(world.update_water_tint)
	world.set_streaming_focus(streaming_focus)
	_population_ready = population.setup(entity_catalog, world.voxel_model, profile, world.play_water_ripple)
	if not _population_ready:
		push_error("[MenuExperience] Cinematic population could not be placed")
	_apply_shot(0)
	main_menu.set_loading_progress(1.0)
	main_menu.set_loading_description("Menu ready")
	_world_ready = true

func _run_launch_intro() -> void:
	_intro_running = true
	await _wait_seconds(profile.logo_delay_seconds)
	if _shutting_down:
		return
	await _fade_logo(1.0, profile.logo_fade_seconds)
	while not _world_ready and not _shutting_down:
		await get_tree().process_frame
	if _shutting_down:
		return
	await _fade_loading_bar(0.0, 0.1 if _skip_requested else LOADING_BAR_FADE_SECONDS)
	if _shutting_down:
		return
	_start_cinematic()
	var reveal_duration := 0.2 if _skip_requested else profile.world_fade_seconds
	await _fade_control(world_cover, 0.0, reveal_duration, not _skip_requested)
	var controls_duration := 0.2 if _skip_requested else profile.controls_fade_seconds
	await _fade_menu_controls(1.0, controls_duration, not _skip_requested)
	_finish_intro()

func _run_quick_reveal() -> void:
	_intro_running = true
	while not _world_ready and not _shutting_down:
		await get_tree().process_frame
	if _shutting_down:
		return
	_start_cinematic()
	if _entry_mode == EntryMode.GAMEPLAY_RETURN:
		await _fade_loading_bar(0.0, RETURN_LOADING_BAR_FADE_SECONDS)
		if _shutting_down:
			return
	var reveal_cover: ColorRect = full_fade if _entry_mode == EntryMode.GAMEPLAY_RETURN else world_cover
	await _fade_control(reveal_cover, 0.0, QUICK_REVEAL_SECONDS, false)
	reveal_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_finish_intro()

func _start_cinematic() -> void:
	_shot_elapsed = 0.0
	if _population_ready:
		population.start_simulation()
	set_process(true)

func _finish_intro() -> void:
	_intro_running = false
	main_menu.visible = _primary_menu_visible
	_input_enabled = _primary_menu_visible
	main_menu.set_interaction_enabled(_input_enabled)
	if _input_enabled:
		main_menu.focus_play()

func _process(delta: float) -> void:
	if not _world_ready:
		return
	_shot_elapsed += delta
	_update_camera_position()
	if _session_transitioning or _shot_transitioning:
		return
	var shot := profile.shots[_shot_index]
	if _shot_elapsed >= shot.duration_seconds:
		_shot_transitioning = true
		_transition_to_next_shot()

func _update_camera_position() -> void:
	var shot := profile.shots[_shot_index]
	var progress := maxf(_shot_elapsed / shot.duration_seconds, 0.0)
	var drift_position := Vector2(shot.anchor) + shot.drift * progress
	var focus_position := Vector3(drift_position.x + 0.5, _camera_height, drift_position.y + 0.5)
	camera_rig.global_position = focus_position
	streaming_focus.global_position = focus_position

func _transition_to_next_shot() -> void:
	var half_fade := profile.crossfade_seconds * 0.5
	if not await _fade_control(world_cover, 1.0, half_fade, false, true):
		_shot_transitioning = false
		return
	_apply_shot((_shot_index + 1) % profile.shots.size())
	if not await _fade_control(world_cover, 0.0, half_fade, false, true):
		_shot_transitioning = false
		return
	_shot_transitioning = false

func _apply_shot(index: int) -> void:
	_shot_index = index
	_shot_elapsed = 0.0
	var shot := profile.shots[index]
	var surface_top := world.voxel_model.get_terrain_surface_top(shot.anchor.x, shot.anchor.y)
	_camera_height = surface_top if surface_top != VoxelSpace.NO_SURFACE_Y else float(world.config.water_level + 5)
	camera_rig.rotation_degrees.y = shot.yaw_degrees
	camera_pitch.rotation_degrees.x = shot.pitch_degrees
	camera.size = shot.orthographic_size
	_update_camera_position()
	game_environment.set_time_of_day(shot.time_of_day)

func _unhandled_input(event: InputEvent) -> void:
	if settings_layer.visible and event.is_action_pressed("ui_cancel"):
		_hide_settings()
		get_viewport().set_input_as_handled()
		return
	if not _intro_running or main_menu.logo.modulate.a <= 0.0:
		return
	var pressed: bool = false
	if event is InputEventKey:
		pressed = event.pressed and not event.echo
	elif event is InputEventMouseButton:
		pressed = event.pressed
	elif event is InputEventJoypadButton:
		pressed = event.pressed
	if pressed:
		_skip_requested = true
		get_viewport().set_input_as_handled()

func _show_settings() -> void:
	if not _input_enabled or _session_transitioning:
		return
	main_menu.set_interaction_enabled(false)
	settings_layer.visible = true
	settings_screen.focus_first_control()

func _hide_settings() -> void:
	if not settings_layer.visible:
		return
	settings_layer.visible = false
	main_menu.set_interaction_enabled(true)
	main_menu.focus_settings()

func _on_settings_changed(updated_settings: GameSettings) -> void:
	_settings = updated_settings
	_apply_music_volume()
	game_environment.apply_settings(_settings)
	if _world_ready:
		world.apply_settings(_settings)
	settings_changed.emit(_settings)

func _on_menu_generation_progress(stage: String, percent: float, details: String) -> void:
	main_menu.set_loading_progress(clampf(percent, 0.0, 1.0) * 0.9)
	var description := stage.capitalize()
	if not details.is_empty():
		description += ": %s" % details
	main_menu.set_loading_description(description)

func _on_play_requested() -> void:
	if not _input_enabled or _session_transitioning:
		return
	play_requested.emit()

func set_primary_menu_visible(should_be_visible: bool) -> void:
	_primary_menu_visible = should_be_visible
	main_menu.visible = should_be_visible
	_input_enabled = (
		should_be_visible
		and not _intro_running
		and _world_ready
		and not _session_transitioning
	)
	main_menu.set_interaction_enabled(_input_enabled)
	if _input_enabled:
		main_menu.focus_play()

func fade_out_for_session() -> void:
	if _session_transitioning:
		return
	_session_transitioning = true
	if _shot_transitioning:
		world_cover.modulate.a = 0.0
	_input_enabled = false
	main_menu.set_interaction_enabled(false)
	full_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var start_db := music_player.volume_db
	var elapsed := 0.0
	while elapsed < SESSION_FADE_SECONDS and not _shutting_down:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		var progress := clampf(elapsed / SESSION_FADE_SECONDS, 0.0, 1.0)
		full_fade.modulate.a = progress
		music_player.volume_db = lerpf(start_db, MUSIC_SILENCE_DB, progress)
	if _shutting_down:
		return
	full_fade.modulate.a = 1.0
	music_player.stop()
	set_process(false)

func shutdown() -> void:
	if _shutting_down:
		return
	_shutting_down = true
	set_process(false)
	set_process_unhandled_input(false)
	music_player.stop()
	music_player.stream = null
	if _population_ready:
		population.shutdown()
	if world.chunk_manager != null:
		world.shutdown()
	_world_ready = false
	_population_ready = false

func is_ready_for_input() -> bool:
	return _input_enabled

func is_session_transitioning() -> bool:
	return _session_transitioning

func is_music_playing() -> bool:
	return music_player.playing

func get_current_shot_id() -> StringName:
	return profile.shots[_shot_index].id

func _apply_music_volume() -> void:
	music_player.volume_db = linear_to_db(_settings.music_volume) if _settings.music_volume > 0.0 else MUSIC_SILENCE_DB

func _start_music_after_boot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not _shutting_down:
		music_player.play()

func _wait_seconds(duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration and not _shutting_down:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

func _fade_control(
	control: CanvasItem,
	target_alpha: float,
	duration: float,
	allow_skip: bool,
	cancel_for_session: bool = false,
) -> bool:
	var start_alpha := control.modulate.a
	var elapsed := 0.0
	while elapsed < duration and not _shutting_down:
		await get_tree().process_frame
		if cancel_for_session and _session_transitioning:
			return false
		if allow_skip and _skip_requested:
			break
		elapsed += get_process_delta_time()
		control.modulate.a = lerpf(start_alpha, target_alpha, clampf(elapsed / duration, 0.0, 1.0))
	control.modulate.a = target_alpha
	return not _shutting_down

func _fade_menu_controls(target_alpha: float, duration: float, allow_skip: bool) -> void:
	var start_alpha := main_menu.controls.modulate.a
	var elapsed := 0.0
	while elapsed < duration and not _shutting_down:
		await get_tree().process_frame
		if allow_skip and _skip_requested:
			break
		elapsed += get_process_delta_time()
		main_menu.set_controls_alpha(lerpf(start_alpha, target_alpha, clampf(elapsed / duration, 0.0, 1.0)))
	main_menu.set_controls_alpha(target_alpha)

func _fade_logo(target_alpha: float, duration: float) -> void:
	var start_alpha := main_menu.logo.modulate.a
	var elapsed := 0.0
	while elapsed < duration and not _shutting_down:
		await get_tree().process_frame
		if _skip_requested:
			break
		elapsed += get_process_delta_time()
		var alpha := lerpf(start_alpha, target_alpha, clampf(elapsed / duration, 0.0, 1.0))
		main_menu.set_logo_alpha(alpha)
		main_menu.set_loading_bar_alpha(alpha)
	main_menu.set_logo_alpha(target_alpha)
	main_menu.set_loading_bar_alpha(target_alpha)

func _fade_loading_bar(target_alpha: float, duration: float) -> void:
	var start_alpha := main_menu.loading_bar.modulate.a
	var elapsed := 0.0
	while elapsed < duration and not _shutting_down:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
		main_menu.set_loading_bar_alpha(lerpf(start_alpha, target_alpha, clampf(elapsed / duration, 0.0, 1.0)))
	main_menu.set_loading_bar_alpha(target_alpha)

func _exit_tree() -> void:
	shutdown()
