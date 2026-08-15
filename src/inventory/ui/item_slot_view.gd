extends Panel
class_name ItemSlotView

signal selection_requested(slot_index: int)

var slot_index: int = 0
var item_texture: Texture2D = null
var item_count: int = 0
var is_selected: bool = false
var _count_visible: bool = true
var _shortcut_text: String = ""
var _normal_style: StyleBox = null
var _selected_style: StyleBox = null
var _left_click_candidate: bool = false

@onready var icon: TextureRect = $Icon as TextureRect
@onready var count_label: Label = $Count as Label
@onready var key_label: Label = get_node_or_null("Key") as Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	set_process_input(false)
	_update_shortcut_text()
	refresh_visuals()

func set_slot_index(index: int) -> void:
	slot_index = index

func set_selection_styles(normal_style: StyleBox, selected_style: StyleBox) -> void:
	_normal_style = normal_style
	_selected_style = selected_style
	if is_node_ready():
		refresh_visuals()

func present(texture: Texture2D, count: int = 0, show_count: bool = true) -> void:
	item_texture = texture
	item_count = count
	_count_visible = show_count
	if is_node_ready():
		refresh_visuals()

func clear() -> void:
	present(null, 0, _count_visible)

func set_selected(selected: bool) -> void:
	if is_selected == selected:
		return
	is_selected = selected
	if is_node_ready():
		refresh_visuals()

func set_shortcut_text(text: String) -> void:
	_shortcut_text = text
	if is_node_ready():
		_update_shortcut_text()

func request_selection() -> void:
	selection_requested.emit(slot_index)

func refresh_visuals() -> void:
	var style := _selected_style if is_selected else _normal_style
	if style != null:
		add_theme_stylebox_override("panel", style)
	_refresh_item_visuals()

func _refresh_item_visuals() -> void:
	icon.texture = item_texture
	count_label.text = str(item_count) if item_texture != null and _count_visible and item_count > 1 else ""

func _update_shortcut_text() -> void:
	if key_label != null:
		key_label.text = _shortcut_text

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if mouse_event.pressed:
		_left_click_candidate = true
	elif _left_click_candidate:
		_left_click_candidate = false
		request_selection()
		get_viewport().set_input_as_handled()
