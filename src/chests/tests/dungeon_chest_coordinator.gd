extends SceneTree

var _errors: Array[String] = []
var _item_catalog: ItemCatalog

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(_item_catalog != null and _item_catalog.validate(block_catalog), "item catalog invalid")
	_test_shared_abstraction()
	_test_deterministic_population_and_transfers()
	_test_one_time_selection_and_escrow()
	_test_one_time_capacity_and_repeat_modes()
	_test_atomic_initialization_failure()
	_test_full_inventory_rejection()
	_item_catalog = null
	call_deferred("_finish")

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
	_expect(first.setup(placements, 41725, null, false, 0, first_inventory, first_loadout, container), "first dungeon chest setup failed")
	_expect(second.setup(reordered, 41725, null, false, 0, second_inventory, second_loadout, container), "reordered dungeon chest setup failed")
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
		_expect(first.repeatable_reward_taken, "repeatable reward take was not tracked")
		var moved_sword := _find_inventory_stack(first_inventory, &"copper_sword")
		_expect(moved_sword != null and moved_sword.to_dict() == fingerprint, "equipment variant changed during chest transfer")

func _test_one_time_selection_and_escrow() -> void:
	var sand_bundle := _bundle(
		&"repeat_sand",
		1,
		_entries([_entry(&"sand", _drop(&"sand_block", 5, 5))]),
		[],
	)
	var dirt_bundle := _bundle(
		&"repeat_dirt",
		1,
		_entries([_entry(&"dirt", _drop(&"dirt_block", 6, 6))]),
		[],
	)
	var log_bundle := _bundle(
		&"repeat_log",
		1,
		_entries([_entry(&"log", _drop(&"log_block", 7, 7))]),
		[],
	)
	var one_time_bundle := _bundle(
		&"progression_bundle",
		2,
		_entries([
			_entry(&"copper", _drop(&"copper", 4, 8)),
			_entry(&"rune", _drop(&"basic_rune", 2, 2)),
		]),
		[],
	)
	var reward := LevelOneTimeChestRewardDefinition.new()
	reward.reward_id = &"basic_rune_progression"
	reward.loot_bundle = one_time_bundle
	var sand_cell := Vector3i(3, 1, 8)
	var dirt_cell := Vector3i(-7, 4, 2)
	var log_cell := Vector3i(9, 2, -5)
	var cells: Array[Vector3i] = [sand_cell, dirt_cell, log_cell]
	var placements := _placements([
		LevelChestPlacement.new(30, sand_cell, sand_bundle),
		LevelChestPlacement.new(10, dirt_cell, dirt_bundle),
		LevelChestPlacement.new(20, log_cell, log_bundle),
	])
	var reordered := _placements([
		LevelChestPlacement.new(20, log_cell, log_bundle),
		LevelChestPlacement.new(30, sand_cell, sand_bundle),
		LevelChestPlacement.new(10, dirt_cell, dirt_bundle),
	])
	var container := _container(1, 3)
	var first_inventory := _inventory()
	var first_loadout := InventoryTestFixture.create_loadout(first_inventory)
	var second_inventory := _inventory()
	var second_loadout := InventoryTestFixture.create_loadout(second_inventory)
	var first := DungeonChestCoordinator.new()
	var second := DungeonChestCoordinator.new()
	_expect(
		first.setup(placements, 417, reward, false, 90817, first_inventory, first_loadout, container),
		"one-time dungeon chest setup failed",
	)
	_expect(
		second.setup(reordered, 991, reward, false, 90817, second_inventory, second_loadout, container),
		"reordered one-time dungeon chest setup failed",
	)
	var first_cell := _find_chest_with_item(first, cells, container, &"basic_rune")
	var second_cell := _find_chest_with_item(second, cells, container, &"basic_rune")
	_expect(first_cell != Vector3i.ZERO, "one-time reward was not placed in any chest")
	_expect(first_cell == second_cell, "placement order or repeat seed changed one-time chest selection")
	if first_cell == Vector3i.ZERO or second_cell == Vector3i.ZERO:
		return
	_expect(first.try_open(first_cell, container), "selected one-time chest did not open")
	var selected_counts := _open_chest_item_counts(first, container.get_slot_count())
	_expect(selected_counts.size() == 2, "one-time chest mixed repeat loot into its reward bundle")
	_expect(selected_counts.get(&"basic_rune", 0) == 2, "one-time chest did not contain its guaranteed runes")
	_expect(selected_counts.get(&"copper", 0) >= 4, "one-time chest did not resolve its guaranteed copper")
	for repeat_item in [&"sand_block", &"dirt_block", &"log_block"]:
		_expect(not selected_counts.has(repeat_item), "one-time chest retained repeat item %s" % repeat_item)
	first.close()
	_expect(second.try_open(second_cell, container), "reordered selected one-time chest did not open")
	_expect(
		_open_chest_item_counts(second, container.get_slot_count()) == selected_counts,
		"stable one-time seed produced different reward contents",
	)
	second.close()

	_expect(first.try_open(first_cell, container), "one-time escrow chest did not reopen")
	var copper_slot := _find_slot(first, &"copper", container.get_slot_count())
	var first_inventory_before := first_inventory.to_dict()
	var first_revision_before := first_inventory.get_revision()
	var inventory_notifications: Array[bool] = []
	var reentrant_claim_rejections: Array[bool] = []
	var first_ref: WeakRef = weakref(first)
	first_inventory.inventory_changed.connect(func() -> void:
		inventory_notifications.append(true)
	)
	first.contents_changed.connect(func(_position: Vector3i) -> void:
		var active := first_ref.get_ref() as DungeonChestCoordinator
		reentrant_claim_rejections.append(active != null and active.prepare_one_time_claim() == null)
	)
	_expect(
		first.handle_drop(
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			ChestTransferCoordinator.PLAYER_SCOPE,
			0,
			2,
		),
		"partial one-time reward did not enter escrow",
	)
	_expect(first.prepare_one_time_claim() == null, "partial one-time chest exposed a claim")
	_expect(first_inventory.to_dict() == first_inventory_before, "partial one-time take changed inventory")
	_expect(first_inventory.get_revision() == first_revision_before, "partial one-time take revised inventory")
	_expect(inventory_notifications.is_empty(), "partial one-time take notified inventory")
	_expect(not first.repeatable_reward_taken, "one-time escrow take was tracked as repeat loot")

	var retry := DungeonChestCoordinator.new()
	_expect(
		retry.setup(reordered, 417, reward, false, 90817, first_inventory, first_loadout, container),
		"fresh dungeon run did not recreate one-time reward",
	)
	var retry_cell := _find_chest_with_item(retry, cells, container, &"basic_rune")
	_expect(retry_cell == first_cell, "fresh dungeon run changed designated one-time chest")
	if retry_cell != Vector3i.ZERO:
		_expect(retry.try_open(retry_cell, container), "fresh dungeon one-time chest did not open")
		_expect(
			_open_chest_item_counts(retry, container.get_slot_count()) == selected_counts,
			"fresh dungeon run retained partial escrow instead of restoring the bundle",
		)
		retry.close()
	_expect(first.move_all_to_backpack(), "remaining one-time bundle did not enter escrow")
	_expect(not first.can_move_all_to_backpack(), "empty one-time chest still advertised Take All")
	_expect(first_inventory.to_dict() == first_inventory_before, "complete one-time escrow changed inventory")
	_expect(first_inventory.get_revision() == first_revision_before, "complete one-time escrow revised inventory")
	_expect(inventory_notifications.is_empty(), "complete one-time escrow notified inventory")
	_expect(
		not reentrant_claim_rejections.is_empty() and not reentrant_claim_rejections.has(false),
		"one-time claim prepared during a chest transfer callback",
	)
	var first_claim := first.prepare_one_time_claim()
	var competing_claim := first.prepare_one_time_claim()
	_expect(first_claim != null and competing_claim != null, "empty one-time chest did not prepare its claim")
	if first_claim == null or competing_claim == null:
		return
	_expect(first_claim.get_reward_id() == reward.reward_id, "prepared claim exposed the wrong reward ID")
	var exposed_stacks := first_claim.get_stacks()
	var claim_counts := _stack_counts(exposed_stacks)
	_expect(claim_counts == selected_counts, "prepared claim did not contain the complete one-time bundle")
	exposed_stacks[0].count += 100
	_expect(_stack_counts(first_claim.get_stacks()) == claim_counts, "prepared claim exposed mutable reward stacks")
	_expect(not retry.can_commit_prepared_claim(first_claim), "foreign coordinator accepted a prepared claim")
	_expect(first.can_commit_prepared_claim(first_claim), "fresh prepared claim was not committable")
	_expect(first.commit_prepared_claim(first_claim), "prepared one-time claim did not commit")
	_expect(not first.can_commit_prepared_claim(competing_claim), "competing claim remained valid after escrow commit")
	_expect(not first.commit_prepared_claim(first_claim), "prepared one-time claim committed twice")
	_expect(first.prepare_one_time_claim() == null, "committed escrow prepared another claim")
	_expect(first_inventory.to_dict() == first_inventory_before, "claim commit directly mutated inventory")

