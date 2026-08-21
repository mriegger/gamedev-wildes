extends Control
class_name CraftingPanel

signal progress_changed(progress: float)
signal opened
signal closed
signal interacted

const PANEL_WIDTH: float = 520.0
const ANIM_DURATION: float = 0.25
const HOTBAR_CLEARANCE: float = 112.0
const ITEM_ICON_SIZE: float = 32.0
const RECIPE_ICON_FRAME_SIZE: float = 54.0
const RECIPE_SCROLL_STEP: float = 61.0
const RECIPE_PAN_SCROLL_SCALE: float = 32.0
const CRAFTING_WORKSPACE_ID: StringName = &"crafting"
const RUNES_WORKSPACE_ID: StringName = &"runes"
const PROGRESSION_WORKSPACE_ID: StringName = &"progression"

@onready var _background: Panel = $Background as Panel
@onready var _content: Control = $Margin/Content as Control
@onready var _title_label: Label = $Margin/Content/Title as Label
@onready var _workspace_tabs: HBoxContainer = $Margin/Content/WorkspaceTabs as HBoxContainer
@onready var _crafting_tab: Button = $Margin/Content/WorkspaceTabs/Crafting as Button
@onready var _runes_tab: Button = $Margin/Content/WorkspaceTabs/Runes as Button
@onready var _progression_tab: Button = $Margin/Content/WorkspaceTabs/Progression as Button
@onready var _crafting_body: Control = $Margin/Content/Body as Control
@onready var _rune_socketing_panel: RuneSocketingPanel = $Margin/Content/RuneSocketingPanel as RuneSocketingPanel
@onready var _recipe_scroll: ScrollContainer = $Margin/Content/Body/Recipes/RecipeScroll as ScrollContainer
@onready var _progression_panel: ProgressionPanel = $Margin/Content/ProgressionPanel as ProgressionPanel
@onready var _recipe_list: VBoxContainer = $Margin/Content/Body/Recipes/RecipeScroll/RecipeList as VBoxContainer
@onready var _output_icon: TextureRect = $Margin/Content/Body/Details/Output/IconFrame/Icon as TextureRect
@onready var _output_name: Label = $Margin/Content/Body/Details/Output/Text/Name as Label
@onready var _output_count: Label = $Margin/Content/Body/Details/Output/Text/Count as Label
@onready var _output_description: Label = $Margin/Content/Body/Details/Description as Label
@onready var _ingredients_heading: Label = $Margin/Content/Body/Details/IngredientsHeading as Label
@onready var _ingredient_list: VBoxContainer = $Margin/Content/Body/Details/IngredientList as VBoxContainer
@onready var _stats_heading: Label = $Margin/Content/Body/Details/StatsHeading as Label
@onready var _stats_label: RichTextLabel = $Margin/Content/Body/Details/Stats as RichTextLabel
@onready var _craft_button: Control = $Margin/Content/Body/Details/CraftButton as Control
@onready var _crafting_sound_player: AudioStreamPlayer = $CraftingSoundPlayer as AudioStreamPlayer

var crafting_coordinator: CraftingCoordinator
var recipe_catalog: CraftingRecipeCatalog

var _recipe_buttons: Dictionary = {}
var _selected_recipe_id: StringName = &""
var _progress: float = 0.0
var _target_progress: float = 0.0
var _is_open: bool = false
var _current_workspace_id: StringName = CRAFTING_WORKSPACE_ID
var _crafting_title: String = "CRAFTING"
var _workspace_tabs_enabled: bool = true
var _crafting_sound_stream: AudioStream = preload("res://assets/audio/sfx/tools/impactGeneric_light_004.ogg")

func _ready() -> void:
	set_process_input(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	WildesStyle.apply_frosted_panel(_background, WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.32), 0, Color(1, 1, 1, 0.12), 1), 5.0, false)
	_craft_button.pressed.connect(_on_craft_pressed)
	_recipe_scroll.gui_input.connect(_on_recipe_scroll_gui_input)
	_crafting_tab.pressed.connect(_switch_workspace.bind(CRAFTING_WORKSPACE_ID))
	_runes_tab.pressed.connect(_switch_workspace.bind(RUNES_WORKSPACE_ID))
	_progression_tab.pressed.connect(_switch_workspace.bind(PROGRESSION_WORKSPACE_ID))
	_style_workspace_tabs()
	_apply_workspace()
	_crafting_sound_player.stream = _crafting_sound_stream
	_update_size()
	_apply_state()
	set_process(false)

