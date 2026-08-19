extends Node

@export var main_menu_scene: PackedScene
@export var world_select_scene: PackedScene
@export var loading_scene: PackedScene
@export var game_scene: PackedScene
@export var item_catalog: Resource

@onready var game_root: Node = $GameRoot
@onready var screen_root: Node = $ScreenRoot

var _screen: Node
var _game: Game
var _settings: GameSettings

func _ready():
	_settings = GameSettings.load_from_disk()
	get_viewport().size_changed.connect(_update_3d_render_scale)
	_update_3d_render_scale()
	_show_main_menu()

func _update_3d_render_scale():
	_settings.apply_display(get_viewport())

func _show_main_menu():
	var menu = main_menu_scene.instantiate() as MainMenu
	menu.play_requested.connect(_show_world_select)
	_replace_screen(menu)

func _show_world_select():
	var world_select = world_select_scene.instantiate() as SaveSlotScreen
	world_select.setup(item_catalog)
	world_select.back_requested.connect(_show_main_menu)
	world_select.session_requested.connect(_start_session)
	_replace_screen(world_select)

func _start_session(slot_id: int, save_data: Dictionary):
	var loading = loading_scene.instantiate() as LoadingScreen
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

func _on_session_ready():
	_game.visible = true
	_clear_screen()

func _on_session_start_failed(message: String) -> void:
	if _game and is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_show_world_select()
	(_screen as SaveSlotScreen).show_load_error(message)

func _on_game_main_menu_requested():
	if _game and is_instance_valid(_game):
		_game.queue_free()
	_game = null
	_show_main_menu()

func _replace_screen(next_screen: Node):
	_clear_screen()
	_screen = next_screen
	screen_root.add_child(_screen)

func _clear_screen():
	if _screen and is_instance_valid(_screen):
		_screen.queue_free()
	_screen = null
