extends Node3D
class_name Game

@onready var world_env_node: WorldEnvironment = $WorldEnvironment
@onready var world: WorldController = $World as WorldController
@onready var player: PlayerMotor = $Player as PlayerMotor
@onready var interactor: PlayerInteractor = $Player/Interactor as PlayerInteractor
@onready var targeting_view: TargetingView = $Player/TargetingView as TargetingView
@onready var camera_rig: CameraRig = $CameraRig as CameraRig
@onready var camera_3d: Camera3D = $CameraRig/Pitch/Camera3D as Camera3D
@onready var sun: DirectionalLight3D = $Sun as DirectionalLight3D
@onready var sun_fill: DirectionalLight3D = $SunFill as DirectionalLight3D
@onready var game_clock: GameClock = $GameClock as GameClock
@onready var day_night_values: DayNightValues = $DayNightValues as DayNightValues
@onready var debug_clock_panel: DebugClockPanel = $DebugClockPanel as DebugClockPanel
@onready var hud: HUD = $HUD as HUD

var inventory_model: InventoryModel = null
var input_buffer: InputBuffer = InputBuffer.new()

var current_slot_id: int = -1
var current_save_data: Dictionary = {}

var _save_timer: float = 0.0
var _playtime_accum: float = 0.0
var _pending_edit_save: bool = false
const AUTO_SAVE_INTERVAL: float = 30.0
const EDIT_SAVE_DEBOUNCE: float = 2.0

var _save_status_timer: float = 0.0
var _save_label: Label = null

func _enter_tree():
	if current_save_data.is_empty():
		current_save_data = _load_current_session_file()
		if not current_save_data.is_empty():
			current_slot_id = int(current_save_data.get("slot_id", -1))

	if not current_save_data.is_empty():
		var world_node = get_node_or_null("World") as WorldController
		if world_node:
			world_node.set_pending_save_data(current_save_data)

func _load_current_session_file() -> Dictionary:
	var path = "user://current_session.json"
	if not FileAccess.file_exists(path):
		return {}
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt = f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var sid = parsed.get("slot_id", -1)
	if sid != -1 and SaveManager.slot_exists(sid):
		var full = SaveManager.load_slot(sid)
		if full.get("exists", false):
			return full
	return parsed

var _defer_setup: bool = false
var _deferred_saved_pos: Vector3 = Vector3.ZERO
var _deferred_has_saved_pos: bool = false
var _deferred_saved_time: float = 6.0
var _deferred_has_saved_time: bool = false

func _ready():
	_create_save_status_ui()
	camera_rig.setup(player, input_buffer)

	inventory_model = InventoryModel.new(InventoryModel.TOTAL_SIZE, InventoryModel.DEFAULT_MAX_STACK)

	if not current_save_data.is_empty() and current_save_data.has("inventory") and current_save_data["inventory"] != null:
		var inv_dict = current_save_data["inventory"] as Dictionary
		if not inv_dict.is_empty():
			inventory_model.from_dict(inv_dict)
		else:
			inventory_model.setup_starter()
	else:
		inventory_model.setup_starter()

	var saved_player_pos: Vector3 = Vector3.ZERO
	var has_saved_pos: bool = false
	var saved_time_of_day: float = 6.0
	var has_saved_time: bool = false
	if not current_save_data.is_empty():
		var pos_arr = current_save_data.get("player_position", null)
		if pos_arr is Array and pos_arr.size() == 3:
			var p = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
			if p != Vector3.ZERO and p.length() > 1.0:
				saved_player_pos = p
				has_saved_pos = true
		if current_save_data.has("time_of_day"):
			saved_time_of_day = float(current_save_data["time_of_day"])
			has_saved_time = true

	if world and not world.auto_generate_on_ready:
		_defer_setup = true
		_deferred_saved_pos = saved_player_pos
		_deferred_has_saved_pos = has_saved_pos
		_deferred_saved_time = saved_time_of_day
		_deferred_has_saved_time = has_saved_time
		return

	_setup_all(saved_player_pos, has_saved_pos, saved_time_of_day, has_saved_time)

