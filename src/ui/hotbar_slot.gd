extends Panel
class_name HotbarSlot

@onready var icon: ColorRect = get_node_or_null("Color") as ColorRect
@onready var count_label: Label = get_node_or_null("Count") as Label
@onready var key_label: Label = get_node_or_null("Key") as Label

var slot_index: int = 0
var item_type = null
var item_count: int = 0
var is_selected: bool = false

var catalog: BlockCatalog = BlockCatalog.shared()

var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_ensure_nodes()
	_ensure_styles()
	set_key(slot_index + 1)
	refresh_visuals()

func _ensure_nodes():
	if icon == null:
		icon = get_node_or_null("Color") as ColorRect
		if icon == null:
			icon = ColorRect.new()
			icon.name = "Color"
			icon.custom_minimum_size = Vector2(36, 36)
			icon.position = Vector2(14, 8)
			icon.size = Vector2(36, 36)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(icon)
		else:
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if count_label == null:
		count_label = get_node_or_null("Count") as Label
		if count_label == null:
			count_label = Label.new()
			count_label.name = "Count"
			count_label.position = Vector2(4, 40)
			count_label.size = Vector2(56, 18)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_label.add_theme_font_size_override("font_size", 14)
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(count_label)
		else:
			count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if key_label == null:
		key_label = get_node_or_null("Key") as Label
		if key_label == null:
			key_label = Label.new()
			key_label.name = "Key"
			key_label.position = Vector2(2, 2)
			key_label.add_theme_font_size_override("font_size", 10)
			key_label.modulate = Color(0.7, 0.7, 0.7, 0.8)
			key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(key_label)
		else:
			key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ensure_styles():
	if _normal_style != null and _selected_style != null:
		return
	# Always fresh via factory - never get_theme_stylebox and mutate shared theme resource
	_normal_style = WildesStyle.make_panel_alpha(Color(0.14, 0.16, 0.18, 0.38), 8, 0.18, 1)
	_selected_style = WildesStyle.make_panel(Color(0.20, 0.20, 0.16, 0.48), 8, Color(1, 1, 0.55, 0.85), 2)

	if not has_theme_stylebox_override("panel"):
		add_theme_stylebox_override("panel", _normal_style)

func set_slot_index(idx: int):
	slot_index = idx
	set_key(idx + 1)

func set_key(num: int):
	if key_label:
		key_label.text = str(num)
	else:
		call_deferred("_deferred_set_key", num)

func _deferred_set_key(num: int):
	if key_label:
		key_label.text = str(num)

func set_item(type, count: int):
	item_type = type
	item_count = count
	refresh_visuals()

func set_selected(selected: bool):
	is_selected = selected
	refresh_visuals()

func refresh_visuals():
	_ensure_nodes()
	_ensure_styles()

	if is_selected:
		add_theme_stylebox_override("panel", _selected_style)
	else:
		add_theme_stylebox_override("panel", _normal_style)

	if icon == null or count_label == null:
		return

	if item_type == null or item_type == BlockId.Type.AIR:
		icon.color = Color(0, 0, 0, 0)
		count_label.text = ""
	else:
		var t = item_type
		var col = catalog.get_side_color(t) if BlockId.is_valid(t) else Color(1, 0, 1, 1)
		icon.color = col
		if item_count > 1:
			count_label.text = str(item_count)
		else:
			count_label.text = ""
		if item_count <= 0:
			count_label.text = ""
