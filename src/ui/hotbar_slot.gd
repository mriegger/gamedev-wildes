extends Panel
class_name HotbarSlot

## HotbarSlot - defines one reusable slot's icon, count, key label, and selected state
## Used by Hotbar (9 instances) inside HUD

@onready var icon: ColorRect = get_node_or_null("Color") as ColorRect
@onready var count_label: Label = get_node_or_null("Count") as Label
@onready var key_label: Label = get_node_or_null("Key") as Label

var slot_index: int = 0
var item_type = null # int legacy BlockType or BlockId.Type, null = empty
var item_count: int = 0
var is_selected: bool = false

var catalog: BlockCatalog = BlockCatalog.shared()

# Styles for selected vs normal
var _normal_style: StyleBoxFlat
var _selected_style: StyleBoxFlat


func _ready():
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
			add_child(icon)
	if count_label == null:
		count_label = get_node_or_null("Count") as Label
		if count_label == null:
			count_label = Label.new()
			count_label.name = "Count"
			count_label.position = Vector2(4, 40)
			count_label.size = Vector2(56, 18)
			count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			count_label.add_theme_font_size_override("font_size", 14)
			add_child(count_label)
	if key_label == null:
		key_label = get_node_or_null("Key") as Label
		if key_label == null:
			key_label = Label.new()
			key_label.name = "Key"
			key_label.position = Vector2(2, 2)
			key_label.add_theme_font_size_override("font_size", 10)
			key_label.modulate = Color(0.7, 0.7, 0.7, 0.8)
			add_child(key_label)


func _ensure_styles():
	if get_theme_stylebox("panel") is StyleBoxFlat:
		# reuse existing as normal base
		var cur = get_theme_stylebox("panel") as StyleBoxFlat
		_normal_style = cur.duplicate() as StyleBoxFlat
	else:
		_normal_style = StyleBoxFlat.new()
		_normal_style.bg_color = Color(0.14, 0.16, 0.18, 0.38)
		_normal_style.corner_radius_top_left = 8
		_normal_style.corner_radius_top_right = 8
		_normal_style.corner_radius_bottom_left = 8
		_normal_style.corner_radius_bottom_right = 8
		_normal_style.border_width_left = 1
		_normal_style.border_width_right = 1
		_normal_style.border_width_top = 1
		_normal_style.border_width_bottom = 1
		_normal_style.border_color = Color(1, 1, 1, 0.18)

	_selected_style = _normal_style.duplicate() as StyleBoxFlat
	_selected_style.border_color = Color(1, 1, 0.55, 0.85)
	_selected_style.bg_color = Color(0.20, 0.20, 0.16, 0.48)
	_selected_style.border_width_left = 2
	_selected_style.border_width_right = 2
	_selected_style.border_width_top = 2
	_selected_style.border_width_bottom = 2

	if not has_theme_stylebox_override("panel"):
		add_theme_stylebox_override("panel", _normal_style)


func set_slot_index(idx: int):
	slot_index = idx
	set_key(idx + 1)

func set_key(num: int):
	if key_label:
		key_label.text = str(num)
	else:
		# deferred
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

func get_item():
	return {"type": item_type, "count": item_count} if item_type != null else null

func pop_anim():
	if not is_inside_tree():
		return
	pivot_offset = size * 0.5
	var tween = get_tree().create_tween()
	tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	refresh_visuals()