func _input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and get_global_rect().has_point(mouse_event.position):
			interacted.emit()
	elif event is InputEventScreenTouch:
		var touch_event := event as InputEventScreenTouch
		if touch_event.pressed and get_global_rect().has_point(touch_event.position):
			interacted.emit()
	elif event is InputEventPanGesture:
		var pan_event := event as InputEventPanGesture
		if get_global_rect().has_point(pan_event.position):
			interacted.emit()

func setup(
	p_crafting_coordinator: CraftingCoordinator,
	p_recipe_catalog: CraftingRecipeCatalog,
	p_crafting_title: String = "CRAFTING",
	p_workspace_tabs_enabled: bool = true,
) -> void:
	assert(p_crafting_coordinator != null)
	assert(p_recipe_catalog != null)
	crafting_coordinator = p_crafting_coordinator
	recipe_catalog = p_recipe_catalog
	_crafting_title = p_crafting_title
	_workspace_tabs_enabled = p_workspace_tabs_enabled
	crafting_coordinator.state_changed.connect(_on_crafting_state_changed)
	_build_recipe_list()
	if not recipe_catalog.definitions.is_empty():
		_select_recipe(recipe_catalog.definitions[0].id)
	_apply_workspace()

func setup_socketing(
	inventory: InventoryModel,
	socketing_coordinator: RuneSocketingCoordinator,
	item_proficiency: ItemProficiency,
) -> void:
	_rune_socketing_panel.setup(inventory, socketing_coordinator, item_proficiency)

func setup_progression(actor_stats: ActorStats, perk_coordinator: PlayerPerkCoordinator) -> void:
	_progression_panel.setup(actor_stats, perk_coordinator)

func open() -> void:
	var was_open := _is_open
	_is_open = true
	_target_progress = 1.0
	_switch_workspace(CRAFTING_WORKSPACE_ID)
	_refresh_details()
	set_process(true)
	if not was_open:
		opened.emit()

func close() -> void:
	var was_open := _is_open
	_is_open = false
	_target_progress = 0.0
	_rune_socketing_panel.clear_gear_reference()
	_crafting_sound_player.stop()
	_apply_workspace()
	set_process(true)
	if was_open:
		closed.emit()

func close_immediate() -> void:
	var was_open := _is_open
	_is_open = false
	_progress = 0.0
	_target_progress = 0.0
	_rune_socketing_panel.clear_gear_reference()
	_crafting_sound_player.stop()
	_apply_workspace()
	_update_size()
	_apply_state()
	set_process(false)
	if was_open:
		closed.emit()

func is_open() -> bool:
	return _is_open

func get_progress() -> float:
	return _progress

func get_selected_recipe_id() -> StringName:
	return _selected_recipe_id

func select_recipe(recipe_id: StringName) -> void:
	_select_recipe(recipe_id)

func get_craft_button() -> Control:
	return _craft_button

func get_ingredients_global_rect() -> Rect2:
	return _ingredients_heading.get_global_rect().merge(_ingredient_list.get_global_rect())

func get_current_workspace_id() -> StringName:
	return _current_workspace_id

func get_rune_socketing_panel() -> RuneSocketingPanel:
	return _rune_socketing_panel

func get_progression_panel() -> ProgressionPanel:
	return _progression_panel

func _switch_workspace(workspace_id: StringName) -> void:
	if not _workspace_tabs_enabled and workspace_id != CRAFTING_WORKSPACE_ID:
		return
	if (
		workspace_id != CRAFTING_WORKSPACE_ID
		and workspace_id != RUNES_WORKSPACE_ID
		and workspace_id != PROGRESSION_WORKSPACE_ID
	):
		return
	if workspace_id != CRAFTING_WORKSPACE_ID:
		_crafting_sound_player.stop()
	_current_workspace_id = workspace_id
	_apply_workspace()

