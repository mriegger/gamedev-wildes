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
	_test_atomic_one_time_completion()
	_test_exit_capacity_revalidation()
	_test_repeatable_completion()
	_item_catalog = null
	call_deferred("_finish")

func _test_atomic_one_time_completion() -> void:
	var reward := _reward(
		&"story_reward",
		_bundle(
			&"story_bundle",
			2,
			_entries([
				_entry(&"copper", _drop(&"copper", 7)),
				_entry(&"rune", _drop(&"basic_rune", 2)),
			]),
		),
	)
	var repeat_bundle := _bundle(
		&"story_repeat",
		1,
		_entries([_entry(&"sand", _drop(&"sand_block", 3))]),
	)
	var cell := Vector3i(4, 2, -7)
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var chests := DungeonChestCoordinator.new()
	var container := _container(1, 3)
	_expect(
		chests.setup(
			_placements([LevelChestPlacement.new(1, cell, repeat_bundle)]),
			17,
			reward,
			false,
			33,
			inventory,
			loadout,
			container,
		),
		"one-time completion chest setup failed",
	)
	_expect(chests.try_open(cell, container), "one-time completion chest did not open")
	var inventory_before := inventory.to_dict()
	_expect(chests.move_all_to_backpack(), "one-time bundle did not enter escrow")
	_expect(inventory.to_dict() == inventory_before, "one-time escrow changed inventory before exit")
	var progress := DungeonProgressState.new()
	var inventory_observations: Array[bool] = []
	var progress_observations: Array[bool] = []
	var inventory_observer := func() -> void:
		inventory_observations.append(
			progress.has_claimed_reward(&"stone_instance", reward.reward_id)
			and chests.prepare_one_time_claim() == null
		)
	var progress_observer := func() -> void:
		progress_observations.append(
			inventory.get_inventory_item_count(&"copper") == 7
			and inventory.get_inventory_item_count(&"basic_rune") == 2
		)
	inventory.inventory_changed.connect(inventory_observer)
	progress.state_changed.connect(progress_observer)
	var outcome := DungeonRunCompletionTransaction.try_complete(
		chests,
		progress,
		&"stone_instance",
		reward,
		loadout,
	)
	_expect(outcome == DungeonRunCompletionTransaction.Outcome.COMPLETED, "one-time dungeon exit did not complete")
	_expect(progress.get_completion_count(&"stone_instance") == 1, "one-time exit did not increment completion count")
	_expect(progress.has_claimed_reward(&"stone_instance", reward.reward_id), "one-time exit did not persist its claim")
	_expect(inventory.get_inventory_item_count(&"copper") == 7, "one-time copper did not reach inventory")
	_expect(inventory.get_inventory_item_count(&"basic_rune") == 2, "one-time runes did not reach inventory")
	_expect(inventory_observations == [true], "inventory observer saw a partial completion transaction")
	_expect(progress_observations == [true], "progress observer saw a partial completion transaction")
	inventory.inventory_changed.disconnect(inventory_observer)
	progress.state_changed.disconnect(progress_observer)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			&"stone_instance",
			reward,
			loadout,
		) == DungeonRunCompletionTransaction.Outcome.INCOMPLETE,
		"claimed one-time completion replayed without repeat loot",
	)

func _test_exit_capacity_revalidation() -> void:
	var reward := _reward(
		&"capacity_reward",
		_bundle(
			&"capacity_bundle",
			1,
			_entries([_entry(&"rune", _drop(&"basic_rune"))]),
		),
	)
	var repeat_bundle := _bundle(
		&"capacity_repeat",
		1,
		_entries([_entry(&"sand", _drop(&"sand_block"))]),
	)
	var cell := Vector3i(-3, 5, 11)
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var chests := DungeonChestCoordinator.new()
	var container := _container(1, 1)
	_expect(
		chests.setup(
			_placements([LevelChestPlacement.new(1, cell, repeat_bundle)]),
			29,
			reward,
			false,
			41,
			inventory,
			loadout,
			container,
		),
		"capacity completion chest setup failed",
	)
	_expect(chests.try_open(cell, container), "capacity completion chest did not open")
	_expect(chests.move_all_to_backpack(), "capacity reward did not enter escrow")
	var dirt_count := _item_catalog.get_definition(&"dirt_block").max_stack
	for _index in range(InventoryModel.FILLABLE_SIZE):
		_expect(loadout.add_stack(InventoryStack.new(&"dirt_block", dirt_count)), "capacity fixture did not fill inventory")
	var full_inventory := inventory.to_dict()
	var progress := DungeonProgressState.new()
	var outcome := DungeonRunCompletionTransaction.try_complete(
		chests,
		progress,
		&"capacity_instance",
		reward,
		loadout,
	)
	_expect(outcome == DungeonRunCompletionTransaction.Outcome.INVENTORY_FULL, "full exit did not request an inventory drop")
	_expect(inventory.to_dict() == full_inventory, "blocked exit changed full inventory")
	_expect(progress.get_completion_count(&"capacity_instance") == 0, "blocked exit completed the dungeon")
	_expect(not progress.has_claimed_reward(&"capacity_instance", reward.reward_id), "blocked exit claimed the reward")
	_expect(chests.prepare_one_time_claim() != null, "blocked exit discarded pending rewards")
	_expect(loadout.discard_stack(0, dirt_count), "capacity fixture could not drop an inventory stack")
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			&"capacity_instance",
			reward,
			loadout,
		) == DungeonRunCompletionTransaction.Outcome.COMPLETED,
		"exit did not complete after inventory space was freed",
	)
	_expect(inventory.get_inventory_item_count(&"basic_rune") == 1, "freed inventory did not receive the pending reward")

