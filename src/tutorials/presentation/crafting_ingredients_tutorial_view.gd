extends CanvasLayer
class_name CraftingIngredientsTutorialView

signal tip_hidden

const OUTLINE_MARGIN: float = 6.0
const OUTLINE_WIDTH: int = 2
const TOOLTIP_GAP: float = 14.0
const TOOLTIP_SIZE := Vector2(280.0, 50.0)
const SCREEN_MARGIN: float = 12.0
const FADE_DURATION: float = TutorialCalloutView.FADE_DURATION

var _crafting_panel: CraftingPanel
var _root: Control
var _outline: Panel
var _tooltip: PanelContainer
var _showing: bool = false
var _fading_out: bool = false
var _fade_progress: float = 0.0

func _ready() -> void:
	layer = 20
	_create_content()
	_hide_immediately()

func setup(crafting_panel: CraftingPanel) -> void:
	assert(crafting_panel != null)
	assert(_crafting_panel == null or _crafting_panel == crafting_panel)
	_crafting_panel = crafting_panel

func show_tip() -> void:
	assert(_crafting_panel != null and _crafting_panel.is_open())
	_root.visible = true
	_showing = true
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	_update_layout()
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
	if not _fading_out:
		_update_layout()
	if _fading_out and is_zero_approx(_fade_progress):
		_fading_out = false
		_root.visible = false
		set_process(false)
		tip_hidden.emit()

func _create_content() -> void:
	_root = Control.new()
	_root.name = "Content"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_outline = Panel.new()
	_outline.name = "IngredientsOutline"
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := StyleBoxFlat.new()
	outline_style.bg_color = Color.TRANSPARENT
	outline_style.border_color = Color.WHITE
	outline_style.set_border_width_all(OUTLINE_WIDTH)
	outline_style.set_corner_radius_all(4)
	_outline.add_theme_stylebox_override("panel", outline_style)
	_root.add_child(_outline)
	_tooltip = PanelContainer.new()
	_tooltip.name = "TipPanel"
	_tooltip.custom_minimum_size = TOOLTIP_SIZE
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("panel", TutorialCalloutView.create_panel_style())
	var label := Label.new()
	label.name = "Text"
	label.text = "Collect resources to craft items"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1.0))
	label.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	label.add_theme_font_size_override("font_size", 16)
	_tooltip.add_child(label)
	_root.add_child(_tooltip)

func _update_layout() -> void:
	if _crafting_panel == null:
		return
	var ingredients_rect := _crafting_panel.get_ingredients_global_rect().grow(OUTLINE_MARGIN)
	_outline.position = ingredients_rect.position
	_outline.size = ingredients_rect.size
	var viewport_size := get_viewport().get_visible_rect().size
	var tooltip_position := Vector2(
		ingredients_rect.end.x + TOOLTIP_GAP,
		ingredients_rect.position.y + (ingredients_rect.size.y - TOOLTIP_SIZE.y) * 0.5,
	)
	tooltip_position.x = minf(tooltip_position.x, viewport_size.x - TOOLTIP_SIZE.x - SCREEN_MARGIN)
	tooltip_position.y = clampf(tooltip_position.y, SCREEN_MARGIN, viewport_size.y - TOOLTIP_SIZE.y - SCREEN_MARGIN)
	_tooltip.position = tooltip_position
	_tooltip.size = TOOLTIP_SIZE

func _hide_immediately() -> void:
	if _root != null:
		_root.visible = false
	_showing = false
	_fading_out = false
	_fade_progress = 0.0
	_apply_fade(0.0)
	set_process(false)

func _apply_fade(progress: float) -> void:
	_root.modulate = Color(1.0, 1.0, 1.0, clampf(progress, 0.0, 1.0))
