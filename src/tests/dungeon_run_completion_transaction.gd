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
	_test_direct_claim_then_alive_completion()
	_test_abandoned_claim_requires_repeat_transfer()
	_test_farmable_dungeon_requires_repeat_transfer()
	_test_invalid_arguments()
	_item_catalog = null
	call_deferred("_finish")

func _test_direct_claim_then_alive_completion() -> void:
	var dungeon_instance_id := &"story_instance"
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
	var repeat_pool := _pool(
		&"story_repeat",
		_rolls([_roll(&"sand", _drop(&"sand_block", 3))]),
	)
	var cell := Vector3i(4, 2, -7)
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var progress := DungeonProgressState.new()
	_expect(progress.begin_attempt(dungeon_instance_id) == 0, "story attempt did not begin")
	var chests := DungeonChestCoordinator.new()
	var container := _container(1, 3)
	_expect(
		chests.setup(
			_placements([LevelChestPlacement.new(1, cell, repeat_pool, null)]),
			17,
			reward,
			33,
			dungeon_instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"story chest setup failed",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.INCOMPLETE,
		"unclaimed story run completed before its reward was claimed",
	)
	_expect(progress.get_completion_count(dungeon_instance_id) == 0, "incomplete story run changed completion count")
	_expect(chests.try_open(cell, container), "story chest did not open")
	_expect(chests.is_active_one_time_reward(), "story reward chest was not active")
	var inventory_observations: Array[bool] = []
	var progress_observations: Array[bool] = []
	var contents_observations: Array[bool] = []
	var claim_observations: Array[bool] = []
	var inventory_observer := func() -> void:
		inventory_observations.append(
			progress.has_claimed_reward(dungeon_instance_id, reward.reward_id)
			and not chests.has_items_to_take()
			and progress.get_completion_count(dungeon_instance_id) == 0
		)
	var progress_observer := func() -> void:
		progress_observations.append(
			inventory.get_inventory_item_count(&"copper") == 7
			and inventory.get_inventory_item_count(&"basic_rune") == 2
			and not chests.has_items_to_take()
			and progress.get_completion_count(dungeon_instance_id) == 0
		)
	var contents_observer := func(position: Vector3i) -> void:
		contents_observations.append(
			position == cell
			and inventory.get_inventory_item_count(&"copper") == 7
			and inventory.get_inventory_item_count(&"basic_rune") == 2
			and progress.has_claimed_reward(dungeon_instance_id, reward.reward_id)
			and progress.get_completion_count(dungeon_instance_id) == 0
		)
	var claim_observer := func(reward_id: StringName) -> void:
		claim_observations.append(
			reward_id == reward.reward_id
			and inventory.get_inventory_item_count(&"copper") == 7
			and inventory.get_inventory_item_count(&"basic_rune") == 2
			and progress.has_claimed_reward(dungeon_instance_id, reward.reward_id)
			and progress.get_completion_count(dungeon_instance_id) == 0
		)
	inventory.inventory_changed.connect(inventory_observer)
	progress.state_changed.connect(progress_observer)
	chests.contents_changed.connect(contents_observer)
	chests.one_time_reward_claimed.connect(claim_observer)
	_expect(chests.move_all_to_backpack(), "story reward was not claimed directly")
	_expect(inventory.get_inventory_item_count(&"copper") == 7, "direct claim did not add story copper")
	_expect(inventory.get_inventory_item_count(&"basic_rune") == 2, "direct claim did not add story runes")
	_expect(progress.has_claimed_reward(dungeon_instance_id, reward.reward_id), "direct claim was not persisted")
	_expect(progress.get_completion_count(dungeon_instance_id) == 0, "direct claim completed the story run")
	_expect(chests.has_met_completion_requirement(), "direct claim did not qualify the story run")
	_expect(inventory_observations == [true], "inventory observer saw a partial direct claim")
	_expect(progress_observations == [true], "progress observer saw a partial direct claim")
	_expect(contents_observations == [true], "chest observer saw a partial direct claim")
	_expect(claim_observations == [true], "claim observer saw a partial direct claim")
	inventory.inventory_changed.disconnect(inventory_observer)
	progress.state_changed.disconnect(progress_observer)
	chests.contents_changed.disconnect(contents_observer)
	chests.one_time_reward_claimed.disconnect(claim_observer)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.COMPLETED,
		"alive story exit did not complete after the direct claim",
	)
	_expect(progress.get_completion_count(dungeon_instance_id) == 1, "alive story exit did not increment completion count")

