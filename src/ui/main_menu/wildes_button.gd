extends Control
class_name WildesButton

signal pressed
signal button_down
signal button_up

var _internal_button_text: String = "PLAY"

@export var button_text: String = "PLAY":
	get:
		return _internal_button_text
	set(v):
		_internal_button_text = v
		if is_inside_tree():
			_update_text()

@onready var _frosted_rect: Panel = $FrostedGlass as Panel
@onready var _button: Button = $Button

func _ready():
	_setup_frosted_material()
	_setup_button_styles()
	_update_text()

	if _button:
		if not _button.pressed.is_connected(_on_button_pressed):
			_button.pressed.connect(_on_button_pressed)
		if not _button.button_down.is_connected(_on_inner_button_down):
			_button.button_down.connect(_on_inner_button_down)
		if not _button.button_up.is_connected(_on_inner_button_up):
			_button.button_up.connect(_on_inner_button_up)
		_button.mouse_filter = Control.MOUSE_FILTER_STOP
		_button.focus_mode = Control.FOCUS_ALL
		_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

func _setup_frosted_material():
	if _frosted_rect == null:
		return
	_frosted_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Always fresh via factory, never read back theme stylebox
	var sb = WildesStyle.make_button_frosted()
	WildesStyle.apply_frosted_panel(_frosted_rect, sb, 4.0, true)

func _setup_button_styles():
	if _button == null:
		return
	var normal_box = WildesStyle.make_button_normal()
	var hover_box = WildesStyle.make_button_hover()
	var pressed_box = WildesStyle.make_button_pressed()
	var disabled_box = WildesStyle.make_button_disabled()

	_button.add_theme_stylebox_override("normal", normal_box)
	_button.add_theme_stylebox_override("hover", hover_box)
	_button.add_theme_stylebox_override("pressed", pressed_box)
	_button.add_theme_stylebox_override("focus", normal_box)
	_button.add_theme_stylebox_override("disabled", disabled_box)

	# Bold satisfies Roboto Slab family; preloaded, no exists check per instance
	_button.add_theme_font_override("font", WildesStyle.BOLD_FONT)

	_update_font_size()

func _update_text():
	if _button:
		_button.text = _internal_button_text
	_update_font_size()

func _update_font_size():
	if _button == null:
		return
	var len = _internal_button_text.length()
	var size = 20
	if len > 16:
		size = 15
	elif len > 12:
		size = 16
	elif len > 8:
		size = 18
	else:
		size = 20
	_button.add_theme_font_size_override("font_size", size)
	_button.alignment = HORIZONTAL_ALIGNMENT_CENTER

func _on_button_pressed():
	pressed.emit()

func _on_inner_button_down():
	button_down.emit()

func _on_inner_button_up():
	button_up.emit()

func focus_button():
	if _button:
		_button.grab_focus()
	else:
		grab_focus()
