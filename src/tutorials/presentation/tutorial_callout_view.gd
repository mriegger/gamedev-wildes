extends Node3D
class_name TutorialCalloutView

signal callout_hidden

const PANEL_SIZE := Vector2(330.0, 54.0)
const PANEL_WITH_SUBTEXT_SIZE := Vector2(410.0, 78.0)
const PANEL_GAP: float = 20.0
const TOOLTIP_HEIGHT: float = 2.1
const FADE_DURATION: float = 0.35
const OUTLINE_ALPHA: float = 0.48

var _camera: Camera3D
var _selection_box: Node3D
var _overlay: Control
var _panel: PanelContainer
var _title_label: Label
var _subtext_label: Label
var _selection_material: StandardMaterial3D
var _tooltip_anchor_position := Vector3.ZERO
var _showing: bool = false
var _fading_out: bool = false
var _outline_suppressed: bool = false
var _fade_progress: float = 0.0

func _ready() -> void:
	_create_selection_box()
	_create_overlay()
	hide_callout()

func setup(camera: Camera3D) -> void:
	assert(camera != null)
	assert(_camera == null or _camera == camera)
	_camera = camera

func show_callout(target_bounds: AABB, title: String, subtext: String = "") -> void:
	assert(_camera != null)
	assert(target_bounds.size.x > 0.0 and target_bounds.size.y > 0.0 and target_bounds.size.z > 0.0)
	assert(not title.is_empty())
	_selection_box.global_position = target_bounds.get_center()
	_selection_box.scale = target_bounds.size / BlockOutlineBuilder.EDGE_LENGTH
	_tooltip_anchor_position = Vector3(target_bounds.get_center().x, target_bounds.end.y + TOOLTIP_HEIGHT, target_bounds.get_center().z)
	_title_label.text = title
	_subtext_label.text = subtext
	_subtext_label.visible = not subtext.is_empty()
	_panel.custom_minimum_size = PANEL_WITH_SUBTEXT_SIZE if _subtext_label.visible else PANEL_SIZE
	_panel.size = _panel.custom_minimum_size
	_outline_suppressed = false
	_selection_box.visible = true
	_overlay.visible = true
	_showing = true
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(true)
	_update_overlay()

func hide_callout() -> void:
	if _showing:
		_showing = false
		_fading_out = true
		set_process(true)
		return
	if _fading_out:
		return
	_hide_immediately()

func _hide_immediately() -> void:
	if _selection_box != null:
		_selection_box.visible = false
	if _overlay != null:
		_overlay.visible = false
	_showing = false
	_fading_out = false
	_outline_suppressed = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(false)

func is_showing() -> bool:
	return _showing

func set_outline_suppressed(suppressed: bool) -> void:
	_outline_suppressed = suppressed
	_selection_box.visible = (_showing or _fading_out) and not _outline_suppressed

func _process(delta: float) -> void:
	var direction := -1.0 if _fading_out else 1.0
	_fade_progress = clampf(_fade_progress + direction * delta / FADE_DURATION, 0.0, 1.0)
	_apply_fade(smoothstep(0.0, 1.0, _fade_progress))
	_update_overlay()
	if _fading_out and is_zero_approx(_fade_progress):
		_fading_out = false
		_outline_suppressed = false
		_selection_box.visible = false
		_overlay.visible = false
		set_process(false)
		callout_hidden.emit()

func _create_selection_box() -> void:
	_selection_material = StandardMaterial3D.new()
	_selection_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_selection_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_selection_box = BlockOutlineBuilder.create_outline("TutorialSelectionBox", _selection_material)
	add_child(_selection_box)

func _create_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "OverlayLayer"
	layer.layer = 20
	add_child(layer)
	_overlay = Control.new()
	_overlay.name = "Overlay"
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)
	_panel = PanelContainer.new()
	_panel.name = "TipPanel"
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", create_panel_style())
	var text_container := VBoxContainer.new()
	text_container.name = "Text"
	text_container.alignment = BoxContainer.ALIGNMENT_CENTER
	text_container.add_theme_constant_override("separation", 2)
	_panel.add_child(text_container)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1.0))
	_title_label.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	_title_label.add_theme_font_size_override("font_size", 16)
	text_container.add_child(_title_label)
	_subtext_label = Label.new()
	_subtext_label.name = "Subtext"
	_subtext_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtext_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtext_label.add_theme_color_override("font_color", Color(0.78, 0.8, 0.84, 1.0))
	_subtext_label.add_theme_font_override("font", WildesStyle.REGULAR_FONT)
	_subtext_label.add_theme_font_size_override("font_size", 12)
	text_container.add_child(_subtext_label)
	_overlay.add_child(_panel)

func _update_overlay() -> void:
	if _camera == null or (not _showing and not _fading_out):
		return
	if _camera.is_position_behind(_tooltip_anchor_position):
		_overlay.visible = false
		return
	_overlay.visible = true
	var viewport_rect := get_viewport().get_visible_rect()
	var target_screen := _camera.unproject_position(_tooltip_anchor_position)
	var panel_size := _panel.custom_minimum_size
	var panel_position := target_screen - Vector2(panel_size.x * 0.5, panel_size.y + PANEL_GAP)
	panel_position.x = clampf(panel_position.x, 12.0, maxf(12.0, viewport_rect.size.x - panel_size.x - 12.0))
	panel_position.y = clampf(panel_position.y, 12.0, maxf(12.0, viewport_rect.size.y - panel_size.y - 12.0))
	_panel.position = panel_position

func _apply_fade(progress: float) -> void:
	var fade := clampf(progress, 0.0, 1.0)
	_overlay.modulate = Color(1.0, 1.0, 1.0, fade)
	_selection_material.albedo_color = Color(1.0, 1.0, 1.0, OUTLINE_ALPHA * fade)

static func create_panel_style() -> StyleBoxFlat:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	panel_style.border_color = Color(0.72, 0.74, 0.78, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_top = 8.0
	panel_style.content_margin_bottom = 8.0
	return panel_style
