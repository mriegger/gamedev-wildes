extends RefCounted
class_name WildesStyle

# Central UI factory - consolidates StyleBoxFlat creation to one callsite.
# Always constructs fresh instances, never reads back theme stylebox and mutates shared state.
# Fixes class of bugs where get_theme_stylebox("panel") returned theme resource and mutation leaked.

const MODAL_BG: Color = Color(0.14, 0.16, 0.18, 0.32)
const MODAL_RADIUS: int = 18
const MODAL_BORDER: Color = Color(1, 1, 1, 0.20)

const BUTTON_BG: Color = Color(0.20, 0.22, 0.24, 0.38)
const BUTTON_RADIUS: int = 14
const BUTTON_BORDER: Color = Color(1, 1, 1, 0.20)

const BOLD_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Bold.ttf")
const FROSTED_PANEL_MAT: ShaderMaterial = preload("res://shaders/frosted_panel_material.tres")
const FROSTED_BUTTON_MAT: ShaderMaterial = preload("res://shaders/frosted_button_material.tres")


static func make_panel(bg: Color, radius: int, border_color: Color = Color(1, 1, 1, 0.20), border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_width_left = border_width
	sb.border_width_right = border_width
	sb.border_width_top = border_width
	sb.border_width_bottom = border_width
	sb.border_color = border_color
	return sb

static func make_panel_alpha(bg: Color, radius: int, border_alpha: float = 0.20, border_width: int = 1) -> StyleBoxFlat:
	return make_panel(bg, radius, Color(1, 1, 1, border_alpha), border_width)


# Spec: Modals - bg Color(0.14,0.16,0.18,0.32) radius 18 border 1 border Color(1,1,1,0.20) material Frosted/Blur Font Roboto Slab
static func make_modal() -> StyleBoxFlat:
	return make_panel(MODAL_BG, MODAL_RADIUS, MODAL_BORDER, 1)

# Spec: Buttons - bg Color(0.20,0.22,0.24,0.38) radius 14 border 1 border Color(1,1,1,0.20) material Frosted/Blur Font Roboto Slab
# Button implementation splits frosted rect (bg+blur, no border) and button states (transparent bg + border)
static func make_button_frosted() -> StyleBoxFlat:
	return make_panel(BUTTON_BG, BUTTON_RADIUS, Color(0, 0, 0, 0), 0)

static func make_button_normal() -> StyleBoxFlat:
	return make_panel(Color(0, 0, 0, 0.0), BUTTON_RADIUS, BUTTON_BORDER, 1)

static func make_button_hover() -> StyleBoxFlat:
	return make_panel(Color(1, 1, 1, 0.08), BUTTON_RADIUS, Color(1, 1, 1, 0.14), 1)

static func make_button_pressed() -> StyleBoxFlat:
	return make_panel(Color(0, 0, 0, 0.12), BUTTON_RADIUS, Color(1, 1, 1, 0.18), 1)

static func make_button_disabled() -> StyleBoxFlat:
	return make_panel(Color(0, 0, 0, 0.04), BUTTON_RADIUS, Color(1, 1, 1, 0.08), 1)


static func make_frosted_panel_material(lod: float = 4.5) -> ShaderMaterial:
	var dup := FROSTED_PANEL_MAT.duplicate() as ShaderMaterial
	dup.set_shader_parameter("blur_lod", lod)
	return dup

static func make_frosted_button_material(lod: float = 4.0) -> ShaderMaterial:
	var dup := FROSTED_BUTTON_MAT.duplicate() as ShaderMaterial
	dup.set_shader_parameter("blur_lod", lod)
	return dup

static func apply_frosted_panel(panel: Panel, sb: StyleBoxFlat, lod: float = 4.5, is_button: bool = false) -> void:
	if panel == null:
		return
	if is_button:
		panel.material = make_frosted_button_material(lod)
	else:
		panel.material = make_frosted_panel_material(lod)
	panel.add_theme_stylebox_override("panel", sb)
