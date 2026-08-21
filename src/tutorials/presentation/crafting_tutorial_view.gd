extends CanvasLayer
class_name CraftingTutorialView

signal tip_hidden

const PANEL_SIZE := Vector2(280.0, 50.0)
const SCREEN_MARGIN := Vector2(24.0, 24.0)
const FADE_DURATION: float = TutorialCalloutView.FADE_DURATION

var _panel: PanelContainer
var _showing: bool = false
var _fading_out: bool = false
var _fade_progress: float = 0.0

func _ready() -> void:
	layer = 20
	_create_panel()
	_hide_immediately()

func show_tip() -> void:
	_panel.visible = true
	_showing = true
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(true)

func hide_tip() -> void:
	if _showing:
		_showing = false
		_fading_out = true
		set_process(true)
		return
	if _fading_out:
		return
	_hide_immediately()

func is_showing() -> bool:
	return _showing

func _process(delta: float) -> void:
	var direction := -1.0 if _fading_out else 1.0
	_fade_progress = clampf(_fade_progress + direction * delta / FADE_DURATION, 0.0, 1.0)
	_apply_fade(smoothstep(0.0, 1.0, _fade_progress))
	if _fading_out and is_zero_approx(_fade_progress):
		_fading_out = false
		_panel.visible = false
		set_process(false)
		tip_hidden.emit()

func _create_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "TipPanel"
	_panel.position = SCREEN_MARGIN
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", TutorialCalloutView.create_panel_style())
	var label := Label.new()
	label.name = "Text"
	label.text = "Press Tab to open Crafting menu"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1.0))
	label.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	label.add_theme_font_size_override("font_size", 16)
	_panel.add_child(label)
	add_child(_panel)

func _hide_immediately() -> void:
	if _panel != null:
		_panel.visible = false
	_showing = false
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(false)

func _apply_fade(progress: float) -> void:
	_panel.modulate = Color(1.0, 1.0, 1.0, clampf(progress, 0.0, 1.0))
