extends Panel

@onready var _placeholder_icon: Label = $Center/PlaceholderIcon as Label

var inventory_model: InventoryModel
var _normal_style: StyleBoxFlat
var _active_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "Drag items here to discard"
	_normal_style = WildesStyle.make_panel(Color(0.16, 0.12, 0.12, 0.72), 8, Color(0.85, 0.45, 0.42, 0.45), 1)
	_active_style = WildesStyle.make_panel(Color(0.42, 0.12, 0.10, 0.88), 8, Color(1.0, 0.62, 0.55, 0.9), 2)
	_placeholder_icon.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	_apply_drop_state(false)

func setup(p_inventory_model: InventoryModel) -> void:
	assert(p_inventory_model != null)
	inventory_model = p_inventory_model

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var parsed := _parse_drag_data(data)
	var can_discard := inventory_model != null and inventory_model.can_discard_stack(parsed.x, parsed.y)
	_apply_drop_state(can_discard)
	return can_discard

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var parsed := _parse_drag_data(data)
	if inventory_model != null:
		inventory_model.discard_stack(parsed.x, parsed.y)
	_apply_drop_state(false)

func _parse_drag_data(data: Variant) -> Vector2i:
	if not data is Dictionary or not data.has("source_index") or not data.has("drag_count"):
		return Vector2i(-1, 0)
	return Vector2i(int(data.get("source_index", -1)), int(data.get("drag_count", 0)))

func _apply_drop_state(active: bool) -> void:
	add_theme_stylebox_override("panel", _active_style if active else _normal_style)
	_placeholder_icon.modulate = Color(1.0, 0.76, 0.70) if active else Color(0.88, 0.62, 0.58)

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_node_ready():
		_apply_drop_state(false)
