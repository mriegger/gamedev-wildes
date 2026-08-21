extends SceneTree

const TEST_SEED: int = 727168808

var _errors: Array[String] = []
var _game: Game
var _world: WorldController
var _session_ready: bool = false
var _world_generation_done: bool = false
var _world_was_inert_at_generation: bool = false
var _slot_id: int
var _covered_foliage_count: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_slot_id = 1000000000 + OS.get_process_id()
	while SaveManager.slot_exists(_slot_id):
		_slot_id += 1
	var save_data := SaveManager.create_new_world(_slot_id, TEST_SEED, "Foliage Join Test")
	var game_scene := load("res://game/game.tscn") as PackedScene
	_game = game_scene.instantiate() as Game
	_world = _game.get_node("Overworld/World") as WorldController
	_game.configure_session(_slot_id, save_data, GameSettings.new())
	_world.generation_progress.connect(_on_generation_progress)
	_game.session_ready.connect(_on_session_ready)
	root.add_child(_game)
	var deadline := Time.get_ticks_msec() + 30000
	while not _session_ready and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(_session_ready, "new-world join did not reach session_ready")
	_expect(_world_generation_done, "world generation never reached done")
	_expect(_world_was_inert_at_generation, "world processing started before player injection")
	if _session_ready:
		_expect(_world.is_processing(), "world processing did not start after player injection")
		_expect(_world._streaming_focus == _game.player, "world retained the wrong streaming dependency")
		_expect(_game.pumpkin_patch.has_patch(), "new world did not create a pumpkin patch")
		_validate_pumpkin_footprint()
		_validate_startup_save()
		_game._save_and_request_main_menu()
	_game.queue_free()
	await process_frame
	await process_frame
	SaveManager.delete_slot(_slot_id)
	if _errors.is_empty():
		print("GAME_JOIN_INTEGRATION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _on_generation_progress(stage: String, _percent: float, _details: String) -> void:
	if stage != "done":
		return
	_world_generation_done = true
	_world_was_inert_at_generation = not _world.is_processing() and _world._streaming_focus == null
	_world.voxel_model.foliage_visibility_changed.connect(_on_foliage_visibility_changed)

func _on_session_ready() -> void:
	_session_ready = true

func _on_foliage_visibility_changed(cells: Array[Vector3i]) -> void:
	for position in cells:
		if _world.voxel_model.has_generated_foliage(position):
			_covered_foliage_count += 1

func _validate_pumpkin_footprint() -> void:
	var snapshot := _game.pumpkin_patch.snapshot()
	var encoded_origin := snapshot.get("origin", []) as Array
	_expect(encoded_origin.size() == 3, "pumpkin patch omitted its origin")
	if encoded_origin.size() != 3:
		return
	var origin := Vector3i(int(encoded_origin[0]), int(encoded_origin[1]), int(encoded_origin[2]))
	var removed := _world.voxel_model.snapshot_block_edits()["removed"] as Dictionary
	var reserved_count := 0
	var persisted_count := 0
	for x_offset in range(PumpkinPatchCoordinator.PATCH_WIDTH):
		for z_offset in range(PumpkinPatchCoordinator.PATCH_DEPTH):
			var position := origin + Vector3i(x_offset, 1, z_offset)
			_expect(_world.voxel_model.get_block_id_at(position) == BlockId.Type.AIR, "pumpkin footprint retained an occupied cell")
			reserved_count += int(_world.voxel_model.is_foliage_clearance_reserved(position))
			persisted_count += int(removed.has(position))
	_expect(reserved_count == PumpkinPatchState.TILE_COUNT, "pumpkin footprint was not fully reserved")
	_expect(persisted_count == 0, "pumpkin clearance fabricated persistent block removals")
	_expect(_covered_foliage_count > 0, "join fixture did not exercise foliage-covered pumpkin soil")

func _validate_startup_save() -> void:
	var saved := SaveManager.load_slot(_slot_id, _game.item_catalog)
	_expect(saved.get("exists", false), "session startup did not write the save slot")
	var saved_patch = saved.get("pumpkin_patch", null)
	_expect(saved_patch is Dictionary, "session startup omitted the pumpkin snapshot")
	if not saved_patch is Dictionary:
		return
	var saved_patch_data := saved_patch as Dictionary
	var runtime_snapshot := _game.pumpkin_patch.snapshot()
	_expect(saved_patch_data.get("present", false), "startup save stored an absent pumpkin patch")
	_expect(saved_patch_data.get("growth_state_ids", []) == runtime_snapshot.get("growth_state_ids", []), "startup save changed pumpkin growth state")
	var encoded_origin := saved_patch_data.get("origin", []) as Array
	_expect(encoded_origin.size() == 3, "startup save omitted the pumpkin origin")
	if encoded_origin.size() != 3:
		return
	var origin := Vector3i(int(encoded_origin[0]), int(encoded_origin[1]), int(encoded_origin[2]))
	var persisted_world := SaveManager.decode_world_state(saved) as WorldState
	_expect(persisted_world != null, "startup save did not decode its world state")
	if persisted_world == null:
		return
	var clearance_removals := 0
	for x_offset in range(PumpkinPatchCoordinator.PATCH_WIDTH):
		for z_offset in range(PumpkinPatchCoordinator.PATCH_DEPTH):
			var position := origin + Vector3i(x_offset, 1, z_offset)
			clearance_removals += int(persisted_world.removed_blocks.has(position))
	_expect(clearance_removals == 0, "startup save serialized derived pumpkin clearance as terrain edits")
	_expect(saved.get("player_position", null) == null, "session startup persisted the temporary spawn lift")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