func finalize_deferred_setup():
	if not _defer_setup:
		return
	_defer_setup = false
	_setup_all(_deferred_saved_pos, _deferred_has_saved_pos, _deferred_saved_time, _deferred_has_saved_time)

func _setup_all(saved_pos: Vector3, has_saved: bool, saved_time: float, has_saved_time: bool):
	player.setup(world.voxel_model, camera_rig, input_buffer)
	interactor.setup(world.voxel_model, camera_3d, player, inventory_model, input_buffer)
	targeting_view.setup(world, world.voxel_model, player, interactor)
	camera_rig.reset_side_panel_offset()

	world.set_player_ref(player)

	if has_saved_time:
		game_clock.set_time_of_day(saved_time)
	else:
		game_clock.set_time_of_day(game_clock.start_hour)

	day_night_values.setup(game_clock, sun, sun_fill, world_env_node, world.config, world)
	debug_clock_panel.inject(game_clock, day_night_values)

	hud.setup_with_camera(inventory_model, camera_rig)

	if has_saved and saved_pos != Vector3.ZERO:
		player.global_position = saved_pos + Vector3(0, 0.2, 0)
	else:
		var spawn_pos = world.voxel_model.get_spawn_position()
		player.global_position = spawn_pos + Vector3(0, 0.1, 0)

	camera_rig.target_position = player.global_position
	camera_rig.global_position = player.global_position
	camera_rig.current_yaw_deg = camera_rig.target_yaw_deg
	camera_3d.current = true

	if not world.voxel_model.block_edit_committed.is_connected(_on_world_edit):
		world.voxel_model.block_edit_committed.connect(_on_world_edit)

var _save_canvas: CanvasLayer = null

func _create_save_status_ui():
	var canvas = CanvasLayer.new()
	canvas.name = "SaveStatusLayer"
	canvas.layer = 100
	canvas.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	canvas.visible = false
	add_child(canvas)
	_save_canvas = canvas
	var lbl = Label.new()
	lbl.name = "SaveStatusLabel"
	var time_str = game_clock.get_formatted() if game_clock else "06:00"
	lbl.text = "Slot %d | Seed %d | %s | %s" % [current_slot_id, world.seed_value if world else 0, current_save_data.get("world_name", "World") if current_save_data else "World", time_str]
	if current_slot_id == -1:
		lbl.text = "No save slot (Play via Main Menu to save) | Seed %d | %s" % [world.seed_value if world else 0, time_str]
	lbl.position = Vector2(10, 10)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(1,1,1,0.85))
	lbl.material = null
	canvas.add_child(lbl)
	_save_label = lbl

func _update_save_label(text: String = ""):
	if _save_label == null:
		return
	if text != "":
		_save_label.text = text
		_save_status_timer = 2.5
	else:
		var time_str = game_clock.get_formatted() if game_clock else "06:00"
		var world_name = current_save_data.get("world_name", "") if current_save_data else ""
		var placed = world.voxel_model.placed_blocks.size() if world and world.voxel_model else 0
		var removed = world.voxel_model.removed_blocks.size() if world and world.voxel_model else 0
		var base = "Slot %d | Seed %d | %s | %s | %d edits" % [current_slot_id, world.seed_value if world else 0, world_name, time_str, placed + removed]
		_save_label.text = base

func _on_world_edit(_edit: BlockEdit):
	_pending_edit_save = true
	_save_timer = 0.0
	if _save_label:
		var time_str = game_clock.get_formatted() if game_clock else "06:00"
		_save_label.text = "Slot %d | Seed %d | %s | Pending save..." % [current_slot_id, world.seed_value if world else 0, time_str]

