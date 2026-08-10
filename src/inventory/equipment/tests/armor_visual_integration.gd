extends SceneTree

const ARMOR_IDS: Array[StringName] = [
	&"copper_helmet",
	&"copper_chest_plate",
	&"copper_pants",
	&"copper_shoes",
]
const VISUAL_PART_COUNTS: Array[int] = [5, 3, 2, 2]

var _errors: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var stats_definition := load("res://player/player_stats.tres") as ActorStatsDefinition
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	var stats := ActorStats.new(stats_definition)
	var coordinator := InventoryStatCoordinator.new()
	_expect(coordinator.setup(inventory, stats), "inventory stat coordinator setup failed")

	var player_visual_scene := load("res://player/visuals/player_visual.tscn") as PackedScene
	var player_visual := player_visual_scene.instantiate() as BlockyHumanoidAnimator
	root.add_child(player_visual)
	await process_frame
	var armor_view := player_visual.get_node("ArmorView") as PlayerArmorView
	armor_view.setup(inventory)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		_expect(armor_view.get_displayed_armor_id(armor_slot).is_empty(), "empty equipment displayed armor for slot %d" % armor_slot)
		_expect(armor_view.get_visual_part_count(armor_slot) == 0, "empty equipment created visuals for slot %d" % armor_slot)

	var helmet_source := _find_item(inventory, &"copper_helmet")
	_expect(coordinator.try_equip_armor(helmet_source), "helmet equip failed")
	_expect(armor_view.get_displayed_armor_id(ArmorDefinition.Slot.HELMET) == &"copper_helmet", "helmet visual ID did not synchronize")
	_expect(armor_view.get_visual_part_count(ArmorDefinition.Slot.HELMET) == VISUAL_PART_COUNTS[ArmorDefinition.Slot.HELMET], "helmet visuals were not created")
	var helmet_instance_id := armor_view.get_visual_part_instance_id(ArmorDefinition.Slot.HELMET, 0)
	_expect(inventory.select_slot(1), "unrelated inventory selection failed")
	_expect(armor_view.get_visual_part_instance_id(ArmorDefinition.Slot.HELMET, 0) == helmet_instance_id, "unrelated inventory change rebuilt helmet visuals")

	for armor_slot in range(1, ArmorDefinition.SLOT_COUNT):
		var source := _find_item(inventory, ARMOR_IDS[armor_slot])
		_expect(coordinator.try_equip_armor(source), "armor equip failed for slot %d" % armor_slot)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		_expect(armor_view.get_displayed_armor_id(armor_slot) == ARMOR_IDS[armor_slot], "full set visual ID mismatch for slot %d" % armor_slot)
		_expect(armor_view.get_visual_part_count(armor_slot) == VISUAL_PART_COUNTS[armor_slot], "full set visual count mismatch for slot %d" % armor_slot)
		var armor := item_catalog.get_definition(ARMOR_IDS[armor_slot]) as ArmorDefinition
		for part_index in range(armor.visual_parts.size()):
			var visual_part := armor.visual_parts[part_index]
			_expect(armor_view.is_visual_part_attached_to(armor_slot, part_index, visual_part.attachment), "armor visual attachment mismatch for slot %d part %d" % [armor_slot, part_index])
			_expect(armor_view.get_visual_part_local_transform(armor_slot, part_index).is_equal_approx(visual_part.local_transform), "armor visual local transform mismatch for slot %d part %d" % [armor_slot, part_index])

	var animation_state := ActorAnimationState.new()
	animation_state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	player_visual.setup(animation_state)
	var transforms_before: Array = []
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var slot_transforms: Array[Transform3D] = []
		for part_index in range(armor_view.get_visual_part_count(armor_slot)):
			slot_transforms.append(armor_view.get_visual_part_global_transform(armor_slot, part_index))
		transforms_before.append(slot_transforms)
	player_visual.advance_animation(0.18)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		for part_index in range(armor_view.get_visual_part_count(armor_slot)):
			var transform_after := armor_view.get_visual_part_global_transform(armor_slot, part_index)
			var transform_before := (transforms_before[armor_slot] as Array)[part_index] as Transform3D
			_expect(not transform_after.is_equal_approx(transform_before), "armor visual did not follow animation for slot %d part %d" % [armor_slot, part_index])

	var equipped_snapshot := inventory.to_dict()
	var restored_inventory := InventoryModel.new(item_catalog)
	_expect(restored_inventory.from_dict(equipped_snapshot), "equipped inventory restore failed")
	var restored_stats := ActorStats.new(stats_definition)
	var restored_coordinator := InventoryStatCoordinator.new()
	_expect(restored_coordinator.setup(restored_inventory, restored_stats), "restored inventory coordinator setup failed")
	var restored_player_visual := player_visual_scene.instantiate() as BlockyHumanoidAnimator
	root.add_child(restored_player_visual)
	await process_frame
	var restored_armor_view := restored_player_visual.get_node("ArmorView") as PlayerArmorView
	restored_armor_view.setup(restored_inventory)
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		_expect(restored_armor_view.get_displayed_armor_id(armor_slot) == ARMOR_IDS[armor_slot], "restored armor visual ID mismatch for slot %d" % armor_slot)
		_expect(restored_armor_view.get_visual_part_count(armor_slot) == VISUAL_PART_COUNTS[armor_slot], "restored armor visual count mismatch for slot %d" % armor_slot)

	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		var equipment_index := InventoryModel.get_equipment_index(armor_slot)
		_expect(coordinator.try_unequip_armor(equipment_index), "armor unequip failed for slot %d" % armor_slot)
		_expect(armor_view.get_displayed_armor_id(armor_slot).is_empty(), "unequipped armor visual ID remained for slot %d" % armor_slot)
		_expect(armor_view.get_visual_part_count(armor_slot) == 0, "unequipped armor visuals remained for slot %d" % armor_slot)

	player_visual.free()
	restored_player_visual.free()
	await process_frame
	_expect(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) == orphan_before, "armor visual teardown leaked orphan nodes")
	if _errors.is_empty():
		print("ARMOR_VISUAL PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _find_item(inventory: InventoryModel, item_id: StringName) -> int:
	for index in range(inventory.size):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
