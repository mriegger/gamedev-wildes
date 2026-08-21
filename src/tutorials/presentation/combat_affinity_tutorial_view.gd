extends CanvasLayer
class_name CombatAffinityTutorialView

signal dismissed

const BUTTON_SCENE: PackedScene = preload("res://ui/components/wildes_button.tscn")
const PANEL_WIDTH: float = 760.0
const PANEL_TOP_MARGIN: float = 12.0
const SCREEN_MARGIN: float = 12.0
const HORIZONTAL_PADDING: float = 12.0
const VERTICAL_PADDING: float = 12.0
const FADE_DURATION: float = TutorialCalloutView.FADE_DURATION

var _root: Control
var _panel: Panel
var _content: VBoxContainer
var _text: RichTextLabel
var _ok_button: WildesButton
var _showing: bool = false
var _fading_out: bool = false
var _fade_progress: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 250
	_create_content()
	_hide_immediately()

func show_dialog(bbcode: String) -> void:
	assert(not bbcode.is_empty())
	_text.text = bbcode
	_root.visible = true
	_showing = true
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	_update_panel_layout()
	call_deferred("_update_panel_layout")
	set_process(true)
	_ok_button.call_deferred("focus_button")

func is_showing() -> bool:
	return _showing

func _process(delta: float) -> void:
	_update_panel_layout()
	var direction := -1.0 if _fading_out else 1.0
	_fade_progress = clampf(_fade_progress + direction * delta / FADE_DURATION, 0.0, 1.0)
	_apply_fade(smoothstep(0.0, 1.0, _fade_progress))
	if _fading_out and is_zero_approx(_fade_progress):
		_hide_immediately()
		dismissed.emit()

func _create_content() -> void:
	_root = Control.new()
	_root.name = "Content"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	get_viewport().size_changed.connect(_update_panel_layout)
	var dim := ColorRect.new()
	dim.name = "BackgroundDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.14)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_panel = Panel.new()
	_panel.name = "DialogPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	WildesStyle.apply_frosted_panel(_panel, WildesStyle.make_modal(), 4.5, false)
	_root.add_child(_panel)
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = HORIZONTAL_PADDING
	_content.offset_top = VERTICAL_PADDING
	_content.offset_right = -HORIZONTAL_PADDING
	_content.offset_bottom = -VERTICAL_PADDING
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_theme_constant_override("separation", roundi(WildesStyle.REGULAR_FONT.get_height(16)))
	_panel.add_child(_content)
	_text = RichTextLabel.new()
	_text.name = "Instructions"
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_text.add_theme_font_override("normal_font", WildesStyle.REGULAR_FONT)
	_text.add_theme_font_override("bold_font", WildesStyle.BOLD_FONT)
	_text.add_theme_font_size_override("normal_font_size", 16)
	_text.add_theme_color_override("default_color", Color(0.96, 0.95, 0.9, 1.0))
	_content.add_child(_text)
	_ok_button = BUTTON_SCENE.instantiate() as WildesButton
	_ok_button.name = "OkButton"
	_ok_button.button_text = "OK"
	_ok_button.button_font_size = 15
	_ok_button.custom_minimum_size = Vector2(120.0, 40.0)
	_ok_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_ok_button.pressed.connect(_on_ok_pressed)
	_content.add_child(_ok_button)
	call_deferred("_update_panel_layout")

func _update_panel_layout() -> void:
	if _panel == null or _content == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var panel_width := minf(PANEL_WIDTH, maxf(1.0, viewport_size.x - SCREEN_MARGIN * 2.0))
	_text.custom_minimum_size.x = maxf(1.0, panel_width - HORIZONTAL_PADDING * 2.0)
	_text.size.x = _text.custom_minimum_size.x
	var text_height := maxf(WildesStyle.REGULAR_FONT.get_height(16), _text.get_content_height())
	_text.custom_minimum_size.y = text_height
	var button_gap := float(_content.get_theme_constant("separation"))
	var panel_height := text_height + button_gap + _ok_button.custom_minimum_size.y + VERTICAL_PADDING * 2.0
	var available_height := viewport_size.y * 0.5 - SCREEN_MARGIN - PANEL_TOP_MARGIN
	var panel_scale := minf(1.0, maxf(0.1, available_height / panel_height))
	_panel.scale = Vector2.ONE * panel_scale
	_panel.offset_left = -panel_width * panel_scale * 0.5
	_panel.offset_top = PANEL_TOP_MARGIN
	_panel.offset_right = _panel.offset_left + panel_width
	_panel.offset_bottom = PANEL_TOP_MARGIN + panel_height

func _on_ok_pressed() -> void:
	if not _showing:
		return
	_showing = false
	_fading_out = true
	set_process(true)

func _hide_immediately() -> void:
	if _root != null:
		_root.visible = false
	_showing = false
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(false)

func _apply_fade(progress: float) -> void:
	if _root != null:
		_root.modulate = Color(1.0, 1.0, 1.0, clampf(progress, 0.0, 1.0))
