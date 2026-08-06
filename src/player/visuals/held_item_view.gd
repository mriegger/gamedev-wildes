extends Node3D
class_name HeldItemView

var inventory_model: InventoryModel
var held_node: Node3D
var _displayed_item_id: StringName
var _has_refreshed: bool = false

func setup(p_inventory_model: InventoryModel):
	inventory_model = p_inventory_model
	inventory_model.inventory_changed.connect(_refresh)
	_refresh()

func _refresh():
	var selected_item_id = inventory_model.get_selected_item_id()
	if _has_refreshed and selected_item_id == _displayed_item_id:
		return
	_has_refreshed = true
	_displayed_item_id = selected_item_id if selected_item_id != null else &""
	if held_node != null:
		held_node.free()
		held_node = null
	if selected_item_id == null:
		return
	var definition := inventory_model.item_catalog.get_definition(selected_item_id)
	if definition.held_scene == null:
		return
	held_node = definition.held_scene.instantiate() as Node3D
	add_child(held_node)
