extends Control
class_name PauseMenu

## PauseMenu - pauses whole game state (get_tree().paused) with frosted glass blur
## Primitive: no images, very dim low opacity border, Roboto Slab

signal resume_requested
signal main_menu_requested

@onready var resume_button: WildesButton = $CenterContainer/Panel/VBox/ResumeButton
@onready var main_menu_button: WildesButton = $CenterContainer/Panel/VBox/MainMenuButton
@onready var title_label: Label = $CenterContainer/Panel/VBox/TitleLabel

func _ready():
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_ensure_blur_material()
	if resume_button:
		resume_button.button_text = "RESUME"
		resume_button.text = "RESUME"
		if not resume_button.pressed.is_connected(_on_resume_pressed):
			resume_button.pressed.connect(_on_resume_pressed)
		resume_button.call_deferred("focus_button")
	if main_menu_button:
		main_menu_button.button_text = "MAIN MENU"
		main_menu_button.text = "MAIN MENU"
		if not main_menu_button.pressed.is_connected(_on_main_menu_pressed):
			main_menu_button.pressed.connect(_on_main_menu_pressed)

	print("[PauseMenu] Ready - game paused, frosted blur - using official godot-demo-projects blur")

func _ensure_blur_material():
	# Use user's exact shader — blur ONLY inside Panel rect (420x300), not fullscreen
	# shader from prompt: uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap; blur_lod; mix(bg, src.rgb, src.a)
	var panel = get_node_or_null("CenterContainer/Panel") as Panel
	var bg_dim = get_node_or_null("BackgroundDim") as ColorRect
	if bg_dim:
		# Ensure fullscreen BackgroundDim has NO blur material — blur only on UI element
		if bg_dim.material != null:
			bg_dim.material = null
		bg_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_dim.color = Color(0, 0, 0, 0.18)

	if panel == null:
		return
	if panel.material == null:
		if ResourceLoader.exists("res://shaders/frosted_panel_material.tres"):
			panel.material = load("res://shaders/frosted_panel_material.tres").duplicate() as ShaderMaterial
	if panel.material is ShaderMaterial:
		var mat = panel.material as ShaderMaterial
		# User wants increased blur — use max visible 4.5 (demo limit 5.0)
		# Select World has blur because its StyleBox has alpha 0.24 (76% blur)
		# Paused should match with 4.5 lod and low alpha for strong blur
		mat.set_shader_parameter("blur_lod", 4.5)
	
	var sb: StyleBoxFlat
	if not panel.has_theme_stylebox_override("panel"):
		sb = StyleBoxFlat.new()
		panel.add_theme_stylebox_override("panel", sb)
	else:
		sb = panel.get_theme_stylebox("panel") as StyleBoxFlat
	if sb:
		sb.bg_color = Color(0.14, 0.16, 0.18, 0.32) # alpha 0.32 = 68% blur + 32% tint — strong blur like Select World
		sb.border_color = Color(1, 1, 1, 0.20)
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		sb.corner_radius_bottom_left = 18
		sb.corner_radius_bottom_right = 18

func _unhandled_input(event):
	# Allow ESC to resume when paused (this Control is WHEN_PAUSED, so it receives input while tree paused)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			print("[PauseMenu] ESC -> resume")
			_on_resume_pressed()
	if event.is_action_pressed("ui_cancel"):
		_on_resume_pressed()

func _on_resume_pressed():
	print("[PauseMenu] Resume requested")
	resume_requested.emit()
	# If no external handler, resume ourselves
	if resume_requested.get_connections().size() <= 1:
		_resume_game()

func _on_main_menu_pressed():
	print("[PauseMenu] Main Menu requested")
	main_menu_requested.emit()
	if main_menu_requested.get_connections().size() <= 1:
		_go_to_main_menu()

func _resume_game():
	get_tree().paused = false
	queue_free()

func _go_to_main_menu():
	get_tree().paused = false
	# The Game will handle saving, but we do fallback
	var parent = get_parent()
	if parent and parent is Game:
		if parent.has_method("_save_and_return_to_menu"):
			parent._save_and_return_to_menu()
			return

	# Fallback direct load main menu
	var main_menu_scene = load("res://ui/main_menu/main_menu.tscn") as PackedScene
	if main_menu_scene:
		var menu = main_menu_scene.instantiate()
		var root = get_tree().root
		root.add_child(menu)
		get_tree().current_scene = menu
	# Free game
	if parent:
		parent.queue_free()
	else:
		queue_free()