func _process(delta):
	if _save_status_timer > 0:
		_save_status_timer -= delta
		if _save_status_timer <= 0:
			_update_save_label()

	if current_slot_id == -1:
		return

	_save_timer += delta
	_playtime_accum += delta

	if _pending_edit_save and _save_timer >= EDIT_SAVE_DEBOUNCE:
		_save_timer = 0.0
		_pending_edit_save = false
		_perform_save("edit")

	elif _save_timer >= AUTO_SAVE_INTERVAL:
		_save_timer = 0.0
		_perform_save("auto")

func _physics_process(_delta):
	input_buffer.poll()

var _pause_menu: PauseMenu = null
var pause_menu_scene: PackedScene = preload("res://ui/main_menu/pause_menu.tscn")

func _is_side_panel_open() -> bool:
	if hud and is_instance_valid(hud):
		return hud.is_side_panel_open()
	return false

func _unhandled_input(event):
	if event.is_action_pressed("toggle_backpack"):
		if hud and is_instance_valid(hud):
			hud.toggle_side_panel()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if _is_side_panel_open():
				if hud:
					hud.close_side_panel()
				get_viewport().set_input_as_handled()
				return
			if get_tree().paused and _pause_menu:
				_resume_from_pause()
			else:
				_show_pause_menu()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if _is_side_panel_open():
			if hud:
				hud.close_side_panel()
			get_viewport().set_input_as_handled()
			return
		if get_tree().paused and _pause_menu:
			_resume_from_pause()
		else:
			_show_pause_menu()
		get_viewport().set_input_as_handled()
		return

func _show_pause_menu():
	if _pause_menu and is_instance_valid(_pause_menu):
		return
	if _is_side_panel_open():
		if hud:
			hud.close_side_panel_immediate()
		if camera_rig:
			camera_rig.reset_side_panel_offset()
	_pause_menu = pause_menu_scene.instantiate() as PauseMenu
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.main_menu_requested.connect(_on_pause_main_menu)
	add_child(_pause_menu)
	if _save_canvas:
		_save_canvas.visible = true
		_update_save_label()
	get_tree().paused = true

func _resume_from_pause():
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
		_pause_menu = null
	if _save_canvas:
		_save_canvas.visible = false
	get_tree().paused = false

func _on_pause_main_menu():
	get_tree().paused = false
	if _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null
	_save_and_return_to_menu()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if current_slot_id != -1:
			_perform_save("close")
		if world:
			world.shutdown()

func _perform_save(reason: String) -> bool:
	if current_slot_id == -1:
		push_warning("[Game] Cannot save - no slot selected (launch via Main Menu -> PLAY -> Select Slot)")
		return false
	if world == null or world.voxel_model == null:
		push_warning("[Game] Cannot save - world not ready")
		return false

	var time_to_save = game_clock.get_time_of_day() if game_clock else 6.0
	var success = SaveManager.save_world_state(current_slot_id, current_save_data, world.voxel_model, player, inventory_model, _playtime_accum, time_to_save)
	if success:
		_playtime_accum = 0.0
		_update_save_label("Saved slot %d! (%s) %s Seed %d | %d edits" % [
			current_slot_id, reason, game_clock.get_formatted() if game_clock else "",
			world.seed_value,
			world.voxel_model.placed_blocks.size() + world.voxel_model.removed_blocks.size()
		])
		_save_status_timer = 2.5
	else:
		push_warning("[Game] Save failed slot %d" % current_slot_id)
		_update_save_label("Save FAILED slot %d" % current_slot_id)
	return success

func _save_and_return_to_menu():
	get_tree().paused = false
	if hud.is_side_panel_open():
		hud.close_side_panel_immediate()
	camera_rig.reset_side_panel_offset()
	_perform_save("quit_to_menu")
	world.shutdown()

	var root = get_tree().root
	UiCleanup.free_stray_canvas_layers(root, self)
	var main_menu_scene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
	var menu = main_menu_scene.instantiate()
	root.add_child(menu)
	get_tree().current_scene = menu
	queue_free()