func _test_repeatable_completion() -> void:
	var repeat_bundle := _bundle(
		&"farm_bundle",
		1,
		_entries([_entry(&"copper", _drop(&"copper", 4))]),
	)
	var cell := Vector3i(8, 1, 6)
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var chests := DungeonChestCoordinator.new()
	var container := _container(1, 1)
	_expect(
		chests.setup(
			_placements([LevelChestPlacement.new(1, cell, repeat_bundle)]),
			53,
			null,
			false,
			0,
			inventory,
			loadout,
			container,
		),
		"repeatable completion chest setup failed",
	)
	var progress := DungeonProgressState.new()
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			&"farm_instance",
			null,
			loadout,
		) == DungeonRunCompletionTransaction.Outcome.INCOMPLETE,
		"untouched repeatable dungeon completed",
	)
	_expect(chests.try_open(cell, container), "repeatable completion chest did not open")
	_expect(chests.move_all_to_backpack(), "repeatable reward did not transfer directly")
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			&"farm_instance",
			null,
			loadout,
		) == DungeonRunCompletionTransaction.Outcome.COMPLETED,
		"repeatable dungeon did not complete after taking loot",
	)
	_expect(progress.get_completion_count(&"farm_instance") == 1, "repeatable completion count did not increment")

func _inventory() -> InventoryModel:
	var inventory := InventoryModel.new(_item_catalog, EquipmentInstanceFactory.new(_item_catalog))
	assert(inventory.setup_empty())
	return inventory

func _container(rows: int, columns: int) -> ContainerBlockDefinition:
	var container := ContainerBlockDefinition.new()
	container.rows = rows
	container.columns = columns
	return container

func _reward(id: StringName, bundle: LootBundleDefinition) -> LevelOneTimeChestRewardDefinition:
	var reward := LevelOneTimeChestRewardDefinition.new()
	reward.reward_id = id
	reward.loot_bundle = bundle
	return reward

func _bundle(
	id: StringName,
	max_rewards: int,
	fixed_entries: Array[LootBundleEntryDefinition],
) -> LootBundleDefinition:
	var bundle := LootBundleDefinition.new()
	bundle.id = id
	bundle.max_rewards = max_rewards
	bundle.fixed_entries = fixed_entries
	return bundle

func _entry(id: StringName, drop: LootDropDefinition) -> LootBundleEntryDefinition:
	var entry := LootBundleEntryDefinition.new()
	entry.id = id
	entry.drop = drop
	return entry

func _drop(item_id: StringName, count: int = 1) -> LootDropDefinition:
	var drop := LootDropDefinition.new()
	drop.item = _item_catalog.get_definition(item_id)
	drop.minimum_count = count
	drop.maximum_count = count
	return drop

func _entries(values: Array) -> Array[LootBundleEntryDefinition]:
	var entries: Array[LootBundleEntryDefinition] = []
	entries.assign(values)
	return entries

func _placements(values: Array) -> Array[LevelChestPlacement]:
	var placements: Array[LevelChestPlacement] = []
	placements.assign(values)
	return placements

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("DUNGEON_RUN_COMPLETION PASS")
		quit(0)
		return
	for message in _errors:
		push_error(message)
	print("DUNGEON_RUN_COMPLETION FAIL count=%d" % _errors.size())
	quit(1)
