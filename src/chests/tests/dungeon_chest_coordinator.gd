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
	_test_deterministic_population_and_repeat_transfers()
	_test_atomic_one_time_claim_and_run_objective()
	_test_full_bundle_capacity_rejection()
	_test_pre_and_post_completion_pools()
	_test_atomic_initialization_failure()
	_item_catalog = null
	call_deferred("_finish")

func _test_shared_abstraction() -> void:
	_expect(ChestCoordinator.new() is ChestTransferCoordinator, "overworld coordinator does not implement the shared chest contract")
	_expect(DungeonChestCoordinator.new() is ChestTransferCoordinator, "dungeon coordinator does not implement the shared chest contract")

func _test_deterministic_population_and_repeat_transfers() -> void:
	var material_pool := _pool(
		&"dungeon_materials",
		_rolls([
			_roll(&"copper", 1.0, _drop(&"copper", 6, 6)),
			_roll(&"rune", 1.0, _drop(&"basic_rune")),
		]),
	)
	var equipment_roll := LootEquipmentRollDefinition.new()
	equipment_roll.fixed_affixes = _affixes([_item_catalog.get_equipment_affix(&"vicious")])
	equipment_roll.fixed_runes = _runes([_item_catalog.get_definition(&"basic_rune") as RuneDefinition])
	var equipment_pool := _pool(
		&"dungeon_equipment",
		_rolls([_roll(&"sword", 1.0, _drop(&"copper_sword", 1, 1, equipment_roll))]),
	)
	var material_cell := Vector3i(14, 3, -8)
	var equipment_cell := Vector3i(-4, 7, 19)
	var placements := _placements([
		LevelChestPlacement.new(9, equipment_cell, equipment_pool, null),
		LevelChestPlacement.new(2, material_cell, material_pool, null),
	])
	var reordered := _placements([
		LevelChestPlacement.new(2, material_cell, material_pool, null),
		LevelChestPlacement.new(9, equipment_cell, equipment_pool, null),
	])
	var container := _container(2, 3)
	var instance_id: StringName = &"deterministic_dungeon"
	var first_progress := DungeonProgressState.new()
	var second_progress := DungeonProgressState.new()
	_expect(first_progress.begin_attempt(instance_id) == 0, "first deterministic attempt did not begin")
	_expect(second_progress.begin_attempt(instance_id) == 0, "second deterministic attempt did not begin")
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
	_expect(
		first.setup(
			placements,
			41725,
			null,
			0,
			instance_id,
			first_progress,
			first_inventory,
			first_loadout,
			container,
		),
		"first dungeon chest setup failed",
	)
	_expect(
		second.setup(
			reordered,
			41725,
			null,
			0,
			instance_id,
			second_progress,
			second_inventory,
			second_loadout,
			container,
		),
		"reordered dungeon chest setup failed",
	)
	_expect(first_inventory.equipment_instance_factory.get_next_instance_id() == 2, "all-chest setup allocated the wrong equipment ID count")
	_expect(second_inventory.equipment_instance_factory.get_next_instance_id() == 2, "reordered setup allocated a different equipment ID count")
	var cells: Array[Vector3i] = [material_cell, equipment_cell]
	_expect(
		_encode_chests(first, cells, container) == _encode_chests(second, cells, container),
		"placement order changed deterministic chest contents",
	)
	_expect(first.try_open(material_cell, container), "material chest did not open")
	_expect(first.has_items_to_take(), "populated repeat chest reported no items")
	_expect(not first.is_active_one_time_reward(), "repeat chest reported a one-time reward")
	_expect(not first.has_met_completion_requirement(), "untouched repeat chest met the run objective")
	var copper_slot := _find_slot(first, &"copper", container.get_slot_count())
	var rune_slot := _find_slot(first, &"basic_rune", container.get_slot_count())
	_expect(copper_slot >= 0 and rune_slot >= 0, "guaranteed repeat rewards were not populated")
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
			ChestTransferCoordinator.CHEST_SCOPE,
			copper_slot,
			ChestTransferCoordinator.CHEST_SCOPE,
			rune_slot,
			1,
		),
		"chest-to-chest rearrangement committed",
	)
	_expect(_encode_open_chest(first, container.get_slot_count()) == material_before_rejections, "rejected repeat transfers changed chest state")
	_expect(first_inventory.to_dict() == inventory_before_rejections, "rejected repeat transfers changed inventory")
	var copper_before := first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, copper_slot).count
	var coherent_observations: Array[bool] = []
	var reentrant_results: Array[bool] = []
	var inventory_observer := func() -> void:
		var remaining := first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, copper_slot)
		coherent_observations.append(
			remaining != null
			and remaining.count == copper_before - 2
			and first_inventory.get_slot(1).item_id == &"copper"
			and first_inventory.get_slot(1).count == 2
			and first.has_met_completion_requirement()
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
		"partial repeat chest take failed",
	)
	first_inventory.inventory_changed.disconnect(inventory_observer)
	_expect(coherent_observations == [true], "repeat inventory observer saw a partial transaction")
	_expect(reentrant_results == [false], "repeat inventory observer reentered a chest transaction")
	_expect(first.has_met_completion_requirement(), "repeat take did not meet the run objective")
	_expect(first.move_all_to_backpack(), "Take all did not move remaining material rewards")
	_expect(not first.has_items_to_take(), "empty repeat chest still reported items to take")
	first.close()
	_expect(first.try_open(equipment_cell, container), "equipment chest did not open")
	var sword_slot := _find_slot(first, &"copper_sword", container.get_slot_count())
	_expect(sword_slot >= 0, "equipment reward was not populated")
	if sword_slot >= 0:
		var sword := first.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, sword_slot)
		_expect(sword.equipment_instance != null, "equipment reward has no variant instance")
		if sword.equipment_instance != null:
			_expect(sword.equipment_instance.instance_id == 1, "equipment reward received an unstable instance ID")
			_expect(sword.equipment_instance.affixes[0].affix_id == &"vicious", "equipment affix changed during population")
			_expect(sword.equipment_instance.socketed_rune_ids == _ids([&"basic_rune"]), "equipment rune changed during population")
			var fingerprint := sword.to_dict()
			_expect(first.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, sword_slot), "equipment quick-take failed")
			var moved_sword := _find_inventory_stack(first_inventory, &"copper_sword")
			_expect(moved_sword != null and moved_sword.to_dict() == fingerprint, "equipment variant changed during chest transfer")

