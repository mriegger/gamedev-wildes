extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(_item_catalog != null and _item_catalog.validate(block_catalog), "item catalog invalid")
	_test_shared_abstraction()
	_test_deterministic_population_and_transfers()
	_test_atomic_initialization_failure()
	_test_full_inventory_rejection()
	_finish()

func _test_shared_abstraction() -> void:
	_expect(ChestCoordinator.new() is ChestTransferCoordinator, "overworld coordinator does not implement the shared chest contract")
	_expect(DungeonChestCoordinator.new() is ChestTransferCoordinator, "dungeon coordinator does not implement the shared chest contract")

func _test_deterministic_population_and_transfers() -> void:
	var material_bundle := _bundle(
		&"dungeon_materials",
		3,
		_entries([
			_entry(&"copper", _drop(&"copper", 6, 6)),
			_entry(&"rune", _drop(&"basic_rune")),
		]),
		_choices([
			_choice(&"dirt", 2.0, _drop(&"dirt_block")),
		]),
	)
	var equipment_roll := LootEquipmentRollDefinition.new()
	equipment_roll.fixed_affixes = _affixes([_item_catalog.get_equipment_affix(&"vicious")])
	equipment_roll.fixed_runes = _runes([_item_catalog.get_definition(&"basic_rune") as RuneDefinition])
	var equipment_bundle := _bundle(
		&"dungeon_equipment",
		1,
		_entries([_entry(&"sword", _drop(&"copper_sword", 1, 1, equipment_roll))]),
		[],
	)
	var material_cell := Vector3i(14, 3, -8)
	var equipment_cell := Vector3i(-4, 7, 19)
	var placements := _placements([
		LevelChestPlacement.new(9, equipment_cell, equipment_bundle),
		LevelChestPlacement.new(2, material_cell, material_bundle),
	])
	var reordered := _placements([
		LevelChestPlacement.new(2, material_cell, material_bundle),
		LevelChestPlacement.new(9, equipment_cell, equipment_bundle),
	])
	var container := _container(2, 3)
	var first_inventory := _inventory()
	_expect(
		InventoryTestFixture.restore_slot(first_inventory, 0, InventoryStack.new(&"torch", 4)),
		"hotbar transfer fixture failed",
	)
	_expect(
		InventoryTestFixture.restore_slot(first_inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"log_block", 3)),
		"backpack transfer fixture failed",
	)
	var first_loadout := InventoryTestFixture.create_loadout(first_inventory)
	var second_inventory := _inventory()
	var second_loadout := InventoryTestFixture.create_loadout(second_inventory)
	var first := DungeonChestCoordinator.new()
	var second := DungeonChestCoordinator.new()
	_expect(first.setup(placements, 41725, first_inventory, first_loadout, container), "first dungeon chest setup failed")
	_expect(second.setup(reordered, 41725, second_inventory, second_loadout, container), "reordered dungeon chest setup failed")
	_expect(first_inventory.equipment_instance_factory.get_next_instance_id() == 2, "all-chest setup allocated the wrong equipment ID count")
	_expect(second_inventory.equipment_instance_factory.get_next_instance_id() == 2, "reordered setup allocated a different equipment ID count")
	_expect(
		_encode_chests(first, [material_cell, equipment_cell], container)
		== _encode_chests(second, [material_cell, equipment_cell], container),
		"placement order changed deterministic chest contents",
	)
	_expect(first.try_open(material_cell, container), "material chest did not open")
	var copper_slot := _find_slot(first, &"copper", container.get_slot_count())
	var rune_slot := _find_slot(first, &"basic_rune", container.get_slot_count())
	_expect(copper_slot >= 0 and rune_slot >= 0, "guaranteed material rewards were not populated")
	var material_before_rejections := _encode_open_chest(first, container.get_slot_count())
	var inventory_before_rejections := first_inventory.to_dict()
	_expect(
		not first.quick_transfer(ChestTransferCoordinator.PLAYER_SCOPE, InventoryModel.HOTBAR_SIZE),
		"player quick-deposit entered a dungeon chest",
	)
	_expect(
		not first.can_handle_drop(
			ChestTransferCoordinator.PLAYER_SCOPE,
			0,
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			1,
		),
		"player-to-chest drag was advertised as valid",
	)
	_expect(
		not first.handle_drop(
			ChestTransferCoordinator.PLAYER_SCOPE,
			0,
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			1,
		),
		"player-to-chest drag committed",
	)
	_expect(
		not first.handle_drop(
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			ChestTransferCoordinator.CHEST_SCOPE,
			rune_slot,
			1,
		),
		"chest-to-chest rearrangement committed",
	)
	_expect(_encode_open_chest(first, container.get_slot_count()) == material_before_rejections, "rejected dungeon chest transfers changed chest state")
	_expect(first_inventory.to_dict() == inventory_before_rejections, "rejected dungeon chest transfers changed inventory")
	_expect(
		first.handle_drop(
			ChestTransferCoordinator.PLAYER_SCOPE,
			InventoryModel.HOTBAR_SIZE,
			ChestTransferCoordinator.PLAYER_SCOPE,
			InventoryModel.HOTBAR_SIZE + 1,
			3,
		),
		"player inventory rearrangement was rejected while a dungeon chest was open",
	)
	_expect(first_inventory.get_slot(InventoryModel.HOTBAR_SIZE) == null, "player rearrangement retained its source")
	_expect(first_inventory.get_slot(InventoryModel.HOTBAR_SIZE + 1).item_id == &"log_block", "player rearrangement moved the wrong stack")
	var copper_before := first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, copper_slot).count
	_expect(
		not first.handle_drop(
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			ChestTransferCoordinator.PLAYER_SCOPE,
			0,
			2,
		),
		"take-only chest swapped with an occupied player slot",
	)
	_expect(first_inventory.get_slot(0).item_id == &"torch", "rejected take replaced the player item")
	_expect(first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, copper_slot).count == copper_before, "rejected take changed the chest stack")
	var coherent_observations: Array[bool] = []
	var reentrant_results: Array[bool] = []
	var inventory_observer := func() -> void:
		var remaining := first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, copper_slot)
		coherent_observations.append(
			remaining != null
			and remaining.count == copper_before - 2
			and first_inventory.get_slot(1).item_id == &"copper"
			and first_inventory.get_slot(1).count == 2
		)
		reentrant_results.append(first.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, rune_slot))
	first_inventory.inventory_changed.connect(inventory_observer)
	_expect(
		first.handle_drop(
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			ChestTransferCoordinator.PLAYER_SCOPE,
			1,
			2,
		),
		"partial chest-to-player take failed",
	)
	first_inventory.inventory_changed.disconnect(inventory_observer)
	_expect(coherent_observations == [true], "inventory observer saw a partially committed dungeon take")
	_expect(reentrant_results == [false], "inventory observer reentered a dungeon chest transaction")
	_expect(first.move_all_to_backpack(), "Take All did not move remaining material rewards")
	_expect(not first.can_move_all_to_backpack(), "Take All remained available for an empty chest")
	first.close()
	_expect(first.try_open(equipment_cell, container), "equipment chest did not open")
	var sword_slot := _find_slot(first, &"copper_sword", container.get_slot_count())
	_expect(sword_slot >= 0, "equipment reward was not populated")
	var sword := first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, sword_slot)
	_expect(sword != null and sword.equipment_instance != null, "equipment reward has no variant instance")
	if sword != null and sword.equipment_instance != null:
		_expect(sword.equipment_instance.instance_id == 1, "equipment reward received an unstable instance ID")
		_expect(sword.equipment_instance.affixes[0].affix_id == &"vicious", "equipment affix changed during population")
		_expect(sword.equipment_instance.socketed_rune_ids == _ids([&"basic_rune"]), "equipment rune changed during population")
		var fingerprint := sword.to_dict()
		_expect(first.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, sword_slot), "equipment quick-take failed")
		var moved_sword := _find_inventory_stack(first_inventory, &"copper_sword")
		_expect(moved_sword != null and moved_sword.to_dict() == fingerprint, "equipment variant changed during chest transfer")

