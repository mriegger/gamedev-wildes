extends Control
class_name PauseMenu

signal resume_requested
signal main_menu_requested

@onready var resume_button: WildesButton = $CenterContainer/Panel/VBox/ResumeButton
@onready var settings_button: WildesButton = $CenterContainer/Panel/VBox/SettingsButton
@onready var main_menu_button: WildesButton = $CenterContainer/Panel/VBox/MainMenuButton
@onready var settings_screen: SettingsScreen = $CenterContainer/Panel/SettingsScreen
@onready var _panel: Panel = $CenterContainer/Panel
@onready var _main_view: VBoxContainer = $CenterContainer/Panel/VBox

func _ready():
	_apply_panel_style()
	resume_button.pressed.connect(_on_resume_pressed)
	resume_button.call_deferred("focus_button")
	settings_button.pressed.connect(_show_settings)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	settings_screen.back_requested.connect(_show_pause_menu)

func setup(settings: GameSettings):
	settings_screen.setup(settings)

func _apply_panel_style():
	var panel = $CenterContainer/Panel as Panel
	var sb = WildesStyle.make_modal()
	WildesStyle.apply_frosted_panel(panel, sb, 4.5, false)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if settings_screen.visible:
				_show_pause_menu()
			else:
				_on_resume_pressed()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if settings_screen.visible:
			_show_pause_menu()
		else:
			_on_resume_pressed()
		get_viewport().set_input_as_handled()
		return

func _on_resume_pressed():
	resume_requested.emit()

func _on_main_menu_pressed():
	main_menu_requested.emit()

func _show_settings():
	_main_view.visible = false
	settings_screen.visible = true
	_panel.custom_minimum_size = Vector2(640, 680)
	settings_screen.focus_first_control()

func _show_pause_menu():
	settings_screen.visible = false
	_main_view.visible = true
	_panel.custom_minimum_size = Vector2(420, 390)
	resume_button.focus_button()
