extends SceneTree

class EnvironmentProbe:
	extends GameEnvironment

	func get_time_of_day() -> float:
		return 9.5

var _errors: Array[String] = []
var _slot_id: int
var _save_path: String

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var chest_block := block_catalog.get_definition(BlockId.Type.CHEST) if block_catalog != null else null
	var stats_definition := load("res://player/player_stats.tres") as PlayerStatsDefinition
	var perk_rules := load("res://progression/player_perk_rules.tres") as PlayerPerkRules
	_expect(block_catalog != null and block_catalog.validate(), "block catalog did not load")
	_expect(item_catalog != null and block_catalog != null and item_catalog.validate(block_catalog), "item catalog did not load")
	_expect(chest_block != null and chest_block.container != null, "chest container definition did not load")
	_expect(stats_definition != null and stats_definition.validate(), "player stats did not load")
	_expect(perk_rules != null and stats_definition != null and perk_rules.validate(stats_definition), "player perk rules did not load")
	if (
		item_catalog == null
		or block_catalog == null
		or chest_block == null
		or chest_block.container == null
		or stats_definition == null
		or perk_rules == null
	):
		_finish()
		return
	_expect(chest_block.container.get_slot_count() == SaveManager.PERSISTED_CHEST_SLOT_COUNT, "chest container slot count did not match the save schema")
	_slot_id = 1200000000 + OS.get_process_id()
	while SaveManager.slot_exists(_slot_id):
		_slot_id += 1
	_save_path = SaveManager.get_slot_path(_slot_id)
	var save_data := SaveManager.create_new_world(_slot_id, 4173, "World Loot Session")
	var seeded_progress := DungeonProgressState.new()
	_expect(seeded_progress.begin_attempt(&"stone_story") == 0, "session dungeon attempt fixture failed")
	var seeded_claim := seeded_progress.prepare_reward_claim(&"stone_story", &"basic_rune_reward")
	_expect(seeded_claim != null and seeded_progress.commit_prepared_reward_claim(seeded_claim), "session dungeon reward claim fixture failed")
	var seeded_completion := seeded_progress.prepare_completion(&"stone_story")
	_expect(seeded_completion != null and seeded_progress.commit_prepared_completion(seeded_completion), "session dungeon completion fixture failed")
	save_data["dungeon_progress"] = seeded_progress.snapshot()
	var restored_progress := DungeonProgressState.new()
	_expect(restored_progress.restore(save_data["dungeon_progress"]), "session dungeon progress restore fixture failed")
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var world_loot_state := WorldLootState.new(item_catalog, factory)
	_expect(_add_stack(world_loot_state, InventoryStack.new(&"sand_block", 3), Vector3(2.5, 4.0, -1.5)), "initial world loot setup failed")
	var world := WorldController.new()
	world.voxel_model = VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var player_stats := ActorStats.new(stats_definition)
	_expect(player_stats.set_progression(2, 0), "player progression setup failed")
	var player_perks := PlayerPerks.new(perk_rules)
	_expect(player_perks.restore({"allocations": {"health": 1}}, player_stats.get_level()), "player perk setup failed")
	var item_proficiency := ItemProficiency.new(item_catalog)
	var tutorial_progress := TutorialProgress.new()
	_expect(tutorial_progress.restore({"mining_tip_completed": false}), "tutorial progress setup failed")
	var chest_storage := ChestStorage.new(item_catalog, factory, chest_block.container.get_slot_count())
	var chest_coordinator := ChestCoordinator.new()
	var overworld_loot := OverworldLootCoordinator.new()
	overworld_loot._world_loot_state = world_loot_state
	var environment := EnvironmentProbe.new()
	var pumpkin_patch := PumpkinPatchCoordinator.new()
	var apple_trees := AppleTreeCoordinator.new()
	_expect(apple_trees._state.collect(Vector3i(3, 4, 5), 2), "session apple collection fixture failed")
	_expect(apple_trees._state.add_fallen_apple(Vector3i(3, 4, 5), 7, Vector3(4.25, 5.0, 6.75)), "session fallen apple fixture failed")
	var session := GameSession.new()
	var persisted_position := Vector3(6.0, 7.0, 8.0)
	session.setup(
		_slot_id,
		save_data,
		world,
		player_stats,
		inventory,
		factory,
		player_perks,
		item_proficiency,
		tutorial_progress,
		chest_storage,
		world_loot_state,
		restored_progress,
		chest_coordinator,
		overworld_loot,
		environment,
		pumpkin_patch,
		apple_trees,
		func() -> Vector3: return persisted_position,
	)
	var initial_snapshot := world_loot_state.snapshot()
	var dungeon_progress := restored_progress
	var initial_progress_snapshot := seeded_progress.snapshot()
	_expect(dungeon_progress.snapshot() == initial_progress_snapshot, "session did not retain dungeon progress")
	_expect(save_data.get("world_loot", null) == initial_snapshot, "session did not seed current world loot before its initial write")
	_expect(save_data.get("dungeon_progress", null) == initial_progress_snapshot, "session did not seed current dungeon progress before its initial write")
	_expect(save_data.get("player_perks", null) == player_perks.snapshot(), "session did not seed current player perks before its initial write")
	_expect(save_data.get("tutorial_progress", null) == tutorial_progress.snapshot(), "session did not seed current tutorial progress before its initial write")
	_expect(save_data.get("apple_trees", null) == apple_trees.snapshot(), "session did not seed current apple trees before its initial write")
	var initial_disk := SaveManager.load_slot(_slot_id, item_catalog)
	_expect(_saved_world_loot_matches(initial_disk, initial_snapshot, item_catalog, factory.get_next_instance_id()), "initial session write omitted current world loot")
	_expect(_saved_dungeon_progress_matches(initial_disk, initial_progress_snapshot), "initial session write omitted current dungeon progress")
	_expect(_saved_player_perks_match(initial_disk, player_perks.snapshot(), perk_rules, player_stats.get_level()), "initial session write omitted current player perks")
	_expect(_saved_apple_trees_match(initial_disk, apple_trees.snapshot()), "initial session write omitted current apple trees")
	_expect(tutorial_progress.complete_mining_tip(), "tutorial progress completion failed")
	_expect(session._pending_edit_save, "tutorial completion did not queue a debounced save")
	_expect(save_data.get("tutorial_progress", null) == tutorial_progress.snapshot(), "tutorial completion did not update current save data")
	session._edit_idle_elapsed = GameSession.EDIT_SAVE_DEBOUNCE - 0.05
	session._process(0.1)
	var tutorial_disk := SaveManager.load_slot(_slot_id, item_catalog)
	_expect(tutorial_disk.get("tutorial_progress", null) == tutorial_progress.snapshot(), "debounced save omitted tutorial completion")
	_expect(_advance_time(world_loot_state, 13.0), "world loot debounce fixture did not advance")
	_expect(dungeon_progress.begin_attempt(&"stone_story") == 1, "dungeon progress change did not advance attempt index")
	_expect(session._pending_edit_save and is_zero_approx(session._edit_idle_elapsed), "dungeon progress change did not queue a debounced save")
	overworld_loot.state_changed.emit()
	_expect(session._pending_edit_save and is_zero_approx(session._edit_idle_elapsed), "world loot state change did not queue a debounced save")
	session._edit_idle_elapsed = GameSession.EDIT_SAVE_DEBOUNCE - 0.05
	session._process(0.1)
	var debounced_snapshot := world_loot_state.snapshot()
	var debounced_progress_snapshot := dungeon_progress.snapshot()
	var debounced_disk := SaveManager.load_slot(_slot_id, item_catalog)
	_expect(not session._pending_edit_save, "world loot debounce did not commit")
	_expect(save_data.get("world_loot", null) == debounced_snapshot, "debounced save data did not snapshot current world loot")
	_expect(_saved_world_loot_matches(debounced_disk, debounced_snapshot, item_catalog, factory.get_next_instance_id()), "debounced disk save did not snapshot current world loot")
	_expect(_saved_dungeon_progress_matches(debounced_disk, debounced_progress_snapshot), "debounced disk save did not snapshot current dungeon progress")
	_expect(_saved_player_perks_match(debounced_disk, player_perks.snapshot(), perk_rules, player_stats.get_level()), "debounced disk save omitted current player perks")
	_expect(_saved_apple_trees_match(debounced_disk, apple_trees.snapshot()), "debounced disk save omitted current apple trees")
	_expect(_advance_time(world_loot_state, 7.0), "world loot shutdown fixture did not advance")
	var shutdown_completion := dungeon_progress.prepare_completion(&"stone_story")
	_expect(shutdown_completion != null and dungeon_progress.commit_prepared_completion(shutdown_completion), "shutdown dungeon progress fixture failed")
	var final_snapshot := world_loot_state.snapshot()
	var final_progress_snapshot := dungeon_progress.snapshot()
	session.shutdown("world_loot_test")
	var final_disk := SaveManager.load_slot(_slot_id, item_catalog)
	_expect(save_data.get("world_loot", null) == final_snapshot, "shutdown save data did not snapshot current world loot")
	_expect(_saved_world_loot_matches(final_disk, final_snapshot, item_catalog, factory.get_next_instance_id()), "shutdown disk save did not snapshot current world loot")
	_expect(_saved_dungeon_progress_matches(final_disk, final_progress_snapshot), "shutdown disk save did not snapshot current dungeon progress")
	_expect(_saved_player_perks_match(final_disk, player_perks.snapshot(), perk_rules, player_stats.get_level()), "shutdown disk save omitted current player perks")
	_expect(_saved_apple_trees_match(final_disk, apple_trees.snapshot()), "shutdown disk save omitted current apple trees")
	_expect(not session._pending_edit_save, "successful shutdown retained a pending save")
	overworld_loot.state_changed.emit()
	_expect(not session._pending_edit_save, "shutdown retained the world loot save connection")
	_expect(dungeon_progress.begin_attempt(&"after_shutdown") == 0, "post-shutdown progress fixture failed")
	_expect(not session._pending_edit_save, "shutdown retained the dungeon progress save connection")
	session.free()
	overworld_loot.free()
	pumpkin_patch.free()
	apple_trees.free()
	environment.free()
	world.free()
	_finish()

