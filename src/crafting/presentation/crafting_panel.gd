extends Control
class_name CraftingPanel

const PANEL_WIDTH: float = 520.0
const ANIM_DURATION: float = 0.25
const HOTBAR_CLEARANCE: float = 112.0
const CRAFTING_IMPACT_INTERVAL: float = 0.5

@onready var _background: Panel = $Background as Panel
@onready var _content: Control = $Margin/Content as Control
@onready var _recipe_list: VBoxContainer = $Margin/Content/Body/Recipes/RecipeScroll/RecipeList as VBoxContainer
@onready var _output_icon: TextureRect = $Margin/Content/Body/Details/Output/Icon as TextureRect
@onready var _output_name: Label = $Margin/Content/Body/Details/Output/Text/Name as Label
@onready var _output_count: Label = $Margin/Content/Body/Details/Output/Text/Count as Label
@onready var _ingredient_list: VBoxContainer = $Margin/Content/Body/Details/IngredientList as VBoxContainer
@onready var _craft_button: CraftProgressButton = $Margin/Content/Body/Details/CraftProgressButton as CraftProgressButton
@onready var _crafting_impact_player: AudioStreamPlayer = $CraftingImpactPlayer as AudioStreamPlayer
@onready var _crafting_complete_player: AudioStreamPlayer = $CraftingCompletePlayer as AudioStreamPlayer
@onready var _crafting_impact_timer: Timer = $CraftingImpactTimer as Timer

var crafting_coordinator: CraftingCoordinator
var recipe_catalog: CraftingRecipeCatalog
var camera_rig: CameraRig

var _recipe_buttons: Dictionary = {}
var _selected_recipe_id: StringName = &""
var _progress: float = 0.0
var _target_progress: float = 0.0
var _is_open: bool = false
var _crafting_impact_stream: AudioStream = preload("res://assets/audio/sfx/tools/impactGeneric_light_003.ogg")
var _crafting_complete_stream: AudioStream = preload("res://assets/audio/sfx/tools/impactGeneric_light_004.ogg")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = true
	WildesStyle.apply_frosted_panel(_background, WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.32), 0, Color(1, 1, 1, 0.12), 1), 5.0, false)
	_craft_button.pressed.connect(_on_craft_pressed)
	_crafting_impact_player.stream = _crafting_impact_stream
	_crafting_complete_player.stream = _crafting_complete_stream
	_crafting_impact_timer.wait_time = CRAFTING_IMPACT_INTERVAL
	_crafting_impact_timer.timeout.connect(_on_crafting_impact_timeout)
	_update_size()
	_apply_state()
	set_process(false)

func setup(p_crafting_coordinator: CraftingCoordinator, p_recipe_catalog: CraftingRecipeCatalog, p_camera_rig: CameraRig = null) -> void:
	assert(p_crafting_coordinator != null)
	assert(p_recipe_catalog != null)
	crafting_coordinator = p_crafting_coordinator
	recipe_catalog = p_recipe_catalog
	camera_rig = p_camera_rig
	crafting_coordinator.state_changed.connect(_on_crafting_state_changed)
	crafting_coordinator.craft_completed.connect(_on_craft_completed)
	_build_recipe_list()
	if not recipe_catalog.definitions.is_empty():
		_select_recipe(recipe_catalog.definitions[0].id)
	_update_camera()

func open() -> void:
	_is_open = true
	_target_progress = 1.0
	_refresh_details()
	set_process(true)

func close() -> void:
	_is_open = false
	_target_progress = 0.0
	if crafting_coordinator != null:
		crafting_coordinator.cancel()
	_stop_all_crafting_audio()
	set_process(true)

func close_immediate() -> void:
	_is_open = false
	_progress = 0.0
	_target_progress = 0.0
	if crafting_coordinator != null:
		crafting_coordinator.cancel()
	_stop_all_crafting_audio()
	_update_size()
	_apply_state()
	set_process(false)

func is_open() -> bool:
	return _is_open

func get_progress() -> float:
	return _progress

func get_selected_recipe_id() -> StringName:
	return _selected_recipe_id

func select_recipe(recipe_id: StringName) -> void:
	_select_recipe(recipe_id)

func get_craft_button() -> CraftProgressButton:
	return _craft_button

func _process(delta: float) -> void:
	if _is_open and crafting_coordinator != null and crafting_coordinator.is_crafting():
		crafting_coordinator.advance_time(delta)
	if not is_equal_approx(_progress, _target_progress):
		var weight := 1.0 - exp(-3.5 / ANIM_DURATION * delta)
		_progress = lerpf(_progress, _target_progress, weight)
		if absf(_progress - _target_progress) < 0.001:
			_progress = _target_progress
		_apply_state()
	_refresh_craft_button()
	if is_equal_approx(_progress, _target_progress) and (crafting_coordinator == null or not crafting_coordinator.is_crafting()):
		set_process(false)