func _apply_workspace() -> void:
	if not is_node_ready():
		return
	var crafting_visible := not _workspace_tabs_enabled or _current_workspace_id == CRAFTING_WORKSPACE_ID
	var runes_visible := _workspace_tabs_enabled and _current_workspace_id == RUNES_WORKSPACE_ID
	var progression_visible := _workspace_tabs_enabled and _current_workspace_id == PROGRESSION_WORKSPACE_ID
	_crafting_body.visible = crafting_visible
	_rune_socketing_panel.visible = runes_visible
	_progression_panel.visible = progression_visible
	_progression_panel.set_workspace_active(_is_open and progression_visible)
	_workspace_tabs.visible = _workspace_tabs_enabled
	if crafting_visible:
		_title_label.text = _crafting_title
	elif runes_visible:
		_title_label.text = "RUNES"
	else:
		_title_label.text = "PROGRESSION"
	_crafting_tab.set_pressed_no_signal(crafting_visible)
	_runes_tab.set_pressed_no_signal(runes_visible)
	_progression_tab.set_pressed_no_signal(progression_visible)

func _style_workspace_tabs() -> void:
	for tab in [_crafting_tab, _runes_tab, _progression_tab]:
		tab.add_theme_font_override(&"font", WildesStyle.BOLD_FONT)
		tab.add_theme_font_size_override(&"font_size", 13)
		tab.add_theme_stylebox_override(&"normal", WildesStyle.make_panel(Color(0.10, 0.12, 0.14, 0.42), 7, Color(1, 1, 1, 0.10), 1))
		tab.add_theme_stylebox_override(&"hover", WildesStyle.make_panel(Color(1, 1, 1, 0.08), 7, Color(1, 1, 1, 0.18), 1))
		tab.add_theme_stylebox_override(&"pressed", WildesStyle.make_panel(Color(0.32, 0.48, 0.39, 0.54), 7, Color(0.62, 0.86, 0.69, 0.58), 1))

func _process(delta: float) -> void:
	if not is_equal_approx(_progress, _target_progress):
		var weight := 1.0 - exp(-3.5 / ANIM_DURATION * delta)
		_progress = lerpf(_progress, _target_progress, weight)
		if absf(_progress - _target_progress) < 0.001:
			_progress = _target_progress
		_apply_state()
	if is_equal_approx(_progress, _target_progress):
		set_process(false)