func _test_atomic_one_time_claim_and_run_objective() -> void:
	var sand_pool := _pool(&"repeat_sand", _rolls([_roll(&"sand", 1.0, _drop(&"sand_block", 5, 5))]))
	var dirt_pool := _pool(&"repeat_dirt", _rolls([_roll(&"dirt", 1.0, _drop(&"dirt_block", 6, 6))]))
	var log_pool := _pool(&"repeat_log", _rolls([_roll(&"log", 1.0, _drop(&"log_block", 7, 7))]))
	var reward := _reward(
		&"progression_reward",
		_bundle(
			&"progression_bundle",
			3,
			_entries([
				_entry(&"copper", _drop(&"copper", 5, 5)),
				_entry(&"iron_pickaxe", _drop(&"iron_pickaxe")),
				_entry(&"rune", _drop(&"basic_rune", 2, 2)),
			]),
		),
	)
	var sand_cell := Vector3i(3, 1, 8)
	var dirt_cell := Vector3i(-7, 4, 2)
	var log_cell := Vector3i(9, 2, -5)
	var cells: Array[Vector3i] = [sand_cell, dirt_cell, log_cell]
	var placements := _placements([
		LevelChestPlacement.new(30, sand_cell, sand_pool, null),
		LevelChestPlacement.new(10, dirt_cell, dirt_pool, null),
		LevelChestPlacement.new(20, log_cell, log_pool, null),
	])
	var reordered := _placements([
		LevelChestPlacement.new(20, log_cell, log_pool, null),
		LevelChestPlacement.new(30, sand_cell, sand_pool, null),
		LevelChestPlacement.new(10, dirt_cell, dirt_pool, null),
	])
	var container := _container(1, 4)
	var instance_id: StringName = &"story_dungeon"
	var progress := DungeonProgressState.new()
	var mirror_progress := DungeonProgressState.new()
	_expect(progress.begin_attempt(instance_id) == 0, "first story attempt did not begin")
	_expect(mirror_progress.begin_attempt(instance_id) == 0, "mirror story attempt did not begin")
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var mirror_inventory := _inventory()
	var mirror_loadout := InventoryTestFixture.create_loadout(mirror_inventory)
	var coordinator := DungeonChestCoordinator.new()
	var mirror := DungeonChestCoordinator.new()
	_expect(
		coordinator.setup(
			placements,
			417,
			reward,
			90817,
			instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"one-time dungeon chest setup failed",
	)
	_expect(
		mirror.setup(
			reordered,
			991,
			reward,
			90817,
			instance_id,
			mirror_progress,
			mirror_inventory,
			mirror_loadout,
			container,
		),
		"reordered one-time dungeon chest setup failed",
	)
	var selected_cell := _find_chest_with_item(coordinator, cells, container, &"iron_pickaxe")
	var mirror_selected_cell := _find_chest_with_item(mirror, cells, container, &"iron_pickaxe")
	_expect(selected_cell != Vector3i.ZERO, "one-time reward was not placed in any chest")
	_expect(selected_cell == mirror_selected_cell, "placement order or repeat seed changed one-time chest selection")
	if selected_cell == Vector3i.ZERO or mirror_selected_cell == Vector3i.ZERO:
		return
	_expect(coordinator.try_open(selected_cell, container), "selected one-time chest did not open")
	var reward_counts := _open_chest_item_counts(coordinator, container.get_slot_count())
	_expect(reward_counts == {&"basic_rune": 2, &"copper": 5, &"iron_pickaxe": 1}, "one-time chest did not contain its exact reward bundle")
	_expect(coordinator.is_active_one_time_reward(), "selected one-time chest did not expose Claim Reward semantics")
	_expect(coordinator.has_items_to_take(), "selected one-time chest reported no items")
	_expect(not coordinator.has_met_completion_requirement(), "unclaimed one-time reward met the run objective")
	coordinator.close()
	_expect(mirror.try_open(mirror_selected_cell, container), "mirror one-time chest did not open")
	_expect(
		_open_chest_item_counts(mirror, container.get_slot_count()) == reward_counts,
		"stable one-time seed produced different reward contents",
	)
	mirror.close()
	var repeat_cell := sand_cell if selected_cell != sand_cell else dirt_cell
	_expect(coordinator.try_open(repeat_cell, container), "repeat chest did not open before one-time claim")
	_expect(not coordinator.is_active_one_time_reward(), "repeat chest exposed Claim Reward semantics")
	_expect(coordinator.move_all_to_backpack(), "repeat reward could not be taken before the one-time reward")
	_expect(not coordinator.has_met_completion_requirement(), "repeat reward replaced the first-run claim objective")
	coordinator.close()
	_expect(coordinator.try_open(selected_cell, container), "one-time chest did not reopen for its claim")
	var clicked_slot := _find_slot(coordinator, &"basic_rune", container.get_slot_count())
	var inventory_before := inventory.to_dict()
	var inventory_revision_before := inventory.get_revision()
	var progress_before := progress.snapshot()
	var stale_claim := progress.prepare_reward_claim(instance_id, reward.reward_id)
	var stale_completion := progress.prepare_completion(instance_id)
	var inventory_observations: Array[bool] = []
	var progress_observations: Array[bool] = []
	var contents_observations: Array[bool] = []
	var reentrant_results: Array[bool] = []
	var claimed_ids: Array[StringName] = []
	var inventory_observer := func() -> void:
		inventory_observations.append(
			_inventory_contains_counts(inventory, reward_counts)
			and progress.has_claimed_reward(instance_id, reward.reward_id)
			and not coordinator.has_items_to_take()
			and not coordinator.is_active_one_time_reward()
			and coordinator.has_met_completion_requirement()
		)
		reentrant_results.append(coordinator.move_all_to_backpack())
	var progress_observer := func() -> void:
		progress_observations.append(
			_inventory_contains_counts(inventory, reward_counts)
			and progress.has_claimed_reward(instance_id, reward.reward_id)
			and not coordinator.has_items_to_take()
		)
	var contents_observer := func(position: Vector3i) -> void:
		contents_observations.append(
			position == selected_cell
			and _inventory_contains_counts(inventory, reward_counts)
			and progress.has_claimed_reward(instance_id, reward.reward_id)
			and not coordinator.has_items_to_take()
		)
	var claim_observer := func(reward_id: StringName) -> void:
		claimed_ids.append(reward_id)
	inventory.inventory_changed.connect(inventory_observer)
	progress.state_changed.connect(progress_observer)
	coordinator.contents_changed.connect(contents_observer)
	coordinator.one_time_reward_claimed.connect(claim_observer)
	_expect(
		coordinator.quick_transfer(ChestTransferCoordinator.CHEST_SCOPE, clicked_slot),
		"one-time reward click did not claim the complete bundle",
	)
	inventory.inventory_changed.disconnect(inventory_observer)
	progress.state_changed.disconnect(progress_observer)
	coordinator.contents_changed.disconnect(contents_observer)
	coordinator.one_time_reward_claimed.disconnect(claim_observer)
	_expect(inventory.to_dict() != inventory_before, "one-time claim did not update inventory immediately")
	_expect(inventory.get_revision() == inventory_revision_before + 1, "one-time bundle revised inventory more than once")
	_expect(_inventory_contains_counts(inventory, reward_counts), "one-time claim omitted part of its reward bundle")
	_expect(progress.snapshot() != progress_before, "one-time claim did not update persistent progress immediately")
	_expect(progress.has_claimed_reward(instance_id, reward.reward_id), "one-time reward claim was not persisted")
	_expect(progress.get_completion_count(instance_id) == 0, "one-time claim completed the dungeon before exit")
	_expect(not coordinator.has_items_to_take(), "claimed one-time chest retained items")
	_expect(not coordinator.is_active_one_time_reward(), "claimed one-time chest retained Claim Reward semantics")
	_expect(coordinator.has_met_completion_requirement(), "one-time claim did not meet the first-run objective")
	_expect(inventory_observations == [true], "inventory observer saw a partial one-time claim")
	_expect(progress_observations == [true], "progress observer saw a partial one-time claim")
	_expect(contents_observations == [true], "contents observer saw a partial one-time claim")
	_expect(reentrant_results == [false], "inventory observer reentered a one-time claim")
	_expect(claimed_ids == _ids([reward.reward_id]), "one-time reward signal did not report exactly one claim")
	_expect(stale_claim != null and not progress.can_commit_prepared_reward_claim(stale_claim), "pre-claim reward transaction was not invalidated")
	_expect(stale_completion != null and not progress.can_commit_prepared_completion(stale_completion), "pre-claim completion transaction was not invalidated")
	var claimed_inventory := inventory.to_dict()
	var claimed_progress := progress.snapshot()
	_expect(not coordinator.move_all_to_backpack(), "claimed one-time reward was granted twice")
	_expect(inventory.to_dict() == claimed_inventory and progress.snapshot() == claimed_progress, "repeated claim changed committed state")
	coordinator.close()
	_expect(progress.begin_attempt(instance_id) == 1, "restart after one-time claim did not begin")
	var restart := DungeonChestCoordinator.new()
	_expect(
		restart.setup(
			placements,
			417,
			reward,
			90817,
			instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"restart after one-time claim did not initialize",
	)
	_expect(progress.get_completion_count(instance_id) == 0, "restart silently completed the dungeon")
	_expect(not restart.has_met_completion_requirement(), "one-time claim counted as repeat loot in a new run")
	_expect(restart.try_open(selected_cell, container), "claimed reward chest did not reopen as repeatable")
	_expect(not restart.is_active_one_time_reward(), "claimed reward chest still exposed Claim Reward semantics")
	_expect(_find_slot(restart, &"iron_pickaxe", container.get_slot_count()) == -1, "claimed one-time pickaxe regenerated")
	_expect(_find_slot(restart, &"basic_rune", container.get_slot_count()) == -1, "claimed one-time rune regenerated")
	_expect(restart.move_all_to_backpack(), "restart repeat loot did not transfer")
	_expect(restart.has_met_completion_requirement(), "restart repeat take did not meet the run objective")

func _test_full_bundle_capacity_rejection() -> void:
	var repeat_pool := _pool(&"capacity_repeat", _rolls([_roll(&"sand", 1.0, _drop(&"sand_block", 3, 3))]))
	var reward := _reward(
		&"capacity_reward",
		_bundle(
			&"capacity_bundle",
			2,
			_entries([
				_entry(&"iron_pickaxe", _drop(&"iron_pickaxe")),
				_entry(&"rune", _drop(&"basic_rune")),
			]),
		),
	)
	var instance_id: StringName = &"capacity_dungeon"
	var progress := DungeonProgressState.new()
	_expect(progress.begin_attempt(instance_id) == 0, "capacity attempt did not begin")
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
	var claimed_ids: Array[StringName] = []
	coordinator.transfer_rejected.connect(func(message: String) -> void:
		messages.append(message)
	)
	coordinator.one_time_reward_claimed.connect(func(reward_id: StringName) -> void:
		claimed_ids.append(reward_id)
	)
	var cell := Vector3i(11, 5, -3)
	var container := _container(1, 2)
	_expect(
		coordinator.setup(
			_placements([LevelChestPlacement.new(1, cell, repeat_pool, null)]),
			15,
			reward,
			7001,
			instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"capacity one-time chest setup failed",
	)
	_expect(coordinator.try_open(cell, container), "capacity one-time chest did not open")
	_expect(coordinator.has_items_to_take(), "full-inventory one-time chest reported no items")
	_expect(coordinator.is_active_one_time_reward(), "full-inventory one-time chest lost Claim Reward semantics")
	var chest_before := _encode_open_chest(coordinator, container.get_slot_count())
	var inventory_before := inventory.to_dict()
	var inventory_revision_before := inventory.get_revision()
	var progress_before := progress.snapshot()
	_expect(not coordinator.move_all_to_backpack(), "partial capacity accepted a one-time reward bundle")
	_expect(messages == [DungeonChestCoordinator.INVENTORY_FULL_MESSAGE], "full reward bundle did not request an inventory drop")
	_expect(claimed_ids.is_empty(), "rejected reward emitted a claim")
	_expect(_encode_open_chest(coordinator, container.get_slot_count()) == chest_before, "rejected reward changed chest contents")
	_expect(inventory.to_dict() == inventory_before, "rejected reward partially changed inventory")
	_expect(inventory.get_revision() == inventory_revision_before, "rejected reward revised inventory")
	_expect(progress.snapshot() == progress_before, "rejected reward partially changed progress")
	_expect(not progress.has_claimed_reward(instance_id, reward.reward_id), "rejected reward persisted a claim")
	_expect(not coordinator.has_met_completion_requirement(), "rejected reward met the run objective")
	_expect(coordinator.has_items_to_take() and coordinator.is_active_one_time_reward(), "rejected reward was no longer available")

func _test_pre_and_post_completion_pools() -> void:
	var pre_pool := load("res://levels/content/dungeons/stone/stone_chest_loot.tres") as LootPoolDefinition
	var post_pool := load("res://levels/content/dungeons/stone/stone_post_completion_chest_loot.tres") as LootPoolDefinition
	_expect(pre_pool != null and LevelLootCatalogValidator.validate_chest_pool(pre_pool, _item_catalog, 2), "stone pre-completion chest pool invalid")
	_expect(post_pool != null and LevelLootCatalogValidator.validate_chest_pool(post_pool, _item_catalog, 2), "stone post-completion chest pool invalid")
	if pre_pool == null or post_pool == null:
		return
	var placements: Array[LevelChestPlacement] = []
	var reversed: Array[LevelChestPlacement] = []
	var cells: Array[Vector3i] = []
	for index in range(40):
		var cell := Vector3i(index + 1, 3, (index * 7) % 19 + 1)
		cells.append(cell)
		placements.append(LevelChestPlacement.new(index, cell, pre_pool, post_pool))
	for index in range(placements.size() - 1, -1, -1):
		reversed.append(placements[index])
	var instance_id: StringName = &"stone_pool_modes"
	var progress := DungeonProgressState.new()
	_expect(progress.begin_attempt(instance_id) == 0, "pre-completion pool attempt did not begin")
	var container := _container(1, 2)
	var pre_inventory := _inventory()
	var pre_coordinator := DungeonChestCoordinator.new()
	_expect(
		pre_coordinator.setup(
			placements,
			62091,
			null,
			0,
			instance_id,
			progress,
			pre_inventory,
			InventoryTestFixture.create_loadout(pre_inventory),
			container,
		),
		"pre-completion chest population failed",
	)
	for cell in cells:
		var counts := _chest_item_counts_at(pre_coordinator, cell, container)
		_expect(counts.get(&"pumpkin", 0) >= 5 and counts.get(&"pumpkin", 0) <= 10, "pre-completion chest omitted its 5-10 pumpkins")
		_expect(not counts.has(&"iron_pickaxe"), "pre-completion chest rolled the post-completion bonus")
	_expect(not pre_coordinator.has_met_completion_requirement(), "opening pre-completion chests met the run objective")
	_expect(_complete(progress, instance_id), "pool-mode completion fixture failed")
	_expect(progress.get_completion_count(instance_id) == 1, "pool-mode completion count did not advance")
	var latched_counts := _chest_item_counts_at(pre_coordinator, cells[0], container)
	_expect(not latched_counts.has(&"iron_pickaxe"), "active run changed loot pools after completion state changed")
	_expect(progress.begin_attempt(instance_id) == 1, "post-completion pool attempt did not begin")
	var post_inventory := _inventory()
	var mirror_inventory := _inventory()
	var post_coordinator := DungeonChestCoordinator.new()
	var mirror := DungeonChestCoordinator.new()
	_expect(
		post_coordinator.setup(
			placements,
			62091,
			null,
			0,
			instance_id,
			progress,
			post_inventory,
			InventoryTestFixture.create_loadout(post_inventory),
			container,
		),
		"post-completion chest population failed",
	)
	_expect(
		mirror.setup(
			reversed,
			62091,
			null,
			0,
			instance_id,
			progress,
			mirror_inventory,
			InventoryTestFixture.create_loadout(mirror_inventory),
			container,
		),
		"reordered post-completion chest population failed",
	)
	_expect(
		_encode_chests(post_coordinator, cells, container) == _encode_chests(mirror, cells, container),
		"per-chest post-completion loot changed with placement order",
	)
	var saw_bonus := false
	var saw_no_bonus := false
	for cell in cells:
		var counts := _chest_item_counts_at(post_coordinator, cell, container)
		var pumpkin_count := int(counts.get(&"pumpkin", 0))
		var iron_count := int(counts.get(&"iron_pickaxe", 0))
		_expect(pumpkin_count >= 5 and pumpkin_count <= 10, "post-completion chest omitted its 5-10 pumpkins")
		_expect(iron_count == 0 or iron_count == 1, "post-completion chest produced an invalid bonus count")
		saw_bonus = saw_bonus or iron_count == 1
		saw_no_bonus = saw_no_bonus or iron_count == 0
	_expect(saw_bonus and saw_no_bonus, "25% post-completion bonus did not both hit and miss across per-chest seeds")
	_expect(not post_coordinator.has_met_completion_requirement(), "post-completion run began with its loot objective met")
	_expect(post_coordinator.try_open(cells[0], container), "post-completion objective chest did not open")
	_expect(not post_coordinator.is_active_one_time_reward(), "post-completion repeat chest exposed Claim Reward semantics")
	_expect(post_coordinator.move_all_to_backpack(), "post-completion repeat loot did not transfer")
	_expect(post_coordinator.has_met_completion_requirement(), "post-completion repeat take did not meet the run objective")

func _test_atomic_initialization_failure() -> void:
	var equipment_pool := _pool(
		&"atomic_equipment",
		_rolls([_roll(&"sword", 1.0, _drop(&"copper_sword"))]),
	)
	var shared_cell := Vector3i(3, 5, 7)
	var duplicate_placements := _placements([
		LevelChestPlacement.new(1, shared_cell, equipment_pool, null),
		LevelChestPlacement.new(2, shared_cell, equipment_pool, null),
	])
	var inventory := _inventory()
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var inventory_before := inventory.to_dict()
	var revision_before := inventory.get_revision()
	var allocator_before := inventory.equipment_instance_factory.get_next_instance_id()
	var progress := DungeonProgressState.new()
	var instance_id: StringName = &"atomic_initialization"
	_expect(progress.begin_attempt(instance_id) == 0, "atomic initialization attempt did not begin")
	var coordinator := DungeonChestCoordinator.new()
	var container := _container(1, 2)
	_expect(
		not coordinator.setup(
			duplicate_placements,
			92,
			null,
			0,
			instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"duplicate chest placement initialized partially",
	)
	_expect(inventory.to_dict() == inventory_before, "failed all-chest initialization changed inventory")
	_expect(inventory.get_revision() == revision_before, "failed all-chest initialization revised inventory")
	_expect(inventory.equipment_instance_factory.get_next_instance_id() == allocator_before, "failed all-chest initialization consumed equipment IDs")
	_expect(not coordinator.can_open(shared_cell), "failed all-chest initialization exposed candidate storage")
	var valid_placements := _placements([LevelChestPlacement.new(1, shared_cell, equipment_pool, null)])
	_expect(
		coordinator.setup(
			valid_placements,
			92,
			null,
			0,
			instance_id,
			progress,
			inventory,
			loadout,
			container,
		),
		"failed initialization stranded the coordinator",
	)
	_expect(inventory.equipment_instance_factory.get_next_instance_id() == allocator_before + 1, "successful retry did not commit the allocator once")
	_expect(coordinator.try_open(shared_cell, container), "successfully retried chest did not open")
	var sword_slot := _find_slot(coordinator, &"copper_sword", container.get_slot_count())
	_expect(sword_slot >= 0, "successfully retried chest has no equipment reward")
	if sword_slot >= 0:
		_expect(
			coordinator.get_inventory_stack(ChestTransferCoordinator.CHEST_SCOPE, sword_slot).equipment_instance.instance_id == allocator_before,
			"successful retry skipped the rolled-back equipment ID",
		)

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

func _reward(id: StringName, bundle: LootBundleDefinition) -> LevelOneTimeChestRewardDefinition:
	var reward := LevelOneTimeChestRewardDefinition.new()
	reward.reward_id = id
	reward.loot_bundle = bundle
	return reward

func _pool(id: StringName, rolls: Array[LootIndependentRollDefinition]) -> LootPoolDefinition:
	var pool := LootPoolDefinition.new()
	pool.id = id
	pool.independent_rolls = rolls
	return pool

func _roll(id: StringName, chance: float, drop: LootDropDefinition) -> LootIndependentRollDefinition:
	var roll := LootIndependentRollDefinition.new()
	roll.id = id
	roll.chance = chance
	roll.drop = drop
	return roll

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

func _rolls(values: Array) -> Array[LootIndependentRollDefinition]:
	var rolls: Array[LootIndependentRollDefinition] = []
	rolls.assign(values)
	return rolls

func _entries(values: Array) -> Array[LootBundleEntryDefinition]:
	var entries: Array[LootBundleEntryDefinition] = []
	entries.assign(values)
	return entries

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

func _complete(progress: DungeonProgressState, instance_id: StringName) -> bool:
	var prepared := progress.prepare_completion(instance_id)
	return progress.commit_prepared_completion(prepared)

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

func _inventory_contains_counts(inventory: InventoryModel, expected: Dictionary) -> bool:
	for item_id in expected:
		if inventory.get_inventory_item_count(item_id) != int(expected[item_id]):
			return false
	return true

func _chest_item_counts_at(
	coordinator: DungeonChestCoordinator,
	cell: Vector3i,
	container: ContainerBlockDefinition,
) -> Dictionary:
	if not coordinator.try_open(cell, container):
		return {}
	var counts := _open_chest_item_counts(coordinator, container.get_slot_count())
	coordinator.close()
	return counts

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