func _test_atomic_initialization_failure() -> void:
	var equipment_bundle := _bundle(
		&"atomic_equipment",
		1,
		_entries([_entry(&"sword", _drop(&"copper_sword"))]),
		[],
	)
	var shared_cell := Vector3i(3, 5, 7)
	var duplicate_placements := _placements([
		LevelChestPlacement.new(1, shared_cell, equipment_bundle),
		LevelChestPlacement.new(2, shared_cell, equipment_bundle),
	])
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var inventory_before := inventory.to_dict()
	var revision_before := inventory.get_revision()
	var allocator_before := inventory.equipment_instance_factory.get_next_instance_id()
	var coordinator := DungeonChestCoordinator.new()
	var container := _container(1, 2)
	_expect(
		not coordinator.setup(duplicate_placements, 92, inventory, loadout, container),
		"duplicate chest placement initialized partially",
	)
	_expect(inventory.to_dict() == inventory_before, "failed all-chest initialization changed inventory")
	_expect(inventory.get_revision() == revision_before, "failed all-chest initialization revised inventory")
	_expect(inventory.equipment_instance_factory.get_next_instance_id() == allocator_before, "failed all-chest initialization consumed equipment IDs")
	_expect(not coordinator.can_open(shared_cell), "failed all-chest initialization exposed candidate storage")
	var valid_placements := _placements([LevelChestPlacement.new(1, shared_cell, equipment_bundle)])
	_expect(coordinator.setup(valid_placements, 92, inventory, loadout, container), "failed initialization stranded the coordinator")
	_expect(inventory.equipment_instance_factory.get_next_instance_id() == allocator_before + 1, "successful retry did not commit the allocator once")
	_expect(coordinator.try_open(shared_cell, container), "successfully retried chest did not open")
	var sword_slot := _find_slot(coordinator, &"copper_sword", container.get_slot_count())
	_expect(sword_slot >= 0, "successfully retried chest has no equipment reward")
	if sword_slot >= 0:
		_expect(
			coordinator.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, sword_slot).equipment_instance.instance_id == allocator_before,
			"successful retry skipped the rolled-back equipment ID",
		)