func _test_abandoned_claim_requires_repeat_transfer() -> void:
	var dungeon_instance_id := &"abandoned_instance"
	var reward := _reward(
		&"abandoned_reward",
		_bundle(
			&"abandoned_bundle",
			1,
			_entries([_entry(&"rune", _drop(&"basic_rune"))]),
		),
	)
	var repeat_pool := _pool(
		&"abandoned_repeat",
		_rolls([_roll(&"sand", _drop(&"sand_block", 3))]),
	)
	var placement := LevelChestPlacement.new(2, Vector3i(-3, 5, 11), repeat_pool, null)
	var placements := _placements([placement])
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var progress := DungeonProgressState.new()
	var container := _container(1, 3)
	_expect(progress.begin_attempt(dungeon_instance_id) == 0, "abandoned attempt did not begin")
	var abandoned_chests := DungeonChestCoordinator.new()
	_expect(
		abandoned_chests.setup(
			placements,
			29,
			reward,
			41,
			dungeon_instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"abandoned run chest setup failed",
	)
	_expect(abandoned_chests.try_open(placement.cell, container), "abandoned reward chest did not open")
	_expect(abandoned_chests.move_all_to_backpack(), "abandoned reward was not claimed")
	_expect(progress.has_claimed_reward(dungeon_instance_id, reward.reward_id), "abandoned reward claim was not retained")
	_expect(progress.get_completion_count(dungeon_instance_id) == 0, "claiming before death or abandon completed the run")
	_expect(inventory.get_inventory_item_count(&"basic_rune") == 1, "abandoned reward was not retained in inventory")
	_expect(progress.begin_attempt(dungeon_instance_id) == 1, "repeat attempt did not begin")
	var repeat_chests := DungeonChestCoordinator.new()
	_expect(
		repeat_chests.setup(
			placements,
			53,
			reward,
			67,
			dungeon_instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"repeat run chest setup failed",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			repeat_chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.INCOMPLETE,
		"already-claimed repeat run completed without a positive transfer",
	)
	_expect(repeat_chests.try_open(placement.cell, container), "repeat reward chest did not open")
	_expect(not repeat_chests.is_active_one_time_reward(), "claimed reward was offered again")
	_expect(repeat_chests.move_all_to_backpack(), "repeat reward did not transfer")
	_expect(inventory.get_inventory_item_count(&"sand_block") == 3, "repeat transfer did not add sand")
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			repeat_chests,
			DungeonProgressState.new(),
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.INVALIDATED,
		"completion accepted a different progress owner",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			repeat_chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.COMPLETED,
		"repeat run did not complete after a positive transfer",
	)
	_expect(progress.get_completion_count(dungeon_instance_id) == 1, "repeat run completion count did not increment")
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			repeat_chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.INCOMPLETE,
		"repeated exit completed without a new qualifying transfer",
	)
	_expect(progress.get_completion_count(dungeon_instance_id) == 1, "repeated exit changed completion count")

func _test_farmable_dungeon_requires_repeat_transfer() -> void:
	var dungeon_instance_id := &"farm_instance"
	var repeat_pool := _pool(
		&"farm_pool",
		_rolls([_roll(&"copper", _drop(&"copper", 4))]),
	)
	var placement := LevelChestPlacement.new(3, Vector3i(8, 1, 6), repeat_pool, null)
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var progress := DungeonProgressState.new()
	_expect(progress.begin_attempt(dungeon_instance_id) == 0, "farm attempt did not begin")
	var chests := DungeonChestCoordinator.new()
	var container := _container(1, 1)
	_expect(
		chests.setup(
			_placements([placement]),
			71,
			null,
			0,
			dungeon_instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"farm chest setup failed",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.INCOMPLETE,
		"untouched farmable dungeon completed",
	)
	_expect(chests.try_open(placement.cell, container), "farm chest did not open")
	_expect(chests.move_all_to_backpack(), "farm reward did not transfer")
	_expect(inventory.get_inventory_item_count(&"copper") == 4, "farm transfer did not add copper")
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			dungeon_instance_id,
		) == DungeonRunCompletionTransaction.Outcome.COMPLETED,
		"farmable dungeon did not complete after a positive transfer",
	)
	_expect(progress.get_completion_count(dungeon_instance_id) == 1, "farmable completion count did not increment")

func _test_invalid_arguments() -> void:
	var progress := DungeonProgressState.new()
	var chests := DungeonChestCoordinator.new()
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			&"invalid_instance",
		) == DungeonRunCompletionTransaction.Outcome.INVALIDATED,
		"uninitialized chest coordinator was not invalidated",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			null,
			progress,
			&"invalid_instance",
		) == DungeonRunCompletionTransaction.Outcome.INVALIDATED,
		"null chest coordinator was not invalidated",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			null,
			&"invalid_instance",
		) == DungeonRunCompletionTransaction.Outcome.INVALIDATED,
		"null progress was not invalidated",
	)
	_expect(
		DungeonRunCompletionTransaction.try_complete(
			chests,
			progress,
			&"",
		) == DungeonRunCompletionTransaction.Outcome.INVALIDATED,
		"empty dungeon instance ID was not invalidated",
	)

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

func _pool(
	id: StringName,
	independent_rolls: Array[LootIndependentRollDefinition],
) -> LootPoolDefinition:
	var pool := LootPoolDefinition.new()
	pool.id = id
	pool.independent_rolls = independent_rolls
	return pool

func _roll(id: StringName, drop: LootDropDefinition) -> LootIndependentRollDefinition:
	var roll := LootIndependentRollDefinition.new()
	roll.id = id
	roll.chance = 1.0
	roll.drop = drop
	return roll

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

func _rolls(values: Array) -> Array[LootIndependentRollDefinition]:
	var rolls: Array[LootIndependentRollDefinition] = []
	rolls.assign(values)
	return rolls

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
