extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_test_owner_and_stale_guards(catalog)
	_test_content_guards(catalog)
	_test_bounded_transaction_history(catalog)
	_test_silent_commit_and_notification(catalog)
	_test_batch_commit(catalog)
	_test_mine_and_replace_preparation(catalog)
	if _errors.is_empty():
		print("VOXEL_WORLD_TRANSACTIONS PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_owner_and_stale_guards(catalog: BlockCatalog) -> void:
	var first := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var second := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var position := Vector3i(2, 8, 2)
	var cross_owner := first.prepare_place_block(position, BlockId.Type.DIRT)
	_expect(cross_owner != null, "valid placement did not prepare")
	_expect(not second.can_commit_prepared_change(cross_owner), "cross-owner prepared change passed validation")
	_expect(not second._commit_prepared_change(cross_owner), "cross-owner prepared change committed")
	_expect(second.get_block_id_at(position) == BlockId.Type.AIR, "cross-owner commit mutated the wrong world")

	var stale := first.prepare_place_block(position, BlockId.Type.DIRT)
	_expect(stale != null, "stale placement fixture did not prepare")
	_expect(VoxelWorldTestFixture.commit_place(first, position, BlockId.Type.STONE) != null, "stale placement fixture mutation failed")
	_expect(not first.can_commit_prepared_change(stale), "same-cell stale change passed validation")
	_expect(not first._commit_prepared_change(stale), "same-cell stale change committed")
	_expect(first.get_block_id_at(position) == BlockId.Type.STONE, "stale change replaced committed world state")

func _test_content_guards(catalog: BlockCatalog) -> void:
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var target := Vector3i(4, 8, 4)
	var unrelated := Vector3i(12, 8, 12)
	var prepared := world.prepare_place_block(target, BlockId.Type.DIRT)
	_expect(prepared != null, "unrelated-edit placement did not prepare")
	_expect(VoxelWorldTestFixture.commit_place(world, unrelated, BlockId.Type.STONE) != null, "unrelated world edit failed")
	_expect(world.can_commit_prepared_change(prepared), "unrelated world edit invalidated a prepared change")
	_expect(world._commit_prepared_change(prepared), "prepared change did not commit after an unrelated edit")

	var aba_target := Vector3i(5, 8, 5)
	var aba := world.prepare_place_block(aba_target, BlockId.Type.DIRT)
	_expect(aba != null, "ABA placement did not prepare")
	_expect(world.get_revision(aba_target) == 0, "ABA fixture did not begin at revision zero")
	_expect(VoxelWorldTestFixture.commit_place(world, aba_target, BlockId.Type.STONE) != null, "ABA placement fixture failed")
	var aba_mine := VoxelWorldTestFixture.commit_mine(world, aba_target)
	_expect(aba_mine != null and aba_mine.get_edits().size() == 1, "ABA mining fixture failed")
	_expect(world.get_revision(aba_target) == 0, "mined placed block did not preserve legacy revision reset")
	_expect(world.get_block_id_at(aba_target) == BlockId.Type.AIR, "ABA fixture did not return to AIR")
	_expect(not world.can_commit_prepared_change(aba), "ABA state transition remained committable")
	_expect(not world._commit_prepared_change(aba), "ABA prepared change committed")
	_expect(world.get_block_id_at(aba_target) == BlockId.Type.AIR, "rejected ABA change mutated world state")

	var direct_target := Vector3i(6, 8, 6)
	var direct_content := world.prepare_place_block(direct_target, BlockId.Type.DIRT)
	_expect(direct_content != null, "direct-content placement did not prepare")
	world.height_map_dict[Vector2i(direct_target.x, direct_target.z)] = direct_target.y
	world.type_map_dict[Vector2i(direct_target.x, direct_target.z)] = BlockId.Type.STONE
	_expect(not world.can_commit_prepared_change(direct_content), "exact content guard accepted a changed target block")

	var support := Vector3i(7, 8, 7)
	var first_torch := support + Vector3i.RIGHT
	var second_torch := support + Vector3i.BACK
	_expect(VoxelWorldTestFixture.commit_place(world, support, BlockId.Type.STONE) != null, "torch support fixture failed")
	_expect(VoxelWorldTestFixture.commit_place(world, first_torch, BlockId.Type.TORCH, Vector3i.LEFT) != null, "first torch fixture failed")
	var mine_support := world.prepare_mine_block(support)
	_expect(mine_support != null, "support mining did not prepare")
	_expect(VoxelWorldTestFixture.commit_place(world, second_torch, BlockId.Type.TORCH, Vector3i.FORWARD) != null, "dependent torch placement failed")
	_expect(not world.can_commit_prepared_change(mine_support), "new attached torch did not invalidate prepared support mining")
	var attachment_content := world.prepare_mine_block(support)
	_expect(attachment_content != null, "attachment-content mining did not prepare")
	world.torch_attachments[first_torch] = Vector3i.RIGHT
	_expect(not world.can_commit_prepared_change(attachment_content), "exact content guard accepted a changed torch attachment")

	var one_shot := world.prepare_place_block(Vector3i(10, 8, 10), BlockId.Type.DIRT)
	_expect(one_shot != null and world._commit_prepared_change(one_shot), "one-shot placement did not commit")
	_expect(not world.can_commit_prepared_change(one_shot), "committed prepared change remained valid")
	_expect(not world._commit_prepared_change(one_shot), "prepared change committed twice")

func _test_bounded_transaction_history(catalog: BlockCatalog) -> void:
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var target := Vector3i(0, 8, 0)
	var prepared := world.prepare_place_block(target, BlockId.Type.DIRT)
	_expect(prepared != null, "history rollover placement did not prepare")
	for index in range(VoxelWorld.MAXIMUM_TRANSACTION_MUTATION_HISTORY + 1):
		var position := Vector3i(index + 32, 8, 32)
		_expect(VoxelWorldTestFixture.commit_place(world, position, BlockId.Type.STONE) != null, "history rollover placement %d failed" % index)
	_expect(world._transaction_history_positions.size() == VoxelWorld.MAXIMUM_TRANSACTION_MUTATION_HISTORY, "transaction position history exceeded its bound")
	_expect(world._transaction_history_sequences.size() == VoxelWorld.MAXIMUM_TRANSACTION_MUTATION_HISTORY, "transaction sequence history exceeded its bound")
	_expect(world._latest_transaction_sequences.size() <= VoxelWorld.MAXIMUM_TRANSACTION_MUTATION_HISTORY, "transaction cell index exceeded its bound")
	_expect(not world.can_commit_prepared_change(prepared), "pre-eviction prepared change remained committable")
	_expect(not world._commit_prepared_change(prepared), "pre-eviction prepared change committed")
	_expect(world.get_block_id_at(target) == BlockId.Type.AIR, "rejected pre-eviction change mutated world state")

func _test_silent_commit_and_notification(catalog: BlockCatalog) -> void:
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var position := Vector3i(6, 8, 6)
	var observed: Array[BlockEdit] = []
	world.block_edit_committed.connect(func(edit: BlockEdit) -> void: observed.append(edit))
	var prepared := world.prepare_place_block(position, BlockId.Type.DIRT)
	_expect(prepared != null, "silent placement did not prepare")
	var exposed := prepared.get_primary_edit()
	exposed.pos = Vector3i(100, 8, 100)
	_expect(world._commit_prepared_change(prepared, false), "silent placement did not commit")
	_expect(world.get_block_id_at(position) == BlockId.Type.DIRT, "silent commit did not mutate world state")
	_expect(observed.is_empty(), "silent commit emitted a block edit")
	_expect(world._notify_prepared_change(prepared), "silent commit notification failed")
	_expect(observed.size() == 1, "silent commit notification count was not one")
	if observed.size() == 1:
		_expect(observed[0].pos == position, "prepared edit query exposed mutable notification state")
	_expect(not world._notify_prepared_change(prepared), "prepared change notified twice")
	_expect(observed.size() == 1, "duplicate notification emitted another block edit")

func _test_batch_commit(catalog: BlockCatalog) -> void:
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var first_position := Vector3i(2, 8, 2)
	var second_position := Vector3i(3, 8, 2)
	var first := world.prepare_place_block(first_position, BlockId.Type.LOG)
	var second := world.prepare_place_block(second_position, BlockId.Type.LEAVES)
	var notifications_observed_after_commit: Array[bool] = []
	var observer := func(_edit: BlockEdit) -> void:
		notifications_observed_after_commit.append(
			world.get_block_id_at(first_position) == BlockId.Type.LOG
			and world.get_block_id_at(second_position) == BlockId.Type.LEAVES
		)
	world.block_edit_committed.connect(observer)
	_expect(world.commit_prepared_changes([first, second]), "valid prepared batch did not commit")
	world.block_edit_committed.disconnect(observer)
	_expect(notifications_observed_after_commit == [true, true], "prepared batch notified before all edits committed")
	var duplicate_position := Vector3i(5, 8, 5)
	var duplicate_first := world.prepare_place_block(duplicate_position, BlockId.Type.DIRT)
	var duplicate_second := world.prepare_place_block(duplicate_position, BlockId.Type.STONE)
	_expect(not world.commit_prepared_changes([duplicate_first, duplicate_second]), "overlapping prepared batch committed")
	_expect(world.get_block_id_at(duplicate_position) == BlockId.Type.AIR, "rejected overlapping batch changed world state")
	var support_position := Vector3i(7, 8, 7)
	_expect(VoxelWorldTestFixture.commit_place(world, support_position, BlockId.Type.STONE) != null, "batch dependency support fixture failed")
	var torch := world.prepare_place_block(support_position + Vector3i.RIGHT, BlockId.Type.TORCH, Vector3i.LEFT)
	var mine_support := world.prepare_mine_block(support_position)
	_expect(not world.commit_prepared_changes([torch, mine_support]), "dependent prepared batch committed")
	_expect(world.get_block_id_at(support_position) == BlockId.Type.STONE, "rejected dependent batch mined its support")

func _test_mine_and_replace_preparation(catalog: BlockCatalog) -> void:
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	var position := Vector3i(9, 8, 9)
	_expect(VoxelWorldTestFixture.commit_place(world, position, BlockId.Type.STONE) != null, "mine fixture placement failed")
	var mine := world.prepare_mine_block(position)
	_expect(mine != null, "valid mining did not prepare")
	if mine != null:
		var edits := mine.get_edits()
		_expect(edits.size() == 1 and edits[0].old_id == BlockId.Type.STONE, "prepared mining did not expose the exact edit")
		_expect(world._commit_prepared_change(mine), "prepared mining did not commit")
	_expect(world.get_block_id_at(position) == BlockId.Type.AIR, "prepared mining left the block in world state")
	_expect(VoxelWorldTestFixture.commit_place(world, position, BlockId.Type.GRASS) != null, "replace fixture placement failed")
	var replace := world.prepare_replace_block(position, BlockId.Type.GRASS, BlockId.Type.FARMLAND_DRY)
	_expect(replace != null, "valid replacement did not prepare")
	if replace != null:
		_expect(world._commit_prepared_change(replace), "prepared replacement did not commit")
	_expect(world.get_block_id_at(position) == BlockId.Type.FARMLAND_DRY, "prepared replacement did not update world state")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
