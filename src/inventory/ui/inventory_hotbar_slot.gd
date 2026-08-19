extends InventorySlot
class_name InventoryHotbarSlot

var _backpack_open: bool = false

func _ready() -> void:
	super._ready()
	set_process(false)

func set_backpack_open(open: bool) -> void:
	_backpack_open = open
	_left_click_candidate = false

func _gui_input(event: InputEvent) -> void:
	if _try_handle_consumption_input(event):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_left_click_candidate = true
		elif _left_click_candidate:
			_left_click_candidate = false
			if get_viewport().gui_is_dragging() or inventory_model == null:
				return
			if _backpack_open:
				if inventory_loadout_coordinator != null and inventory_loadout_coordinator.move_hotbar_slot_to_backpack(slot_index):
					get_viewport().set_input_as_handled()
					return
			elif inventory_model.get_slot(slot_index) != null:
				request_selection()
				get_viewport().set_input_as_handled()
				return
	if _backpack_open:
		super._gui_input(event)

func _get_drag_data(at_position: Vector2):
	_left_click_candidate = false
	if not _backpack_open:
		return null
	return super._get_drag_data(at_position)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if not _backpack_open:
		return false
	return super._can_drop_data(at_position, data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _backpack_open:
		return
	super._drop_data(at_position, data)

func _show_high_layer_preview(type: StringName, count: int) -> void:
	super._show_high_layer_preview(type, count)
	if _drag_preview_layer:
		_drag_preview_layer.name = "HotbarDragPreview"
