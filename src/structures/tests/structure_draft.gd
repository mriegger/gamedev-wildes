extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	_test_size_contract()
	_test_block_and_torch_transactions()
	_test_indexed_torch_transactions()
	_test_copied_queries()
	_test_bounded_chunk_queries()
	if _failures.is_empty():
		print("STRUCTURE_DRAFT PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_size_contract() -> void:
	_expect(StructureDraft.create() != null, "default draft creation failed")
	_expect(StructureDraft.create().get_size() == StructureDraft.DEFAULT_SIZE, "default draft size changed")
	_expect(StructureDraft.is_valid_size(Vector3i(64, 64, 64)), "maximum draft size was rejected")
	_expect(not StructureDraft.is_valid_size(Vector3i(65, 1, 1)), "oversized draft axis was accepted")
	_expect(not StructureDraft.is_valid_size(Vector3i.ZERO), "zero draft size was accepted")
	_expect(StructureDraft.create(Vector3i(65, 1, 1)) == null, "invalid draft size was created")

func _test_block_and_torch_transactions() -> void:
	var draft := StructureDraft.create(Vector3i(4, 4, 4))
	_expect(draft != null and not draft.is_dirty(), "draft initial state is invalid")
	var original := draft.snapshot_cells()
	_expect(not draft.try_place_block(Vector3i(-1, 0, 0), BlockId.Type.DIRT).succeeded, "out-of-bounds placement succeeded")
	_expect(not draft.try_place_block(Vector3i.ZERO, StructureCell.VOID).succeeded, "VOID placement succeeded")
	_expect(draft.snapshot_cells() == original and not draft.is_dirty(), "rejected placement mutated the draft")
	var support := Vector3i(1, 1, 1)
	var torch_cell := support + Vector3i.RIGHT
	var placed := draft.try_place_block(support, BlockId.Type.STONE)
	_expect(placed.succeeded and placed.changed_cells == [support], "block placement failed")
	_expect(not draft.try_place_block(support, BlockId.Type.DIRT).succeeded, "occupied cell accepted another block")
	var torch_change := draft.try_place_torch(torch_cell, Vector3i.LEFT)
	_expect(torch_change.succeeded and torch_change.added_torches.size() == 1, "torch placement failed")
	_expect(not draft.try_place_torch(torch_cell, Vector3i.LEFT).succeeded, "occupied torch cell accepted another torch")
	_expect(not draft.try_remove_block(Vector3i.ZERO).succeeded, "AIR removal succeeded")
	var removed := draft.try_remove_block(support)
	_expect(removed.succeeded and removed.removed_torch_cells == [torch_cell], "support removal did not report its torch removal")
	_expect(draft.get_cell(support) == StructureCell.AIR and draft.get_torches().is_empty(), "support and torch removal did not commit atomically")
	_expect(draft.is_dirty(), "successful edits did not dirty the draft")

func _test_indexed_torch_transactions() -> void:
	var draft := StructureDraft.create(Vector3i(5, 5, 5))
	var support := Vector3i(2, 2, 2)
	var attached: Array[Vector3i] = [
		support + Vector3i.LEFT,
		support + Vector3i.FORWARD,
		support + Vector3i.BACK,
		support + Vector3i.RIGHT,
	]
	_expect(draft.try_place_block(support, BlockId.Type.STONE).succeeded, "indexed torch support setup failed")
	for cell in attached:
		var change := draft.try_place_torch(cell, support - cell)
		_expect(change.succeeded and change.added_torches.size() == 1, "indexed torch placement failed at %s" % cell)
		_expect(draft.has_torch(cell), "indexed torch query missed %s" % cell)
	var unrelated_support := Vector3i(4, 2, 4)
	var unrelated_torch := Vector3i(4, 2, 3)
	_expect(draft.try_place_block(unrelated_support, BlockId.Type.DIRT).succeeded, "unrelated torch support setup failed")
	_expect(draft.try_place_torch(unrelated_torch, Vector3i.BACK).succeeded, "unrelated torch setup failed")
	var removed := draft.try_remove_block(support)
	_expect(removed.succeeded and removed.removed_torch_cells == attached, "support removal did not return its indexed torches deterministically")
	for cell in attached:
		_expect(not draft.has_torch(cell), "support removal retained indexed torch %s" % cell)
	_expect(draft.has_torch(unrelated_torch), "support removal removed a torch owned by another support")

func _test_copied_queries() -> void:
	var draft := StructureDraft.create(Vector3i(3, 3, 3))
	var support := Vector3i(1, 1, 1)
	var torch_cell := support + Vector3i.RIGHT
	_expect(draft.try_place_block(support, BlockId.Type.STONE).succeeded, "copied-query block setup failed")
	var placement := draft.try_place_torch(torch_cell, Vector3i.LEFT)
	_expect(placement.succeeded, "copied-query torch setup failed")
	var copied_cells := draft.snapshot_cells()
	copied_cells[StructureCell.index_of(support, draft.get_size())] = BlockId.Type.DIRT
	_expect(draft.get_cell(support) == BlockId.Type.STONE, "cell snapshot exposed mutable draft state")
	var copied_torches := draft.get_torches()
	copied_torches[0].cell = Vector3i.ZERO
	_expect(draft.get_torches()[0].cell == torch_cell, "torch query exposed mutable draft state")
	placement.added_torches[0].cell = Vector3i.ZERO
	_expect(draft.has_torch(torch_cell), "change result exposed mutable draft torch state")

func _test_bounded_chunk_queries() -> void:
	var draft := StructureDraft.create(Vector3i(64, 64, 64))
	var interior_chunk := Vector3i.ONE
	var copied := draft.copy_cells_for_chunk(interior_chunk, 16)
	_expect(copied.size() == 18 * 18 * 18, "interior chunk query did not copy its exact one-cell halo")
	_expect(copied.size() < StructureDraft.MAX_CELL_COUNT, "chunk query copied the full maximum plot")
	var inside := Vector3i(16, 16, 16)
	var halo := Vector3i(15, 15, 15)
	_expect(copied.has(inside) and copied.has(halo), "chunk query omitted owner or halo cells")
	_expect(not copied.has(Vector3i(14, 15, 15)), "chunk query copied cells beyond its halo")
	copied[inside] = BlockId.Type.STONE
	_expect(draft.get_cell(inside) == StructureCell.AIR, "chunk query exposed mutable draft state")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