func _test_full_inventory_rejection() -> void:
	var bundle := _bundle(
		&"full_inventory_reward",
		1,
		_entries([_entry(&"copper", _drop(&"copper", 3, 3))]),
		[],
	)
	var cell := Vector3i(8, 4, 2)
	var inventory := _inventory()
	for index in range(InventoryModel.FILLABLE_SIZE):
		_expect(
			InventoryTestFixture.restore_slot(
				inventory,
				index,
				InventoryStack.new(&"sand_block", _item_catalog.get_definition(&"sand_block").max_stack),
			),
			"full inventory fixture failed at %d" % index,
		)
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var coordinator := DungeonChestCoordinator.new()
	var rejection_messages: Array[String] = []
	coordinator.transfer_rejected.connect(func(message: String) -> void:
		rejection_messages.append(message)
	)
	var container := _container(1, 2)
	_expect(
		coordinator.setup(_placements([LevelChestPlacement.new(1, cell, bundle)]), 7, inventory, loadout, container),
		"full inventory dungeon chest setup failed",
	)
	_expect(coordinator.try_open(cell, container), "full inventory dungeon chest did not open")
	var slot := _find_slot(coordinator, &"copper", container.get_slot_count())
	var chest_before := _encode_open_chest(coordinator, container.get_slot_count())
	var inventory_before := inventory.to_dict()
	_expect(not coordinator.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, slot), "full inventory accepted a quick take")
	_expect(not coordinator.move_all_to_backpack(), "full inventory accepted Take All")
	_expect(
		rejection_messages == [DungeonChestCoordinator.INVENTORY_FULL_MESSAGE, DungeonChestCoordinator.INVENTORY_FULL_MESSAGE],
		"full inventory did not report that items must be dropped first",
	)
	_expect(_encode_open_chest(coordinator, container.get_slot_count()) == chest_before, "failed full-inventory take changed chest contents")
	_expect(inventory.to_dict() == inventory_before, "failed full-inventory take changed inventory")