func _build_recipe_list() -> void:
	for child in _recipe_list.get_children():
		child.free()
	_recipe_buttons.clear()
	for recipe in recipe_catalog.definitions:
		var button := Button.new()
		button.name = String(recipe.id).to_pascal_case()
		button.custom_minimum_size = Vector2(0, 54)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_NONE
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.icon = recipe.output_item.icon
		button.expand_icon = true
		button.text = recipe.output_item.display_name
		if recipe.output_count > 1:
			button.text += "  ×%d" % recipe.output_count
		button.add_theme_font_override("font", WildesStyle.BOLD_FONT)
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", WildesStyle.make_panel(Color(0.10, 0.12, 0.14, 0.45), 8, Color(1, 1, 1, 0.10), 1))
		button.add_theme_stylebox_override("hover", WildesStyle.make_panel(Color(1, 1, 1, 0.08), 8, Color(1, 1, 1, 0.18), 1))
		button.add_theme_stylebox_override("pressed", WildesStyle.make_panel(Color(0.42, 0.58, 0.48, 0.42), 8, Color(0.72, 0.92, 0.76, 0.58), 1))
		button.pressed.connect(_select_recipe.bind(recipe.id))
		_recipe_list.add_child(button)
		_recipe_buttons[recipe.id] = button

func _select_recipe(recipe_id: StringName) -> void:
	if recipe_catalog == null or not recipe_catalog.has_definition(recipe_id):
		return
	if recipe_id != _selected_recipe_id and crafting_coordinator != null:
		crafting_coordinator.cancel()
	_selected_recipe_id = recipe_id
	for id in _recipe_buttons:
		(_recipe_buttons[id] as Button).set_pressed_no_signal(id == recipe_id)
	_refresh_details()

func _refresh_details() -> void:
	if recipe_catalog == null or _selected_recipe_id.is_empty():
		return
	var recipe := recipe_catalog.get_definition(_selected_recipe_id)
	_output_icon.texture = recipe.output_item.icon
	_output_name.text = recipe.output_item.display_name
	_output_count.text = "Creates ×%d" % recipe.output_count
	for child in _ingredient_list.get_children():
		child.free()
	for ingredient in recipe.ingredients:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 38.0
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(32, 32)
		icon.texture = ingredient.item.icon
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
	_refresh_craft_button()

func _refresh_craft_button() -> void:
	if crafting_coordinator == null or _selected_recipe_id.is_empty():
		_craft_button.set_progress(0.0)
		_craft_button.set_crafting(false)
		_craft_button.set_craft_enabled(false)
		return
	var selected_is_active := crafting_coordinator.is_crafting() and crafting_coordinator.get_active_recipe_id() == _selected_recipe_id
	_craft_button.set_progress(crafting_coordinator.get_progress() if selected_is_active else 0.0)
	_craft_button.set_crafting(selected_is_active)
	_craft_button.set_craft_enabled(crafting_coordinator.can_craft(_selected_recipe_id))

func _on_craft_pressed() -> void:
	if crafting_coordinator.start(_selected_recipe_id):
		set_process(true)
	_refresh_craft_button()

func _on_crafting_state_changed() -> void:
	_refresh_details()
	if crafting_coordinator.is_crafting():
		set_process(true)
	_sync_crafting_audio()

func _sync_crafting_audio() -> void:
	if crafting_coordinator != null and crafting_coordinator.is_crafting():
		if _crafting_impact_timer.is_stopped():
			_crafting_complete_player.stop()
			_crafting_impact_player.play()
			_crafting_impact_timer.start()
		return
	_stop_crafting_audio()

func _stop_crafting_audio() -> void:
	_crafting_impact_timer.stop()
	_crafting_impact_player.stop()

func _on_crafting_impact_timeout() -> void:
	if not _is_open or crafting_coordinator == null or not crafting_coordinator.is_crafting():
		_stop_crafting_audio()
		return
	_crafting_impact_player.play()

func _on_craft_completed(_recipe_id: StringName) -> void:
	if _is_open:
		_crafting_complete_player.play()

func _stop_all_crafting_audio() -> void:
	_stop_crafting_audio()
	_crafting_complete_player.stop()

func _exit_tree() -> void:
	if _crafting_impact_timer != null:
		_crafting_impact_timer.stop()
	if _crafting_impact_player != null:
		_crafting_impact_player.stop()
		_crafting_impact_player.stream = null
	if _crafting_complete_player != null:
		_crafting_complete_player.stop()
		_crafting_complete_player.stream = null
	_crafting_impact_stream = null
	_crafting_complete_stream = null

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
	_update_camera()

func _update_camera() -> void:
	if camera_rig != null:
		camera_rig.set_left_panel_obstruction_progress(_progress)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_update_size()
		_apply_state()
