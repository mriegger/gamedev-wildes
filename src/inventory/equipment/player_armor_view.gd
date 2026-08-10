extends Node
class_name PlayerArmorView

@export_node_path("Node3D") var head_attachment_path: NodePath
@export_node_path("Node3D") var torso_attachment_path: NodePath
@export_node_path("Node3D") var left_arm_attachment_path: NodePath
@export_node_path("Node3D") var right_arm_attachment_path: NodePath
@export_node_path("Node3D") var left_leg_attachment_path: NodePath
@export_node_path("Node3D") var right_leg_attachment_path: NodePath
@export_node_path("Node3D") var left_foot_attachment_path: NodePath
@export_node_path("Node3D") var right_foot_attachment_path: NodePath

var inventory_model: InventoryModel
var _attachments: Array[Node3D] = []
var _displayed_item_ids: Array[StringName] = []
var _visual_nodes_by_slot: Array = []

func _ready() -> void:
	_attachments.resize(ArmorVisualPart.Attachment.COUNT)
	_attachments[ArmorVisualPart.Attachment.HEAD] = get_node(head_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.TORSO] = get_node(torso_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.LEFT_ARM] = get_node(left_arm_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.RIGHT_ARM] = get_node(right_arm_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.LEFT_LEG] = get_node(left_leg_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.RIGHT_LEG] = get_node(right_leg_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.LEFT_FOOT] = get_node(left_foot_attachment_path) as Node3D
	_attachments[ArmorVisualPart.Attachment.RIGHT_FOOT] = get_node(right_foot_attachment_path) as Node3D
	for attachment in _attachments:
		assert(attachment != null)
	_displayed_item_ids.resize(ArmorDefinition.SLOT_COUNT)
	_displayed_item_ids.fill(&"")
	_visual_nodes_by_slot.resize(ArmorDefinition.SLOT_COUNT)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		_visual_nodes_by_slot[armor_slot] = []

func setup(p_inventory_model: InventoryModel) -> void:
	assert(p_inventory_model != null)
	assert(inventory_model == null)
	inventory_model = p_inventory_model
	inventory_model.inventory_changed.connect(_refresh)
	_refresh()

func _exit_tree() -> void:
	if _visual_nodes_by_slot.size() != ArmorDefinition.SLOT_COUNT:
		return
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		_clear_slot(armor_slot)

func get_displayed_armor_id(armor_slot: int) -> StringName:
	assert(ArmorDefinition.is_valid_slot(armor_slot))
	return _displayed_item_ids[armor_slot]

func get_visual_part_count(armor_slot: int) -> int:
	assert(ArmorDefinition.is_valid_slot(armor_slot))
	return (_visual_nodes_by_slot[armor_slot] as Array).size()

func get_visual_part_instance_id(armor_slot: int, part_index: int) -> int:
	assert(part_index >= 0 and part_index < get_visual_part_count(armor_slot))
	return (_visual_nodes_by_slot[armor_slot][part_index] as MeshInstance3D).get_instance_id()

func get_visual_part_global_transform(armor_slot: int, part_index: int) -> Transform3D:
	assert(part_index >= 0 and part_index < get_visual_part_count(armor_slot))
	return (_visual_nodes_by_slot[armor_slot][part_index] as MeshInstance3D).global_transform

func get_visual_part_local_transform(armor_slot: int, part_index: int) -> Transform3D:
	assert(part_index >= 0 and part_index < get_visual_part_count(armor_slot))
	return (_visual_nodes_by_slot[armor_slot][part_index] as MeshInstance3D).transform

func is_visual_part_attached_to(armor_slot: int, part_index: int, attachment: ArmorVisualPart.Attachment) -> bool:
	assert(attachment >= ArmorVisualPart.Attachment.HEAD and attachment < ArmorVisualPart.Attachment.COUNT)
	assert(part_index >= 0 and part_index < get_visual_part_count(armor_slot))
	return (_visual_nodes_by_slot[armor_slot][part_index] as MeshInstance3D).get_parent() == _attachments[attachment]

func _refresh() -> void:
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var armor := inventory_model.get_equipped_armor(armor_slot)
		var next_item_id: StringName = &"" if armor == null else armor.id
		if _displayed_item_ids[armor_slot] == next_item_id:
			continue
		_clear_slot(armor_slot)
		if armor != null:
			_create_visuals(armor_slot, armor)
		_displayed_item_ids[armor_slot] = next_item_id

func _clear_slot(armor_slot: int) -> void:
	var visual_nodes := _visual_nodes_by_slot[armor_slot] as Array
	for visual_node in visual_nodes:
		(visual_node as MeshInstance3D).free()
	visual_nodes.clear()

func _create_visuals(armor_slot: int, armor: ArmorDefinition) -> void:
	var visual_nodes := _visual_nodes_by_slot[armor_slot] as Array
	for part_index in range(armor.visual_parts.size()):
		var part := armor.visual_parts[part_index]
		var visual_node := MeshInstance3D.new()
		visual_node.name = "%s_%d" % [armor.id, part_index]
		visual_node.mesh = part.mesh
		visual_node.transform = part.local_transform
		_attachments[part.attachment].add_child(visual_node)
		visual_nodes.append(visual_node)