func _inventory() -> InventoryModel:
	var inventory := InventoryModel.new(_item_catalog, EquipmentInstanceFactory.new(_item_catalog))
	var initialized := inventory.setup_empty()
	assert(initialized)
	return inventory

func _container(rows: int, columns: int) -> ContainerBlockDefinition:
	var container := ContainerBlockDefinition.new()
	container.rows = rows
	container.columns = columns
	return container

func _bundle(
	id: StringName,
	max_rewards: int,
	fixed_entries: Array[LootBundleEntryDefinition],
	weighted_candidates: Array[LootWeightedChoiceDefinition],
) -> LootBundleDefinition:
	var bundle := LootBundleDefinition.new()
	bundle.id = id
	bundle.max_rewards = max_rewards
	bundle.fixed_entries = fixed_entries
	bundle.weighted_candidates = weighted_candidates
	return bundle

func _entry(id: StringName, drop: LootDropDefinition) -> LootBundleEntryDefinition:
	var entry := LootBundleEntryDefinition.new()
	entry.id = id
	entry.drop = drop
	return entry

func _choice(id: StringName, weight: float, drop: LootDropDefinition) -> LootWeightedChoiceDefinition:
	var choice := LootWeightedChoiceDefinition.new()
	choice.id = id
	choice.weight = weight
	choice.drop = drop
	return choice

func _drop(
	item_id: StringName,
	minimum_count: int = 1,
	maximum_count: int = 1,
	equipment_roll: LootEquipmentRollDefinition = null,
) -> LootDropDefinition:
	var drop := LootDropDefinition.new()
	drop.item = _item_catalog.get_definition(item_id)
	drop.minimum_count = minimum_count
	drop.maximum_count = maximum_count
	drop.equipment_roll = equipment_roll
	return drop

func _entries(values: Array) -> Array[LootBundleEntryDefinition]:
	var entries: Array[LootBundleEntryDefinition] = []
	entries.assign(values)
	return entries

func _choices(values: Array) -> Array[LootWeightedChoiceDefinition]:
	var choices: Array[LootWeightedChoiceDefinition] = []
	choices.assign(values)
	return choices

func _placements(values: Array) -> Array[LevelChestPlacement]:
	var placements: Array[LevelChestPlacement] = []
	placements.assign(values)
	return placements

func _affixes(values: Array) -> Array[EquipmentAffixDefinition]:
	var affixes: Array[EquipmentAffixDefinition] = []
	affixes.assign(values)
	return affixes

func _runes(values: Array) -> Array[RuneDefinition]:
	var runes: Array[RuneDefinition] = []
	runes.assign(values)
	return runes

func _ids(values: Array) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(values)
	return ids

func _find_slot(coordinator: DungeonChestCoordinator, item_id: StringName, slot_count: int) -> int:
	for slot_index in range(slot_count):
		var stack := coordinator.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, slot_index)
		if stack != null and stack.item_id == item_id:
			return slot_index
	return -1

func _find_inventory_stack(inventory: InventoryModel, item_id: StringName) -> InventoryStack:
	for index in range(mini(inventory.get_size(), InventoryModel.FILLABLE_SIZE)):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return stack
	return null

func _encode_chests(
	coordinator: DungeonChestCoordinator,
	cells: Array[Vector3i],
	container: ContainerBlockDefinition,
) -> Dictionary:
	var encoded: Dictionary = {}
	for cell in cells:
		if not coordinator.try_open(cell, container):
			return {}
		encoded[cell] = _encode_open_chest(coordinator, container.get_slot_count())
		coordinator.close()
	return encoded

func _encode_open_chest(coordinator: DungeonChestCoordinator, slot_count: int) -> Array:
	var encoded: Array = []
	for slot_index in range(slot_count):
		var stack := coordinator.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, slot_index)
		encoded.append(null if stack == null else stack.to_dict())
	return encoded

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("DUNGEON_CHEST_COORDINATOR PASS")
		quit(0)
		return
	for message in _errors:
		push_error(message)
	print("DUNGEON_CHEST_COORDINATOR FAIL count=%d" % _errors.size())
	quit(1)
