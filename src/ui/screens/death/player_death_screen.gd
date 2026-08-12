extends CanvasLayer
class_name PlayerDeathScreen

signal respawn_requested
signal main_menu_requested

@onready var panel: Panel = $ModalRoot/CenterContainer/Panel as Panel
@onready var title_label: Label = $ModalRoot/CenterContainer/Panel/VBox/TitleLabel as Label
@onready var respawn_button: WildesButton = $ModalRoot/CenterContainer/Panel/VBox/RespawnButton as WildesButton
@onready var main_menu_button: WildesButton = $ModalRoot/CenterContainer/Panel/VBox/MainMenuButton as WildesButton

func _ready():
	WildesStyle.apply_frosted_panel(panel, WildesStyle.make_modal(), 4.5, false)
	respawn_button.pressed.connect(_on_respawn_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	respawn_button.call_deferred("focus_button")

func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()

func _on_respawn_pressed():
	respawn_requested.emit()

func _on_main_menu_pressed():
	main_menu_requested.emit()
