extends RefCounted
class_name WildesStyle


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


static func make_modal(radius: int = MODAL_RADIUS, border_color: Color = MODAL_BORDER) -> StyleBoxFlat:
	return make_panel(MODAL_BG, radius, border_color, 1)

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
	dup.set_shader_parameter("fade", 1.0)
	return dup

static func make_frosted_button_material(lod: float = 4.0) -> ShaderMaterial:
	var dup := FROSTED_BUTTON_MAT.duplicate() as ShaderMaterial
	dup.set_shader_parameter("blur_lod", lod)
	dup.set_shader_parameter("fade", 1.0)
	return dup

static func apply_frosted_panel(panel: Panel, sb: StyleBoxFlat, lod: float = 4.5, is_button: bool = false) -> void:
	if panel == null:
		return
	if is_button:
		panel.material = make_frosted_button_material(lod)
	else:
		panel.material = make_frosted_panel_material(lod)
	panel.add_theme_stylebox_override("panel", sb)

static func set_frosted_fade(panel: Panel, fade: float) -> void:
	if panel == null or panel.material == null:
		return
	if panel.material is ShaderMaterial:
		var sm := panel.material as ShaderMaterial
		# Duplicate shared on-disk .tres so one panel fading doesn't bleed to all
		# instances that share the same resource and we don't dirty the file on disk.
		if sm.resource_path != "" or sm == FROSTED_PANEL_MAT or sm == FROSTED_BUTTON_MAT:
			sm = sm.duplicate() as ShaderMaterial
			panel.material = sm
		sm.set_shader_parameter("fade", clamp(fade, 0.0, 1.0))
