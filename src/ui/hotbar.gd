extends Control
class_name Hotbar

## Hotbar - presents inventory slots, reacts to inventory model signals, no forwarders

@export var slot_scene: PackedScene

var _inv_model: InventoryModel = null
var inventory_model: InventoryModel:
	get:
		return _inv_model
	set(v):
		_inv_model = v
		_connect_inventory_signals()
		refresh()

var container: HBoxContainer
var slot_nodes: Array[HotbarSlot] = []

@onready var hbox: HBoxContainer = $MarginContainer/HBoxContainer


func _ready():
	if slot_scene == null:
		slot_scene = load("res://ui/hotbar_slot.tscn") as PackedScene
	if hbox == null:
		hbox = $MarginContainer/HBoxContainer as HBoxContainer
	_build_slots()
	_connect_inventory_signals()
	refresh()

func _build_slots():
	if hbox == null:
		return
	for c in hbox.get_children():
		c.queue_free()
	slot_nodes.clear()
	for i in range(9):
		var slot_node: HotbarSlot
		if slot_scene != null:
			var inst = slot_scene.instantiate()
			slot_node = inst as HotbarSlot if inst is HotbarSlot else HotbarSlot.new()
		else:
			slot_node = HotbarSlot.new()
		slot_node.name = "Slot_%d" % i
		slot_node.set_slot_index(i)
		hbox.add_child(slot_node)
		slot_nodes.append(slot_node)

func _connect_inventory_signals():
	if _inv_model == null:
		return
	# Only subscribe to inventory_changed per spec - Game only assigns model, Hotbar subscribes
	# Using lambda to avoid argument count mismatch (selection_changed emits 2 args)
	# Disconnect any existing to avoid double subscription
	for conn in _inv_model.inventory_changed.get_connections():
		if conn["callable"].get_object() == self:
			_inv_model.inventory_changed.disconnect(conn["callable"])
	_inv_model.inventory_changed.connect(refresh)

func refresh():
	if _inv_model == null or slot_nodes.is_empty():
		return
	for i in range(9):
		if i >= slot_nodes.size():
			continue
		var data = _inv_model.get_slot(i)
		var ui = slot_nodes[i]
		if data == null:
			ui.set_item(null, 0)
		else:
			ui.set_item(data["type"], data["count"])
		ui.set_selected(i == _inv_model.selected_slot)

func refresh_slot(idx: int):
	if _inv_model == null or idx < 0 or idx >= slot_nodes.size():
		return
	var data = _inv_model.get_slot(idx)
	var ui = slot_nodes[idx]
	if data == null:
		ui.set_item(null, 0)
	else:
		ui.set_item(data["type"], data["count"])
	ui.set_selected(idx == _inv_model.selected_slot)

func pop_slot(idx: int):
	if idx < 0 or idx >= slot_nodes.size():
		return
	slot_nodes[idx].pop_anim()
