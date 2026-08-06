extends Node3D
class_name Game

signal loading_progress(stage: String, percent: float, details: String)
signal session_ready
signal main_menu_requested

@export var pause_menu_scene: PackedScene
@export var animation_tuning_panel_scene: PackedScene
@export var block_catalog: BlockCatalog
@export var item_catalog: ItemCatalog

@onready var world: WorldController = $World as WorldController
@onready var player: PlayerMotor = $Player as PlayerMotor
@onready var camera_rig: CameraRig = $CameraRig as CameraRig
@onready var game_environment: GameEnvironment = $Environment as GameEnvironment
@onready var hud: HUD = $HUD as HUD
@onready var game_session: GameSession = $GameSession as GameSession
@onready var _save_canvas: CanvasLayer = $SaveStatusLayer as CanvasLayer
@onready var _save_label: Label = $SaveStatusLayer/SaveStatusLabel as Label

var inventory_model: InventoryModel
var input_buffer: InputBuffer = InputBuffer.new()
var settings: GameSettings

var _slot_id: int = -1
var _save_data: Dictionary = {}
var _world_state: WorldState
var _pause_menu: PauseMenu
var animation_tuning_panel: AnimationTuningPanel = null
var _save_status_timer: float = 0.0
var _session_active: bool = false

func configure_session(slot_id: int, save_data: Dictionary, p_settings: GameSettings):
	_slot_id = slot_id
	_save_data = save_data
	settings = p_settings
	_world_state = SaveManager.decode_world_state(save_data)

func _ready():
	set_physics_process(false)
	set_process_unhandled_input(false)
	assert(block_catalog.validate())
	assert(item_catalog.validate(block_catalog))
	settings.apply_display(get_viewport())
	game_environment.setup(float(_save_data.get("time_of_day", 6.0)), settings.get_shadow_distance())
	game_environment.apply_settings(settings)
	world.block_catalog = block_catalog
	world.configure_settings(settings)
	inventory_model = InventoryModel.new(item_catalog)
	_restore_inventory()
	world.configure_start_state(_world_state)
	world.generation_progress.connect(_on_generation_progress)
	await world.initialize_world_async()
	world.generation_progress.disconnect(_on_generation_progress)
	_setup_gameplay()
	game_session.save_status_changed.connect(_show_save_status)
	game_session.setup(_slot_id, _save_data, world, player, inventory_model, game_environment)
	_session_active = true
	_refresh_save_label()
	set_physics_process(true)
	set_process_unhandled_input(true)
	session_ready.emit()

func _restore_inventory():
	var saved_inventory = _save_data.get("inventory", null)
	if saved_inventory is Dictionary and not saved_inventory.is_empty():
		assert(inventory_model.from_dict(saved_inventory))
		assert(inventory_model.ensure_item(&"copper_pickaxe"))
	else:
		inventory_model.setup_starter()

func _setup_gameplay():
	camera_rig.setup(player, input_buffer)
	player.setup(world, camera_rig, inventory_model, input_buffer)
	camera_rig.reset_right_obstruction()
	world.set_player_ref(player)

	game_environment.sky_color_changed.connect(world.update_water_tint)
	game_environment.start_clock()
	hud.setup_with_camera(inventory_model, camera_rig)

	var saved_position = _world_state.player_position
	if saved_position != Vector3.ZERO:
		player.global_position = saved_position + Vector3(0, 0.2, 0)
	else:
		player.global_position = world.voxel_model.get_spawn_position() + Vector3(0, 0.1, 0)

	camera_rig.target_position = player.global_position
	camera_rig.global_position = player.global_position
	camera_rig.current_yaw_deg = camera_rig.target_yaw_deg
	camera_rig.camera.current = true

func _on_generation_progress(stage: String, percent: float, details: String):
	loading_progress.emit(stage, percent, details)

func _show_save_status(text: String):
	_save_label.text = text
	_save_status_timer = 2.5
	_save_canvas.visible = true

func _refresh_save_label():
	_save_label.text = game_session.get_summary()

func _process(delta):
	if _save_status_timer <= 0.0:
		return
	_save_status_timer -= delta
	if _save_status_timer <= 0.0:
		_save_canvas.visible = false

func _physics_process(_delta):
	if OS.is_debug_build() and Input.is_action_just_pressed("toggle_animation_tuner"):
		_toggle_animation_tuning_panel()
	input_buffer.poll()
	if animation_tuning_panel != null and animation_tuning_panel.is_open():
		input_buffer.clear_gameplay()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event = event as InputEventKey
		if animation_tuning_panel != null and animation_tuning_panel.is_open():
			if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
				animation_tuning_panel.hide_panel()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_backpack"):
		hud.toggle_side_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_handle_cancel()
		get_viewport().set_input_as_handled()

func _toggle_animation_tuning_panel():
	if animation_tuning_panel == null:
		animation_tuning_panel = animation_tuning_panel_scene.instantiate() as AnimationTuningPanel
		add_child(animation_tuning_panel)
		animation_tuning_panel.setup(player)
	animation_tuning_panel.toggle_panel()

func _handle_cancel():
	if animation_tuning_panel != null and animation_tuning_panel.is_open():
		animation_tuning_panel.hide_panel()
		return
	if hud.is_side_panel_open():
		hud.close_side_panel()
		return
	_show_pause_menu()

func _show_pause_menu():
	_pause_menu = pause_menu_scene.instantiate() as PauseMenu
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.main_menu_requested.connect(_save_and_request_main_menu)
	add_child(_pause_menu)
	_pause_menu.setup(settings)
	_pause_menu.settings_screen.settings_changed.connect(_on_settings_changed)
	_save_canvas.visible = true
	_refresh_save_label()
	get_tree().paused = true

func _on_settings_changed(updated_settings: GameSettings):
	settings = updated_settings
	settings.apply_display(get_viewport())
	game_environment.apply_settings(settings)
	world.apply_settings(settings)
	if settings.persist_changes:
		settings.save_to_disk()

func _resume_from_pause():
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null
	_save_canvas.visible = false
	get_tree().paused = false

func _save_and_request_main_menu():
	get_tree().paused = false
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null
	hud.close_side_panel_immediate()
	camera_rig.reset_right_obstruction()
	game_session.shutdown("quit_to_menu")
	world.shutdown()
	_session_active = false
	main_menu_requested.emit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _session_active:
		_session_active = false
		game_session.shutdown("close")
		world.shutdown()