func _test_one_time_capacity_and_repeat_modes() -> void:
	var repeat_bundle := _bundle(
		&"capacity_repeat",
		1,
		_entries([_entry(&"sand", _drop(&"sand_block", 3, 3))]),
		[],
	)
	var one_time_bundle := _bundle(
		&"capacity_one_time",
		2,
		_entries([
			_entry(&"rune", _drop(&"basic_rune")),
			_entry(&"sword", _drop(&"copper_sword")),
		]),
		[],
	)
	var reward := LevelOneTimeChestRewardDefinition.new()
	reward.reward_id = &"capacity_progression"
	reward.loot_bundle = one_time_bundle
	var cell := Vector3i(11, 5, -3)
	var placements := _placements([LevelChestPlacement.new(1, cell, repeat_bundle)])
	var inventory := _inventory()
	var dirt_max := _item_catalog.get_definition(&"dirt_block").max_stack
	for index in range(InventoryModel.FILLABLE_SIZE - 1):
		_expect(
			InventoryTestFixture.restore_slot(inventory, index, InventoryStack.new(&"dirt_block", dirt_max)),
			"one-time capacity fixture failed at %d" % index,
		)
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var coordinator := DungeonChestCoordinator.new()
	var messages: Array[String] = []
	coordinator.transfer_rejected.connect(func(message: String) -> void:
		messages.append(message)
	)
	var container := _container(1, 2)
	_expect(
		coordinator.setup(placements, 15, reward, false, 7001, inventory, loadout, container),
		"capacity one-time chest setup failed",
	)
	_expect(coordinator.try_open(cell, container), "capacity one-time chest did not open")
	var rune_slot := _find_slot(coordinator, &"basic_rune", container.get_slot_count())
	var sword_slot := _find_slot(coordinator, &"copper_sword", container.get_slot_count())
	var inventory_before := inventory.to_dict()
	var revision_before := inventory.get_revision()
	_expect(coordinator.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, rune_slot), "first reserved reward did not fit the last inventory slot")
	_expect(coordinator.prepare_one_time_claim() == null, "partially reserved full-inventory chest exposed a claim")
	_expect(not coordinator.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, sword_slot), "reward escrow exceeded eventual inventory capacity")
	_expect(messages == [DungeonChestCoordinator.INVENTORY_FULL_MESSAGE], "full one-time escrow did not request an inventory drop")
	_expect(
		coordinator.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, sword_slot) != null,
		"capacity rejection removed the reward from its chest",
	)
	_expect(inventory.to_dict() == inventory_before, "one-time capacity checks changed inventory")
	_expect(inventory.get_revision() == revision_before, "one-time capacity checks revised inventory")
	_expect(not coordinator.repeatable_reward_taken, "one-time capacity attempt was tracked as repeat loot")

	var claimed_inventory := _inventory()
	var claimed_loadout := InventoryTestFixture.create_loadout(claimed_inventory)
	var claimed := DungeonChestCoordinator.new()
	_expect(
		claimed.setup(placements, 15, reward, true, 7001, claimed_inventory, claimed_loadout, container),
		"claimed one-time reward mode did not initialize",
	)
	_expect(claimed.try_open(cell, container), "claimed reward chest did not open as repeatable")
	_expect(_find_slot(claimed, &"basic_rune", container.get_slot_count()) == -1, "claimed reward chest regenerated its one-time rune")
	_expect(_find_slot(claimed, &"copper_sword", container.get_slot_count()) == -1, "claimed reward chest regenerated its one-time equipment")
	var sand_slot := _find_slot(claimed, &"sand_block", container.get_slot_count())
	_expect(sand_slot >= 0, "claimed reward chest did not use its repeat loot pool")
	_expect(claimed.prepare_one_time_claim() == null, "claimed reward mode exposed a one-time claim")
	_expect(claimed.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, sand_slot), "claimed reward repeat loot did not transfer directly")
	_expect(claimed.repeatable_reward_taken, "claimed reward repeat loot was not tracked")
	var retained_inventory := claimed_inventory.to_dict()
	var next_run := DungeonChestCoordinator.new()
	_expect(
		next_run.setup(placements, 15, reward, true, 7001, claimed_inventory, claimed_loadout, container),
		"subsequent repeatable dungeon run did not initialize",
	)
	_expect(claimed_inventory.to_dict() == retained_inventory, "new dungeon runtime discarded previously taken repeat loot")
	_expect(not next_run.repeatable_reward_taken, "new dungeon runtime inherited repeat tracking")

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
		not coordinator.setup(duplicate_placements, 92, null, false, 0, inventory, loadout, container),
		"duplicate chest placement initialized partially",
	)
	_expect(inventory.to_dict() == inventory_before, "failed all-chest initialization changed inventory")
	_expect(inventory.get_revision() == revision_before, "failed all-chest initialization revised inventory")
	_expect(inventory.equipment_instance_factory.get_next_instance_id() == allocator_before, "failed all-chest initialization consumed equipment IDs")
	_expect(not coordinator.can_open(shared_cell), "failed all-chest initialization exposed candidate storage")
	var valid_placements := _placements([LevelChestPlacement.new(1, shared_cell, equipment_bundle)])
	_expect(coordinator.setup(valid_placements, 92, null, false, 0, inventory, loadout, container), "failed initialization stranded the coordinator")
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
		coordinator.setup(_placements([LevelChestPlacement.new(1, cell, bundle)]), 7, null, false, 0, inventory, loadout, container),
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

func _find_chest_with_item(
	coordinator: DungeonChestCoordinator,
	cells: Array[Vector3i],
	container: ContainerBlockDefinition,
	item_id: StringName,
) -> Vector3i:
	for cell in cells:
		if not coordinator.try_open(cell, container):
			return Vector3i.ZERO
		var found := _find_slot(coordinator, item_id, container.get_slot_count()) >= 0
		coordinator.close()
		if found:
			return cell
	return Vector3i.ZERO

func _open_chest_item_counts(coordinator: DungeonChestCoordinator, slot_count: int) -> Dictionary:
	var stacks: Array[InventoryStack] = []
	for slot_index in range(slot_count):
		var stack := coordinator.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, slot_index)
		if stack != null:
			stacks.append(stack)
	return _stack_counts(stacks)

func _stack_counts(stacks: Array[InventoryStack]) -> Dictionary:
	var counts: Dictionary = {}
	for stack in stacks:
		counts[stack.item_id] = int(counts.get(stack.item_id, 0)) + stack.count
	return counts

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
