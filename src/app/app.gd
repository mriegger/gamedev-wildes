extends Node

@export var menu_experience_scene: PackedScene
@export var world_select_scene: PackedScene
@export var loading_scene: PackedScene
@export var game_scene: PackedScene
@export var item_catalog: Resource

@onready var game_root: Node = $GameRoot
@onready var menu_root: Node = $MenuRoot
@onready var screen_root: CanvasLayer = $ScreenRoot

var _menu_experience: MenuExperience
var _screen: Node
var _game: Game
var _settings: GameSettings
var _session_starting := false

func _ready() -> void:
	_settings = GameSettings.load_from_disk()
	get_viewport().size_changed.connect(_update_3d_render_scale)
	_update_3d_render_scale()
	_create_menu_experience(MenuExperience.EntryMode.FIRST_LAUNCH)
	_notify_web_bootstrap_ready()

func _notify_web_bootstrap_ready() -> void:
	if not OS.has_feature("web"):
		return
	await RenderingServer.frame_post_draw
	var bridge := Engine.get_singleton("JavaScriptBridge")
	if bridge != null:
		bridge.eval("window.wildesBootstrapReady?.()", true)

func _update_3d_render_scale() -> void:
	_settings.apply_display(get_viewport())

func _create_menu_experience(entry_mode: MenuExperience.EntryMode) -> void:
	assert(_menu_experience == null)
	_menu_experience = menu_experience_scene.instantiate() as MenuExperience
	_menu_experience.setup(_settings, entry_mode)
	_menu_experience.play_requested.connect(_show_world_select)
	_menu_experience.settings_changed.connect(_on_menu_settings_changed)
	menu_root.add_child(_menu_experience)

func _show_world_select() -> void:
	if _session_starting or _screen != null:
		return
	if _menu_experience == null:
		_create_menu_experience(MenuExperience.EntryMode.RECOVERY)
	_menu_experience.set_primary_menu_visible(false)
	var world_select := world_select_scene.instantiate() as SaveSlotScreen
	world_select.setup(item_catalog)
	world_select.back_requested.connect(_return_to_menu)
	world_select.session_requested.connect(_start_session)
	_replace_screen(world_select)

func _return_to_menu() -> void:
	if _session_starting:
		return
	_clear_screen()
	if _menu_experience == null:
		_create_menu_experience(MenuExperience.EntryMode.RECOVERY)
	else:
		_menu_experience.set_primary_menu_visible(true)

func _start_session(slot_id: int, save_data: Dictionary) -> void:
	if _session_starting:
		return
	_session_starting = true
	if _menu_experience != null:
		await _menu_experience.fade_out_for_session()
	_clear_screen()
	_destroy_menu_experience()
	var loading := loading_scene.instantiate() as LoadingScreen
	loading.setup(slot_id, save_data)
	_replace_screen(loading)

	_game = game_scene.instantiate() as Game
	_game.configure_session(slot_id, save_data, _settings)
	_game.loading_progress.connect(loading.update_progress)
	_game.session_ready.connect(_on_session_ready)
	_game.session_start_failed.connect(_on_session_start_failed)
	_game.main_menu_requested.connect(_on_game_main_menu_requested)
	_game.visible = false
	game_root.add_child(_game)

func _on_session_ready() -> void:
	_game.visible = true
	var loading := _screen as LoadingScreen
	if loading != null:
		await loading.fade_into_game()
		if _screen == loading:
			_clear_screen()
	_game.activate_session()
	_session_starting = false

func _on_session_start_failed(message: String) -> void:
	if _game and is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_clear_screen()
	_session_starting = false
	_create_menu_experience(MenuExperience.EntryMode.RECOVERY)
	_show_world_select()
	(_screen as SaveSlotScreen).show_load_error(message)

func _on_game_main_menu_requested() -> void:
	if _game and is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_session_starting = false
	_create_menu_experience(MenuExperience.EntryMode.GAMEPLAY_RETURN)

func _on_menu_settings_changed(updated_settings: GameSettings) -> void:
	_settings = updated_settings
	_update_3d_render_scale()
	if _settings.persist_changes:
		_settings.save_to_disk()

func _destroy_menu_experience() -> void:
	if _menu_experience == null or not is_instance_valid(_menu_experience):
		_menu_experience = null
		return
	_menu_experience.shutdown()
	menu_root.remove_child(_menu_experience)
	_menu_experience.free()
	_menu_experience = null

func _replace_screen(next_screen: Node) -> void:
	_clear_screen()
	_screen = next_screen
	screen_root.add_child(_screen)

func _clear_screen() -> void:
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