func _add_stack(state: WorldLootState, stack: InventoryStack, position: Vector3) -> bool:
	var prepared := state._prepare_add_stack(stack, position)
	return prepared != null and state.commit_prepared_change(prepared)

func _advance_time(state: WorldLootState, delta: float) -> bool:
	var prepared := state.prepare_advance_time(delta)
	return prepared != null and state.commit_prepared_change(prepared)

func _saved_world_loot_matches(
	save_data: Dictionary,
	expected_snapshot: Dictionary,
	item_catalog: ItemCatalog,
	next_instance_id: int,
) -> bool:
	var encoded = save_data.get("world_loot", null)
	if not encoded is Dictionary:
		return false
	var restored := WorldLootState.new(
		item_catalog,
		EquipmentInstanceFactory.new(item_catalog, next_instance_id),
	)
	return restored.restore(encoded) and restored.snapshot() == expected_snapshot

func _saved_player_perks_match(
	save_data: Dictionary,
	expected_snapshot: Dictionary,
	perk_rules: PlayerPerkRules,
	player_level: int,
) -> bool:
	var encoded = save_data.get("player_perks", null)
	if not encoded is Dictionary:
		return false
	var restored := PlayerPerks.new(perk_rules)
	return restored.restore(encoded, player_level) and restored.snapshot() == expected_snapshot

func _saved_dungeon_progress_matches(save_data: Dictionary, expected_snapshot: Dictionary) -> bool:
	var restored := DungeonProgressState.new()
	return restored.restore(save_data.get("dungeon_progress", null)) and restored.snapshot() == expected_snapshot

func _saved_apple_trees_match(save_data: Dictionary, expected_snapshot: Dictionary) -> bool:
	var encoded = save_data.get("apple_trees", null)
	var restored := AppleTreeState.new()
	return restored.restore(encoded) and restored.snapshot() == expected_snapshot

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	var cleanup_error := OK
	if not _save_path.is_empty() and FileAccess.file_exists(_save_path):
		cleanup_error = DirAccess.remove_absolute(_save_path)
	_expect(cleanup_error == OK and (_save_path.is_empty() or not FileAccess.file_exists(_save_path)), "temporary save cleanup failed")
	if _errors.is_empty():
		print("GAME_SESSION_WORLD_LOOT PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)
