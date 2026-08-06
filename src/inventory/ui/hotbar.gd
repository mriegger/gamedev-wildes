extends Control
class_name Hotbar

@export var slot_scene: PackedScene

var _inv_model: InventoryModel = null
var slot_nodes: Array[HotbarSlot] = []
var _slot_normal_style: StyleBoxFlat
var _slot_selected_style: StyleBoxFlat
var _slots_interactive: bool = false

@onready var hbox: HBoxContainer = $MarginContainer/HBoxContainer

func _ready():
	_slot_normal_style = WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.38), 8, Color(1, 1, 1, 0.18), 1)
	_slot_selected_style = WildesStyle.make_panel(Color(0.20, 0.20, 0.16, 0.48), 8, Color(1, 1, 0.55, 0.85), 2)
	_build_slots()

func setup(inv: InventoryModel):
	_inv_model = inv
	_inv_model.inventory_changed.connect(refresh)
	for slot in slot_nodes:
		slot.set_inventory(_inv_model)
	refresh()

func _build_slots():
	for i in range(InventoryModel.HOTBAR_SIZE):
		var slot_node = slot_scene.instantiate() as HotbarSlot
		slot_node.name = "Slot_%d" % i
		slot_node.set_slot_index(i)
		slot_node.set_hotbar_styles(_slot_normal_style, _slot_selected_style)
		hbox.add_child(slot_node)
		slot_nodes.append(slot_node)

func refresh():
	if _inv_model == null or slot_nodes.is_empty():
		return
	for i in range(InventoryModel.HOTBAR_SIZE):
		var data = _inv_model.get_slot(i)
		var ui = slot_nodes[i]
		if data == null:
			ui.set_item(null, 0)
		else:
			ui.set_item(data["item_id"], data["count"])
		ui.set_selected(i == _inv_model.selected_slot)

func set_slots_interactive(enabled: bool):
	if _slots_interactive == enabled:
		return
	_slots_interactive = enabled
	for slot in slot_nodes:
		slot.set_mouse_interactive(enabled)
