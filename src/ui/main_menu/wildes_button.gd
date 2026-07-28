extends Control
class_name WildesButton

## Primitive WildesButton - frosted glass blur, Roboto Slab Bold
## No image assets, fully primitive. PLAY button 25% smaller (250x70) but font 25% bigger (20px)

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

var text: String:
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
	# Exact shader from user: screen_texture + blur_lod, mixes bg with src.a
	# FrostedGlass is now Panel to have same radius as border (14)
	if ResourceLoader.exists("res://shaders/frosted_button_material.tres"):
		var mat = load("res://shaders/frosted_button_material.tres") as Material
		if mat:
			var dup = mat.duplicate() as ShaderMaterial
			dup.set_shader_parameter("blur_lod", 4.0)
			_frosted_rect.material = dup
	else:
		if ResourceLoader.exists("res://shaders/frosted_glass.gdshader"):
			var shader = load("res://shaders/frosted_glass.gdshader") as Shader
			if shader:
				var m = ShaderMaterial.new()
				m.shader = shader
				m.set_shader_parameter("blur_lod", 4.0)
				_frosted_rect.material = m
	
	# Ensure background has SAME radius as border (14) — fix mismatch where bg was square but border rounded
	var sb: StyleBoxFlat
	if _frosted_rect.has_theme_stylebox_override("panel"):
		sb = _frosted_rect.get_theme_stylebox("panel") as StyleBoxFlat
	else:
		sb = StyleBoxFlat.new()
		_frosted_rect.add_theme_stylebox_override("panel", sb)
	if sb:
		sb.bg_color = Color(0.20, 0.22, 0.24, 0.38) # src.a 0.38 = 62% blur + 38% tint (shader mixes)
		sb.corner_radius_top_left = 14
		sb.corner_radius_top_right = 14
		sb.corner_radius_bottom_left = 14
		sb.corner_radius_bottom_right = 14
		sb.border_width_left = 0
		sb.border_width_right = 0
		sb.border_width_top = 0
		sb.border_width_bottom = 0

func _setup_button_styles():
	if _button == null:
		return
	# Very dim low opacity border for frosted glass legibility (iOS style)
	var normal_box = StyleBoxFlat.new()
	normal_box.bg_color = Color(0, 0, 0, 0.0)
	normal_box.corner_radius_top_left = 14
	normal_box.corner_radius_top_right = 14
	normal_box.corner_radius_bottom_left = 14
	normal_box.corner_radius_bottom_right = 14
	normal_box.border_width_left = 1
	normal_box.border_width_right = 1
	normal_box.border_width_top = 1
	normal_box.border_width_bottom = 1
	normal_box.border_color = Color(1, 1, 1, 0.10)

	var hover_box = normal_box.duplicate() as StyleBoxFlat
	hover_box.bg_color = Color(1, 1, 1, 0.08)
	hover_box.border_color = Color(1, 1, 1, 0.14)

	var pressed_box = normal_box.duplicate() as StyleBoxFlat
	pressed_box.bg_color = Color(0, 0, 0, 0.12)
	pressed_box.border_color = Color(1, 1, 1, 0.18)

	_button.add_theme_stylebox_override("normal", normal_box)
	_button.add_theme_stylebox_override("hover", hover_box)
	_button.add_theme_stylebox_override("pressed", pressed_box)
	_button.add_theme_stylebox_override("focus", normal_box)

	if ResourceLoader.exists("res://assets/fonts/RobotoSlab-Bold.ttf"):
		var bold = load("res://assets/fonts/RobotoSlab-Bold.ttf") as FontFile
		if bold:
			_button.add_theme_font_override("font", bold)

	_update_font_size()

func _update_text():
	if _button:
		_button.text = _internal_button_text
	_update_font_size()

func _update_font_size():
	if _button == null:
		return
	var len = _internal_button_text.length()
	# 25% bigger font to accommodate new button sizing
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

func set_button_disabled(disabled: bool):
	if _button:
		_button.disabled = disabled
	modulate.a = 0.5 if disabled else 1.0

func focus_button():
	if _button:
		_button.grab_focus()
	else:
		grab_focus()
