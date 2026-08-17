extends Control
class_name HotbarView

signal slot_selection_requested(slot_index: int)

@export var slot_scene: PackedScene
@export_range(1, 9) var slot_count: int = 9

var slot_nodes: Array[ItemSlotView] = []
var selected_slot: int = 0
var _selection_input_enabled: bool = true
var _slot_normal_style: StyleBoxFlat
var _slot_selected_style: StyleBoxFlat

@onready var hbox: HBoxContainer = $MarginContainer/HBoxContainer as HBoxContainer

func _ready() -> void:
	_slot_normal_style = WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.38), 8, Color(1, 1, 1, 0.18), 1)
	_slot_selected_style = WildesStyle.make_panel(Color(0.20, 0.20, 0.16, 0.48), 8, Color(1, 1, 0.55, 0.85), 2)
	_build_slots()

func present_slot(slot_index: int, texture: Texture2D, count: int = 0, show_count: bool = true) -> void:
	slot_nodes[slot_index].present(texture, count, show_count)

func clear_slot(slot_index: int) -> void:
	slot_nodes[slot_index].clear()

func set_selected_slot(slot_index: int) -> void:
	selected_slot = slot_index
	for index in range(slot_nodes.size()):
		slot_nodes[index].set_selected(index == selected_slot)

func set_selection_input_enabled(enabled: bool) -> void:
	_selection_input_enabled = enabled

func _build_slots() -> void:
	for index in range(slot_count):
		var slot := slot_scene.instantiate() as ItemSlotView
		assert(slot != null)
		slot.name = "Slot_%d" % index
		slot.set_slot_index(index)
		slot.set_shortcut_text(str(index + 1))
		slot.set_selection_styles(_slot_normal_style, _slot_selected_style)
		slot.selection_requested.connect(_on_slot_selection_requested)
		hbox.add_child(slot)
		slot_nodes.append(slot)
	set_selected_slot(selected_slot)

func _on_slot_selection_requested(slot_index: int) -> void:
	if not _selection_input_enabled:
		return
	slot_selection_requested.emit(slot_index)

func _unhandled_key_input(event: InputEvent) -> void:
	if not _selection_input_enabled or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	var slot_index := _get_slot_index(key_event)
	if slot_index < 0 or slot_index >= slot_nodes.size():
		return
	slot_selection_requested.emit(slot_index)
	get_viewport().set_input_as_handled()

func _get_slot_index(event: InputEventKey) -> int:
	var number_key := event.keycode
	if number_key < KEY_1 or number_key > KEY_9:
		number_key = event.physical_keycode
	if number_key < KEY_1 or number_key > KEY_9:
		return -1
	return number_key - KEY_1
