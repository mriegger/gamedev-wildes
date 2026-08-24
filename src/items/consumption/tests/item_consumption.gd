extends SceneTree

var _errors: Array[String] = []
var _consumed_item_ids: Array[StringName] = []
var _station_open_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(item_catalog.validate(block_catalog), "item catalog rejected consumption content")
	var pumpkin := item_catalog.get_definition(&"pumpkin")
	var apple := item_catalog.get_definition(&"apple")
	var apple_seeds := item_catalog.get_definition(&"apple_seeds")
	var health_potion := item_catalog.get_definition(&"health_potion")
	var pumpkin_action := pumpkin.secondary_action as ConsumableActionDefinition
	var apple_action := apple.secondary_action as ConsumableActionDefinition
	var potion_action := health_potion.secondary_action as ConsumableActionDefinition
	_expect(pumpkin_action != null and is_equal_approx(pumpkin_action.health_restore_fraction, 0.1), "pumpkin does not restore ten percent health")
	_expect(apple_action != null and is_equal_approx(apple_action.health_restore_fraction, 0.1), "apple does not restore ten percent health")
	_expect(apple_action != null and apple_action.can_consume_at_full_health, "apple cannot be consumed at full health")
	_expect(apple_action != null and apple_action.output_item_id == apple_seeds.id and apple_action.output_count == 1, "apple does not return one apple seed")
	_expect(apple_seeds.secondary_action is PlantingActionDefinition and (apple_seeds.secondary_action as PlantingActionDefinition).crop_id == &"apple_tree", "apple seeds do not expose apple-tree planting")
	_expect(potion_action != null and is_equal_approx(potion_action.health_restore_fraction, 1.0), "health potion is not a full-health consumable")
	var highlight_color := CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)
	_expect(ItemStatFormatter.get_item_stat_lines(pumpkin) == ["Health: [b][color=#%s]+10[/color][/b]" % highlight_color], "pumpkin health stat is incorrect")
	_expect(ItemStatFormatter.get_item_stat_lines(apple) == ["Health: [b][color=#%s]+10[/color][/b]" % highlight_color], "apple health stat is incorrect")
	_expect(ItemStatFormatter.get_item_stat_lines(health_potion) == ["Health: [b][color=#%s]+100[/color][/b]" % highlight_color], "health potion stat is incorrect")
	_expect(pumpkin.consume_audio != null and pumpkin.consume_audio.streams.size() == 1, "pumpkin munch audio is not configured")
	_expect(pumpkin.consume_audio.streams[0].resource_path == "res://assets/audio/sfx/items/consume/munch_crunchy_fruit_sequence_3x_CC0.wav", "pumpkin uses the wrong consume sound")
	_expect(health_potion.consume_audio != null and health_potion.consume_audio.streams.size() == 1, "health potion consume audio is not configured")
	var full_health_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(full_health_inventory.setup_empty(), "full-health apple inventory setup failed")
	_expect(InventoryTestFixture.restore_slots(full_health_inventory, {0: InventoryStack.new(&"apple", 1)}), "full-health apple inventory could not restore")
	var full_health_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var full_health_loadout := InventoryTestFixture.create_loadout(full_health_inventory, full_health_stats)
	var full_health_consumption := ItemConsumptionCoordinator.new()
	full_health_consumption.setup(full_health_inventory, full_health_loadout, full_health_stats)
	_expect(full_health_consumption.try_consume_at(0), "apple could not be consumed at full health")
	_expect(full_health_inventory.get_inventory_item_count(&"apple") == 0 and full_health_inventory.get_inventory_item_count(&"apple_seeds") == 1, "full-health apple consumption did not return one seed")
	var full_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog), InventoryModel.FILLABLE_SIZE)
	_expect(full_inventory.setup_empty(), "full apple-output inventory setup failed")
	var full_slots: Dictionary = {0: InventoryStack.new(&"apple", 2)}
	for slot_index in range(1, InventoryModel.FILLABLE_SIZE):
		full_slots[slot_index] = InventoryStack.new(&"grass_block", item_catalog.get_definition(&"grass_block").max_stack)
	_expect(InventoryTestFixture.restore_slots(full_inventory, full_slots), "full apple-output inventory could not restore")
	var full_inventory_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var full_inventory_loadout := InventoryTestFixture.create_loadout(full_inventory, full_inventory_stats)
	var blocked_consumption := ItemConsumptionCoordinator.new()
	blocked_consumption.setup(full_inventory, full_inventory_loadout, full_inventory_stats)
	_expect(not blocked_consumption.try_consume_at(0), "apple consumption succeeded without room for its seed")
	_expect(full_inventory.get_inventory_item_count(&"apple") == 2 and full_inventory.get_inventory_item_count(&"apple_seeds") == 0, "failed apple-seed output changed inventory")

	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	var backpack_index := InventoryModel.HOTBAR_SIZE
	var defeated_potion_index := 3
	_expect(inventory.setup_empty(), "test inventory setup failed")
	_expect(
		InventoryTestFixture.restore_slots(
			inventory,
			{
				0: InventoryStack.new(&"pumpkin", 2),
				1: InventoryStack.new(&"apple", 1),
				2: InventoryStack.new(&"health_potion", 1),
				defeated_potion_index: InventoryStack.new(&"health_potion", 1),
				backpack_index: InventoryStack.new(&"health_potion", 1),
			},
		),
		"test inventory contents could not be restored",
	)
	var consumable_slot := (load("res://inventory/ui/inventory_slot.tscn") as PackedScene).instantiate() as InventorySlot
	root.add_child(consumable_slot)
	consumable_slot.set_inventory(inventory)
	consumable_slot.set_item_proficiency(ItemProficiency.new(item_catalog))
	consumable_slot.set_slot_index(0)
	consumable_slot.set_item(&"pumpkin", 2)
	var consumable_tooltip := consumable_slot._make_custom_tooltip(consumable_slot.tooltip_text) as ItemTooltip
	_expect(consumable_tooltip != null, "pumpkin did not expose its health stat tooltip")
	if consumable_tooltip != null:
		root.add_child(consumable_tooltip)
		_expect(not consumable_tooltip.rarity_label.visible, "ordinary consumable tooltip showed a rarity")
		_expect(not consumable_tooltip.proficiency_level_label.visible and not consumable_tooltip.proficiency_experience_label.visible, "ordinary consumable tooltip showed proficiency")
		_expect(consumable_tooltip.stats_label.get_parsed_text() == "Health: +10", "pumpkin tooltip health stat is incorrect")
		_expect(consumable_tooltip.get_combined_minimum_size().y < 200.0, "pumpkin tooltip expanded beyond its content")
		consumable_tooltip.free()
	consumable_slot.free()
	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var inventory_loadout := InventoryTestFixture.create_loadout(inventory, stats)
	_expect(inventory_loadout != null, "inventory loadout setup failed")
	var max_health := stats.get_value(&"hp")
	var consumption := ItemConsumptionCoordinator.new()
	consumption.setup(inventory, inventory_loadout, stats)
	consumption.item_consumed.connect(_on_item_consumed)
	var input_buffer := InputBuffer.new()
	var interactor := PlayerInteractor.new()
	interactor.inventory_model = inventory
	interactor.inventory_loadout = inventory_loadout
	interactor._input_buffer = input_buffer
	interactor.item_consumption = consumption
	interactor.unarmed_primary_action = load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var voxel_world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var mine_target := Vector3i(2, 20, 2)
	voxel_world.restore_block_edits({mine_target: BlockId.Type.STONE}, {})
	interactor.voxel_space = voxel_world
	interactor.editable_voxel_world = voxel_world
	interactor.target_block = mine_target
	interactor.target_has = true
	interactor.can_primary_target = true
	interactor.can_interact_target = true
	interactor.target_crafting_station = block_catalog.get_definition(BlockId.Type.ANVIL).crafting_station
	interactor.crafting_station_open_requested.connect(_on_station_open_requested)
	_expect(not consumption.can_consume_selected(), "full-health player could consume a pumpkin")
	_expect(not consumption.try_consume_selected(), "full-health consumption succeeded")
	_expect(inventory.get_slot(0).count == 2, "full-health consumption removed a pumpkin")
	input_buffer.primary_use_just = true
	input_buffer.primary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(inventory.get_slot(0).count == 2, "full-health left-click removed a pumpkin")
	_expect(_station_open_count == 1, "selected consumable did not prioritize the targeted crafting station")
	input_buffer.primary_use_pressed = false
	interactor._handle_item_actions(0.0)
	interactor.target_has = false
	interactor.can_interact_target = false
	interactor.target_crafting_station = null
	_expect(inventory_loadout.toggle_last_equipped_item(), "pumpkin could not be unequipped")
	stats.damage(75.0)
	input_buffer.primary_use_just = true
	input_buffer.primary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.25) and inventory.get_slot(0).count == 2, "unequipped pumpkin responded to primary use")
	input_buffer.primary_use_pressed = false
	interactor._handle_item_actions(0.0)
	_expect(inventory_loadout.toggle_last_equipped_item(), "pumpkin could not be re-equipped")

	input_buffer.primary_use_just = true
	input_buffer.primary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.35), "pumpkin did not restore ten percent health")
	_expect(inventory.get_slot(0).count == 1, "pumpkin consumption did not remove exactly one item")
	_expect(_consumed_item_ids == [&"pumpkin"], "pumpkin consumption did not announce one completed action")
	_expect(_station_open_count == 1, "consumable without an interaction target changed the station request count")
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.35), "held left-click repeatedly consumed pumpkins")
	_expect(inventory.get_slot(0).count == 1, "held left-click removed another pumpkin")

	input_buffer.primary_use_pressed = false
	interactor._handle_item_actions(0.0)
	input_buffer.primary_use_just = true
	input_buffer.primary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.45), "second pumpkin did not restore ten percent health")
	_expect(inventory.get_slot(0) == null, "last consumed pumpkin left an empty stack")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin"], "second consumption did not announce completion")
	interactor._handle_item_actions(0.0)
	_expect(not interactor.is_mining, "held left-click started mining after consuming the last item")
	input_buffer.primary_use_pressed = false
	interactor._handle_item_actions(0.0)
	_expect(inventory_loadout.select_slot(1), "apple selection failed")
	input_buffer.primary_use_just = true
	input_buffer.primary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health * 0.55), "apple did not restore ten percent health")
	_expect(inventory.get_slot(1) == null, "consumed apple left an empty stack")
	_expect(inventory.get_inventory_item_count(&"apple_seeds") == 1, "apple consumption did not add one seed")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin", &"apple"], "apple consumption did not announce completion")
	input_buffer.primary_use_pressed = false
	interactor._handle_item_actions(0.0)
	_expect(inventory_loadout.select_slot(2), "health potion selection failed")
	input_buffer.primary_use_just = true
	input_buffer.primary_use_pressed = true
	interactor._handle_item_actions(0.0)
	_expect(is_equal_approx(stats.current_hp, max_health), "selected health potion left-click did not restore full health")
	_expect(inventory.get_slot(2) == null, "selected health potion left-click did not consume one item")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin", &"apple", &"health_potion"], "selected health potion consumption did not announce completion")
	interactor.free()

	stats.damage(25.0)
	var inventory_slot := (load("res://inventory/ui/inventory_slot.tscn") as PackedScene).instantiate() as InventorySlot
	root.add_child(inventory_slot)
	inventory_slot.set_slot_index(backpack_index)
	inventory_slot.set_item_consumption(consumption)
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	inventory_slot._gui_input(right_click)
	_expect(is_equal_approx(stats.current_hp, max_health), "right-clicking a backpack health potion did not restore full health")
	_expect(inventory.get_slot(backpack_index) == null, "right-clicking a backpack health potion did not consume it")
	_expect(_consumed_item_ids == [&"pumpkin", &"pumpkin", &"apple", &"health_potion", &"health_potion"], "backpack consumption did not announce completion")
	inventory_slot.queue_free()
	await process_frame

	_expect(inventory_loadout.select_slot(defeated_potion_index), "defeated-state potion selection failed")
	stats.set_current_hp(0.0)
	_expect(not consumption.can_consume_selected(), "defeated player could consume a health potion")
	_expect(not consumption.try_consume_selected(), "defeated consumption succeeded")
	_expect(inventory.get_slot(defeated_potion_index).count == 1, "defeated consumption removed a health potion")

	if _errors.is_empty():
		print("ITEM_CONSUMPTION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _on_item_consumed(item_id: StringName) -> void:
	_consumed_item_ids.append(item_id)

func _on_station_open_requested(_position: Vector3i, _definition: CraftingStationBlockDefinition) -> void:
	_station_open_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
