extends Control
class_name WildesButton

signal pressed
signal button_down
signal button_up

var _internal_button_text: String = "PLAY"
var _internal_button_icon: Texture2D = null
var _internal_icon_size: Vector2 = Vector2(20, 20)
var _internal_font_size: int = -1

@export var button_text: String = "PLAY":
	get:
		return _internal_button_text
	set(v):
		if _internal_button_text == v:
			return
		_internal_button_text = v
		if is_inside_tree():
			_update_text()

@export var button_icon: Texture2D = null:
	get:
		return _internal_button_icon
	set(v):
		if _internal_button_icon == v:
			return
		_internal_button_icon = v
		if is_inside_tree():
			_update_icon()

@export var button_icon_size: Vector2 = Vector2(20, 20):
	get:
		return _internal_icon_size
	set(v):
		if _internal_icon_size == v:
			return
		_internal_icon_size = v
		if is_inside_tree():
			_update_icon()

@export var button_font_size: int = -1:
	get:
		return _internal_font_size
	set(v):
		if _internal_font_size == v:
			return
		_internal_font_size = v
		if is_inside_tree():
			_update_font_size()

@onready var _frosted_rect: Panel = $FrostedGlass as Panel
@onready var _button: Button = $Button
@onready var _icon_rect: TextureRect = $Button/ContentHBox/Icon
@onready var _text_label: Label = $Button/ContentHBox/TextLabel

func _ready():
	_setup_frosted_material()
	_setup_button_styles()
	_update_text()
	_update_icon()

	_button.pressed.connect(_on_button_pressed)
	_button.button_down.connect(_on_inner_button_down)
	_button.button_up.connect(_on_inner_button_up)
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	if has_meta("_side_panel_no_focus"):
		_button.focus_mode = Control.FOCUS_NONE
	else:
		_button.focus_mode = Control.FOCUS_ALL
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE

func _setup_frosted_material():
	_frosted_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb = WildesStyle.make_button_frosted()
	WildesStyle.apply_frosted_panel(_frosted_rect, sb, 4.0, true)

func _setup_button_styles():
	var normal_box = WildesStyle.make_button_normal()
	var hover_box = WildesStyle.make_button_hover()
	var pressed_box = WildesStyle.make_button_pressed()
	var disabled_box = WildesStyle.make_button_disabled()

	_button.add_theme_stylebox_override("normal", normal_box)
	_button.add_theme_stylebox_override("hover", hover_box)
	_button.add_theme_stylebox_override("pressed", pressed_box)
	_button.add_theme_stylebox_override("focus", normal_box)
	_button.add_theme_stylebox_override("disabled", disabled_box)

	_button.add_theme_font_override("font", WildesStyle.BOLD_FONT)

func _update_text():
	_text_label.text = _internal_button_text
	_update_font_size()

func _update_font_size():
	var size = _internal_font_size
	if size < 0:
		var len = _internal_button_text.length()
		if len > 16:
			size = 15
		elif len > 12:
			size = 16
		elif len > 8:
			size = 18
		else:
			size = 20
	_text_label.add_theme_font_size_override("font_size", size)
	_text_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))

func _update_icon():
	if _internal_button_icon == null:
		_icon_rect.visible = false
		_icon_rect.texture = null
		return
	_icon_rect.visible = true
	_icon_rect.texture = _internal_button_icon
	_icon_rect.custom_minimum_size = _internal_icon_size
	_icon_rect.size = _internal_icon_size

func _on_button_pressed():
	pressed.emit()

func _on_inner_button_down():
	button_down.emit()

func _on_inner_button_up():
	button_up.emit()

func focus_button():
	_button.grab_focus()
