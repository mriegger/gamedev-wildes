extends Control
class_name PauseMenu

signal resume_requested
signal main_menu_requested

@onready var resume_button: WildesButton = $CenterContainer/Panel/VBox/ResumeButton
@onready var main_menu_button: WildesButton = $CenterContainer/Panel/VBox/MainMenuButton

func _ready():
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_ensure_blur_material()
	if resume_button:
		resume_button.button_text = "RESUME"
		if not resume_button.pressed.is_connected(_on_resume_pressed):
			resume_button.pressed.connect(_on_resume_pressed)
		resume_button.call_deferred("focus_button")
	if main_menu_button:
		main_menu_button.button_text = "MAIN MENU"
		if not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
			main_menu_button.pressed.connect(_on_main_menu_pressed)

func _ensure_blur_material():
	var panel = get_node_or_null("CenterContainer/Panel") as Panel
	var bg_dim = get_node_or_null("BackgroundDim") as ColorRect
	if bg_dim:
		if bg_dim.material != null:
			bg_dim.material = null
		bg_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_dim.color = Color(0, 0, 0, 0.18)

	if panel == null:
		return
	# Always construct fresh via factory - never read back theme stylebox and mutate shared state
	var sb = WildesStyle.make_modal()
	WildesStyle.apply_frosted_panel(panel, sb, 4.5, false)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_on_resume_pressed()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		_on_resume_pressed()
		get_viewport().set_input_as_handled()
		return

func _on_resume_pressed():
	resume_requested.emit()
	if resume_requested.get_connections().is_empty():
		_resume_game()

func _on_main_menu_pressed():
	main_menu_requested.emit()
	if main_menu_requested.get_connections().is_empty():
		_go_to_main_menu()

func _resume_game():
	get_tree().paused = false
	queue_free()

func _go_to_main_menu():
	get_tree().paused = false
	var parent = get_parent()
	if parent and parent is Game:
		if parent.has_method("_save_and_return_to_menu"):
			parent._save_and_return_to_menu()
			return

	var main_menu_scene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
	if main_menu_scene:
		var menu = main_menu_scene.instantiate()
		var root = get_tree().root
		root.add_child(menu)
		get_tree().current_scene = menu
	if parent:
		parent.queue_free()
	else:
		queue_free()
