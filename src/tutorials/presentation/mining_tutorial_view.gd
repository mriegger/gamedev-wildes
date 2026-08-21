extends Node3D
class_name MiningTutorialView

const PANEL_SIZE := Vector2(330.0, 54.0)
const PANEL_GAP: float = 20.0
const TOOLTIP_HEIGHT: float = 2.1
const FADE_DURATION: float = 0.35
const OUTLINE_ALPHA: float = 0.48

var _camera: Camera3D
var _selection_box: Node3D
var _overlay: Control
var _panel: PanelContainer
var _selection_material: StandardMaterial3D
var _tooltip_anchor_position := Vector3.ZERO
var _showing: bool = false
var _fading_out: bool = false
var _outline_suppressed: bool = false
var _fade_progress: float = 0.0

func _ready() -> void:
	_create_selection_box()
	_create_overlay()
	hide_tip()

func setup(camera: Camera3D) -> void:
	assert(camera != null)
	assert(_camera == null or _camera == camera)
	_camera = camera

func show_tip(block_position: Vector3i) -> void:
	assert(_camera != null)
	var block_top_center := Vector3(block_position) + Vector3(0.5, 1.0, 0.5)
	_selection_box.global_position = Vector3(block_position) + Vector3(0.5, 0.5, 0.5)
	_selection_box.scale = Vector3.ONE / BlockOutlineBuilder.EDGE_LENGTH
	_tooltip_anchor_position = block_top_center + Vector3.UP * TOOLTIP_HEIGHT
	_outline_suppressed = false
	_selection_box.visible = true
	_overlay.visible = true
	_showing = true
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(true)
	_update_overlay()

func hide_tip() -> void:
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
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.11, 0.96)
	panel_style.border_color = Color(0.72, 0.74, 0.78, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 12.0
	panel_style.content_margin_right = 12.0
	panel_style.content_margin_top = 10.0
	panel_style.content_margin_bottom = 10.0
	_panel.add_theme_stylebox_override("panel", panel_style)
	var label := Label.new()
	label.name = "Text"
	label.text = "Hold left mouse button to mine blocks"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1.0))
	label.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	label.add_theme_font_size_override("font_size", 16)
	_panel.add_child(label)
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
	var panel_position := target_screen - Vector2(PANEL_SIZE.x * 0.5, PANEL_SIZE.y + PANEL_GAP)
	panel_position.x = clampf(panel_position.x, 12.0, maxf(12.0, viewport_rect.size.x - PANEL_SIZE.x - 12.0))
	panel_position.y = clampf(panel_position.y, 12.0, maxf(12.0, viewport_rect.size.y - PANEL_SIZE.y - 12.0))
	_panel.position = panel_position

func _apply_fade(progress: float) -> void:
	var fade := clampf(progress, 0.0, 1.0)
	_overlay.modulate = Color(1.0, 1.0, 1.0, fade)
	_selection_material.albedo_color = Color(1.0, 1.0, 1.0, OUTLINE_ALPHA * fade)
