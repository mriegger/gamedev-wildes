extends Control
class_name ChestPanel

@export var slot_scene: PackedScene

@onready var _panel: Panel = $Center/Panel
@onready var _chest_grid: GridContainer = $Center/Panel/Margin/Content/ChestGrid
@onready var _move_all_button: Button = $Center/Panel/Margin/Content/ActionRow/MoveAllButton
@onready var _move_all_label: Label = $Center/Panel/Margin/Content/ActionRow/MoveAllButton/Content/Text

var coordinator: ChestTransferCoordinator
var player_inventory: InventoryModel
var item_proficiency: ItemProficiency
var _chest_slots: Array[InventorySlot] = []
var _slot_normal_style: StyleBoxFlat
var _slot_empty_style: StyleBoxFlat

func _ready():
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_normal_style = WildesStyle.make_panel(Color(0.16, 0.18, 0.20, 0.72), 6, Color(1, 1, 1, 0.18), 1)
	_slot_empty_style = WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.48), 6, Color(1, 1, 1, 0.12), 1)
	_setup_move_all_button()
	get_viewport().size_changed.connect(_update_layout)
	_move_all_button.pressed.connect(_on_move_all_pressed)
	_move_all_button.disabled = true
	_update_layout()

func _setup_move_all_button():
	_move_all_button.add_theme_stylebox_override("normal", WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.92), 10, Color(1, 1, 1, 0.20), 1))
	_move_all_button.add_theme_stylebox_override("hover", WildesStyle.make_panel(Color(1, 1, 1, 0.08), 10, Color(1, 1, 1, 0.16), 1))
	_move_all_button.add_theme_stylebox_override("pressed", WildesStyle.make_panel(Color(0, 0, 0, 0.12), 10, Color(1, 1, 1, 0.18), 1))
	_move_all_button.add_theme_stylebox_override("focus", WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.92), 10, Color(1, 1, 1, 0.20), 1))
	_move_all_button.add_theme_stylebox_override("disabled", WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.48), 10, Color(1, 1, 1, 0.08), 1))

func setup(p_player_inventory: InventoryModel, p_item_proficiency: ItemProficiency) -> bool:
	assert(p_player_inventory != null and p_item_proficiency != null)
	if player_inventory != null or item_proficiency != null:
		return false
	player_inventory = p_player_inventory
	item_proficiency = p_item_proficiency
	player_inventory.inventory_changed.connect(_refresh_move_all_state)
	return true

func bind(p_coordinator: ChestTransferCoordinator) -> bool:
	if (
		p_coordinator == null
		or coordinator != null
		or player_inventory == null
		or item_proficiency == null
		or p_coordinator.is_open()
	):
		return false
	coordinator = p_coordinator
	coordinator.opened.connect(_on_opened)
	coordinator.closed.connect(_on_closed)
	coordinator.contents_changed.connect(_on_contents_changed)
	return true

func release() -> void:
	if coordinator == null:
		return
	if coordinator.opened.is_connected(_on_opened):
		coordinator.opened.disconnect(_on_opened)
	if coordinator.closed.is_connected(_on_closed):
		coordinator.closed.disconnect(_on_closed)
	if coordinator.contents_changed.is_connected(_on_contents_changed):
		coordinator.contents_changed.disconnect(_on_contents_changed)
	for slot in _chest_slots:
		slot.set_inventory_transfer_context(null, &"")
	coordinator = null

func _build_chest_slots(definition: ContainerBlockDefinition):
	for slot in _chest_slots:
		slot.queue_free()
	_chest_slots.clear()
	_chest_grid.columns = definition.columns
	for index in range(definition.get_slot_count()):
		var slot := _create_slot(index, ChestTransferCoordinator.CHEST_SCOPE)
		_chest_grid.add_child(slot)
		_chest_slots.append(slot)

func _create_slot(index: int, scope: StringName) -> InventorySlot:
	var slot := slot_scene.instantiate() as InventorySlot
	assert(slot != null)
	slot.name = "%sSlot_%d" % [scope, index]
	slot.set_slot_index(index)
	slot.set_inventory(player_inventory)
	slot.set_item_proficiency(item_proficiency)
	slot.set_inventory_styles(_slot_normal_style, _slot_empty_style)
	slot.set_inventory_transfer_context(coordinator, scope)
	return slot

func _on_opened(_position: Vector3i, definition: ContainerBlockDefinition):
	_build_chest_slots(definition)
	visible = true
	_update_layout()
	_refresh()

func _on_closed():
	visible = false
	_move_all_button.disabled = true
	_move_all_label.text = "Take all"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cancel_drag_if_needed()
	release()

func _on_contents_changed(position: Vector3i) -> void:
	if coordinator != null and coordinator.get_active_position() == position:
		_refresh()

func _refresh():
	if not visible or coordinator == null:
		return
	for slot in _chest_slots:
		_refresh_slot(slot, ChestTransferCoordinator.CHEST_SCOPE)
	_refresh_move_all_state()

func _refresh_move_all_state():
	_move_all_button.disabled = not visible or coordinator == null or not coordinator.has_items_to_take()
	_move_all_label.text = "Claim Reward" if coordinator != null and coordinator.is_active_one_time_reward() else "Take all"

func _on_move_all_pressed():
	if coordinator != null:
		coordinator.move_all_to_backpack()

func _refresh_slot(slot: InventorySlot, scope: StringName):
	var stack := coordinator.get_inventory_stack(scope, slot.slot_index)
	if stack == null:
		slot.set_item(null, 0)
	else:
		slot.set_item(stack.item_id, stack.count)

func close():
	if coordinator != null:
		if coordinator.is_open():
			coordinator.close()
		else:
			release()

func close_immediate():
	close()

func is_open() -> bool:
	return visible

func get_chest_slots() -> Array[InventorySlot]:
	return _chest_slots

func _cancel_drag_if_needed():
	var viewport := get_viewport()
	if viewport != null and viewport.gui_is_dragging():
		viewport.gui_cancel_drag()

func _update_layout():
	if _panel == null:
		return
	_update_layout_for_size(get_viewport().get_visible_rect().size)

func _update_layout_for_size(viewport_size: Vector2):
	var panel_size := _panel.size
	var available_width := maxf(1.0, viewport_size.x - SidePanel.PANEL_WIDTH)
	var scale_factor := minf(1.0, minf(available_width / panel_size.x, viewport_size.y / panel_size.y))
	_panel.scale = Vector2.ONE * scale_factor
	_panel.position = Vector2(
		maxf(0.0, (available_width - panel_size.x * scale_factor) * 0.5),
		maxf(0.0, (viewport_size.y - panel_size.y * scale_factor) * 0.5),
	)
