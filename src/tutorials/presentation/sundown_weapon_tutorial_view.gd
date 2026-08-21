extends CanvasLayer
class_name SundownWeaponTutorialView

signal tip_hidden

const PANEL_SIZE := Vector2(400.0, 72.0)
const SCREEN_MARGIN := Vector2(24.0, 24.0)
const DISPLAY_DURATION_SECONDS: float = 15.0
const FADE_DURATION: float = TutorialCalloutView.FADE_DURATION

var _panel: PanelContainer
var _showing: bool = false
var _fading_out: bool = false
var _fade_progress: float = 0.0
var _display_elapsed: float = 0.0

func _ready() -> void:
	layer = 20
	_create_panel()
	_hide_immediately()

func show_tip() -> void:
	_panel.visible = true
	_showing = true
	_fading_out = false
	_fade_progress = 0.0
	_display_elapsed = 0.0
	_apply_fade(0.0)
	set_process(true)

func hide_tip() -> void:
	if _showing:
		_showing = false
		_fading_out = true
		set_process(true)
		return
	if not _fading_out:
		_hide_immediately()

func is_showing() -> bool:
	return _showing

func _process(delta: float) -> void:
	if _fading_out:
		_fade_progress = maxf(0.0, _fade_progress - delta / FADE_DURATION)
		_apply_fade(smoothstep(0.0, 1.0, _fade_progress))
		if is_zero_approx(_fade_progress):
			_hide_immediately()
			tip_hidden.emit()
		return
	var fade_seconds_remaining := (1.0 - _fade_progress) * FADE_DURATION
	var fade_delta := minf(delta, fade_seconds_remaining)
	_fade_progress = minf(1.0, _fade_progress + fade_delta / FADE_DURATION)
	_apply_fade(smoothstep(0.0, 1.0, _fade_progress))
	if _fade_progress < 1.0:
		return
	_display_elapsed += delta - fade_delta
	if _display_elapsed >= DISPLAY_DURATION_SECONDS:
		hide_tip()

func _create_panel() -> void:
	_panel = PanelContainer.new()
	_panel.name = "TipPanel"
	_panel.position = SCREEN_MARGIN
	_panel.custom_minimum_size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	TutorialCalloutView.apply_panel_style(_panel)
	var label := Label.new()
	label.name = "Text"
	label.text = "Night approaching! Craft a weapon at the\nAnvil to defend yourself against enemy threats."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1.0))
	label.add_theme_font_override("font", WildesStyle.REGULAR_FONT)
	label.add_theme_font_size_override("font_size", 16)
	_panel.add_child(label)
	add_child(_panel)

func _hide_immediately() -> void:
	if _panel != null:
		_panel.visible = false
	_showing = false
	_fading_out = false
	_fade_progress = 0.0
	_display_elapsed = 0.0
	_apply_fade(0.0)
	set_process(false)

func _apply_fade(progress: float) -> void:
	var fade := clampf(progress, 0.0, 1.0)
	_panel.modulate = Color(1.0, 1.0, 1.0, fade)
	TutorialCalloutView.set_panel_fade(_panel, fade)
