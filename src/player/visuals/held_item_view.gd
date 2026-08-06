extends Node3D
class_name HeldItemView

@export var attack_position_offset: Vector3
@export var attack_rotation_degrees: Vector3

var inventory_model: InventoryModel
var held_node: Node3D
var _displayed_item_id: StringName
var _has_refreshed: bool = false
var _rest_position: Vector3
var _rest_rotation: Vector3
var _previewing_item: bool = false

func _ready():
	_rest_position = position
	_rest_rotation = rotation

func setup(p_inventory_model: InventoryModel):
	inventory_model = p_inventory_model
	inventory_model.inventory_changed.connect(_refresh)
	_refresh()

func set_attack_pose(weight: float, attack_arm_pitch: float):
	var pose_weight: float = clampf(weight, 0.0, 1.0)
	position = _rest_position + attack_position_offset * pose_weight
	rotation = _rest_rotation + Vector3(
		deg_to_rad(attack_rotation_degrees.x),
		deg_to_rad(attack_rotation_degrees.y),
		deg_to_rad(attack_rotation_degrees.z)
	) * pose_weight
	if pose_weight > 0.0:
		rotation.x -= attack_arm_pitch

func show_preview_item(definition: ItemDefinition):
	assert(definition.held_scene != null)
	_previewing_item = true
	_replace_held_scene(definition.held_scene)

func clear_preview_item():
	_previewing_item = false
	_has_refreshed = false
	_refresh()

func _refresh():
	if _previewing_item:
		return
	var selected_item_id = inventory_model.get_selected_item_id()
	if _has_refreshed and selected_item_id == _displayed_item_id:
		return
	_has_refreshed = true
	_displayed_item_id = selected_item_id if selected_item_id != null else &""
	var held_scene: PackedScene = null
	if selected_item_id != null:
		held_scene = inventory_model.item_catalog.get_definition(selected_item_id).held_scene
	_replace_held_scene(held_scene)

func _replace_held_scene(scene: PackedScene):
	if held_node != null:
		held_node.free()
		held_node = null
	if scene == null:
		return
	held_node = scene.instantiate() as Node3D
	add_child(held_node)