func _build_recipe_list() -> void:
	for child in _recipe_list.get_children():
		child.free()
	_recipe_buttons.clear()
	for recipe in recipe_catalog.definitions:
		var button := Button.new()
		button.name = String(recipe.id).to_pascal_case()
		button.custom_minimum_size = Vector2(0, RECIPE_ICON_FRAME_SIZE)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.tooltip_text = recipe.output_item.display_name
		var content := HBoxContainer.new()
		content.name = "Content"
		content.anchor_right = 1.0
		content.anchor_bottom = 1.0
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 0)
		button.add_child(content)
		var icon_frame := CenterContainer.new()
		icon_frame.name = "IconFrame"
		icon_frame.custom_minimum_size = Vector2(RECIPE_ICON_FRAME_SIZE, RECIPE_ICON_FRAME_SIZE)
		icon_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon_frame)
		var icon := TextureRect.new()
		icon.name = "Icon"
		icon.custom_minimum_size = Vector2(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
		icon.texture = recipe.output_item.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_frame.add_child(icon)
		var label := Label.new()
		label.name = "Label"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.text = recipe.output_item.display_name
		if recipe.output_count > 1:
			label.text += "  ×%d" % recipe.output_count
		label.add_theme_font_override("font", WildesStyle.BOLD_FONT)
		label.add_theme_font_size_override("font_size", 13)
		content.add_child(label)
		button.add_theme_stylebox_override("normal", WildesStyle.make_panel(Color(0.10, 0.12, 0.14, 0.45), 8, Color(1, 1, 1, 0.10), 1))
		button.add_theme_stylebox_override("hover", WildesStyle.make_panel(Color(1, 1, 1, 0.08), 8, Color(1, 1, 1, 0.18), 1))
		button.add_theme_stylebox_override("pressed", WildesStyle.make_panel(Color(0.42, 0.58, 0.48, 0.42), 8, Color(0.72, 0.92, 0.76, 0.58), 1))
		button.pressed.connect(_select_recipe.bind(recipe.id))
		_recipe_list.add_child(button)
		_recipe_buttons[recipe.id] = button

func _select_recipe(recipe_id: StringName) -> void:
	if recipe_catalog == null or not recipe_catalog.has_definition(recipe_id):
		return
	_selected_recipe_id = recipe_id
	for id in _recipe_buttons:
		(_recipe_buttons[id] as Button).set_pressed_no_signal(id == recipe_id)
	_refresh_details()

func _on_recipe_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if not mouse_event.pressed or mouse_event.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		var factor := mouse_event.factor if mouse_event.factor > 0.0 else 1.0
		var offset := roundi(RECIPE_SCROLL_STEP * factor)
		if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_recipe_scroll.scroll_vertical -= offset
		else:
			_recipe_scroll.scroll_vertical += offset
		_recipe_scroll.accept_event()
	elif event is InputEventPanGesture:
		var pan_event := event as InputEventPanGesture
		_recipe_scroll.scroll_vertical += roundi(pan_event.delta.y * RECIPE_PAN_SCROLL_SCALE)
		_recipe_scroll.accept_event()

func _refresh_details() -> void:
	if recipe_catalog == null or _selected_recipe_id.is_empty():
		return
	var recipe := recipe_catalog.get_definition(_selected_recipe_id)
	_output_icon.texture = recipe.output_item.icon
	_output_name.text = recipe.output_item.display_name
	_output_count.text = "Creates ×%d" % recipe.output_count
	_output_description.text = recipe.output_item.description
	for child in _ingredient_list.get_children():
		child.free()
	for ingredient in recipe.ingredients:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 38.0
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(ITEM_ICON_SIZE, ITEM_ICON_SIZE)
		icon.texture = ingredient.item.icon
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var available := crafting_coordinator.inventory_model.get_inventory_item_count(ingredient.item.id)
		label.text = "%s    %d / %d" % [ingredient.item.display_name, available, ingredient.count]
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.72, 0.92, 0.76) if available >= ingredient.count else Color(0.92, 0.58, 0.52))
		row.add_child(label)
		_ingredient_list.add_child(row)
	var stat_lines := ItemStatFormatter.get_item_stat_lines(recipe.output_item)
	_stats_heading.visible = not stat_lines.is_empty()
	_stats_label.visible = not stat_lines.is_empty()
	_stats_label.text = "\n".join(stat_lines)
	_refresh_craft_button()

func _refresh_craft_button() -> void:
	if crafting_coordinator == null or _selected_recipe_id.is_empty():
		_craft_button.set_craft_enabled(false)
		return
	_craft_button.set_craft_enabled(crafting_coordinator.can_craft(_selected_recipe_id))

func _on_craft_pressed() -> void:
	if crafting_coordinator.craft(_selected_recipe_id):
		_crafting_sound_player.play()
	_refresh_craft_button()

func _on_crafting_state_changed() -> void:
	_refresh_details()

func _exit_tree() -> void:
	if _crafting_sound_player != null:
		_crafting_sound_player.stop()
		_crafting_sound_player.stream = null
	_crafting_sound_stream = null

func _update_size() -> void:
	var viewport_size := Vector2(1280, 720)
	var viewport := get_viewport()
	if viewport != null and viewport.get_visible_rect().size.x > 10.0:
		viewport_size = viewport.get_visible_rect().size
	var panel_height := maxf(0.0, viewport_size.y - HOTBAR_CLEARANCE)
	custom_minimum_size = Vector2(PANEL_WIDTH, panel_height)
	size = Vector2(PANEL_WIDTH, panel_height)

func _apply_state() -> void:
	position = Vector2(-PANEL_WIDTH * (1.0 - _progress), 0.0)
	mouse_filter = Control.MOUSE_FILTER_STOP if _progress > 0.01 else Control.MOUSE_FILTER_IGNORE
	_content.modulate = Color(1, 1, 1, _progress)
	WildesStyle.set_frosted_fade(_background, _progress)
	progress_changed.emit(_progress)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_size()
		_apply_state()
