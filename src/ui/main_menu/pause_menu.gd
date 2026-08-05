extends Control
class_name PauseMenu

signal resume_requested
signal main_menu_requested

@onready var resume_button: WildesButton = $CenterContainer/Panel/VBox/ResumeButton
@onready var main_menu_button: WildesButton = $CenterContainer/Panel/VBox/MainMenuButton

func _ready():
	_ensure_blur_material()
	resume_button.button_text = "RESUME"
	resume_button.pressed.connect(_on_resume_pressed)
	resume_button.call_deferred("focus_button")
	main_menu_button.button_text = "MAIN MENU"
	main_menu_button.pressed.connect(_on_main_menu_pressed)

func _ensure_blur_material():
	var panel = $CenterContainer/Panel as Panel
	var bg_dim = $BackgroundDim as ColorRect
	bg_dim.material = null
	bg_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_dim.color = Color(0, 0, 0, 0.18)
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

func _on_main_menu_pressed():
	main_menu_requested.emit()
