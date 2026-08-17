extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	_test_size_contract()
	_test_block_and_torch_transactions()
	_test_indexed_torch_transactions()
	_test_copied_queries()
	_test_restore_and_binding()
	_test_module_restore_and_protection()
	_test_malformed_module_definitions()
	_test_bounded_chunk_queries()
	if _failures.is_empty():
		print("STRUCTURE_DRAFT PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_size_contract() -> void:
	_expect(StructureDraft.create_generic() != null and StructureDraft.create_generic().get_format() == StructureDraft.Format.GENERIC_STRUCTURE, "default generic draft creation failed")
	_expect(StructureDraft.create_generic().get_size() == StructureDefinition.DEFAULT_SIZE, "default draft size changed")
	_expect(StructureDefinition.is_valid_size(Vector3i(64, 64, 64)), "maximum draft size was rejected")
	_expect(not StructureDefinition.is_valid_size(Vector3i(65, 1, 1)), "oversized draft axis was accepted")
	_expect(not StructureDefinition.is_valid_size(Vector3i.ZERO), "zero draft size was accepted")
	_expect(StructureDraft.create_generic(Vector3i(65, 1, 1)) == null, "invalid draft size was created")
	var module := StructureDraft.create_level_module()
	_expect(module != null and module.get_format() == StructureDraft.Format.LEVEL_MODULE, "default Level Module draft creation failed")
	_expect(module != null and module.get_size() == Vector3i(7, 4, 7), "default Level Module size changed")
	_expect(StructureDraft.is_valid_level_module_size(Vector3i(96, 16, 96)), "maximum Level Module size was rejected")
	_expect(not StructureDraft.is_valid_level_module_size(Vector3i(97, 16, 96)), "oversized Level Module length was accepted")
	_expect(not StructureDraft.is_valid_level_module_size(Vector3i(96, 17, 96)), "oversized Level Module height was accepted")
	_expect(not StructureDraft.is_valid_level_module_size(Vector3i.ZERO), "zero Level Module size was accepted")

func _test_block_and_torch_transactions() -> void:
	var draft := StructureDraft.create_generic(Vector3i(4, 4, 4))
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
	var draft := StructureDraft.create_generic(Vector3i(5, 5, 5))
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
	_expect(draft.try_remove_torch(attached[1]).succeeded, "indexed torch order removal failed")
	_expect(draft.try_place_torch(attached[1], support - attached[1]).succeeded, "indexed torch order re-add failed")
	var reordered_torches := draft.get_torches()
	_expect(
		reordered_torches.map(func(torch: StructureTorchDefinition) -> Vector3i: return torch.cell) == [attached[0], attached[2], attached[3], attached[1]],
		"indexed torch removal and re-add did not preserve insertion order",
	)
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
	var draft := StructureDraft.create_generic(Vector3i(3, 3, 3))
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

func _test_restore_and_binding() -> void:
	var definition := StructureDefinition.new()
	definition.format_version = StructureDefinition.CURRENT_FORMAT_VERSION
	definition.structure_id = &"restored_structure"
	definition.size = Vector3i(2, 2, 2)
	definition.cells.resize(8)
	definition.cells.fill(StructureCell.AIR)
	definition.cells[StructureCell.index_of(Vector3i.ZERO, definition.size)] = BlockId.Type.STONE
	var torch := StructureTorchDefinition.new()
	torch.cell = Vector3i(1, 0, 0)
	torch.support_direction = Vector3i.LEFT
	definition.torches.append(torch)
	var source_path := ProjectSettings.globalize_path("res://../restored_structure.tres").simplify_path()
	var draft := StructureDraft.restore_structure(definition, source_path)
	_expect(draft != null and draft.is_bound() and not draft.is_dirty(), "valid definition did not restore as a clean bound draft")
	if draft == null:
		return
	_expect(draft.get_format() == StructureDraft.Format.GENERIC_STRUCTURE and draft.get_identifier() == definition.structure_id and draft.get_source_path() == source_path, "restored binding changed its type, ID, or source path")
	definition.cells[0] = BlockId.Type.DIRT
	definition.torches[0].cell = Vector3i.ZERO
	_expect(draft.get_cell(Vector3i.ZERO) == BlockId.Type.STONE and draft.has_torch(Vector3i(1, 0, 0)), "restored draft retained mutable definition state")
	_expect(draft.try_remove_torch(Vector3i(1, 0, 0)).succeeded and draft.is_dirty(), "restored draft edit did not become dirty")
	_expect(not draft.accept_export(&"renamed_structure", source_path), "bound draft accepted a renamed ID")
	_expect(not draft.accept_export(&"restored_structure", source_path.get_base_dir().path_join("other.tres")), "bound draft accepted another source path")
	_expect(draft.accept_export(&"restored_structure", source_path) and not draft.is_dirty(), "bound draft did not accept its own export")

func _test_module_restore_and_protection() -> void:
	var definition := _make_module_definition(&"restored_module")
	_expect(definition.validate(), "valid Level Module fixture was rejected")
	var source_path := ProjectSettings.globalize_path("res://../restored_module.tres").simplify_path()
	var draft := StructureDraft.restore_level_module(definition, source_path)
	_expect(draft != null and draft.get_format() == StructureDraft.Format.LEVEL_MODULE, "valid Level Module did not restore with its type")
	if draft == null:
		return
	_expect(draft.is_bound() and not draft.is_dirty() and draft.get_identifier() == &"restored_module" and draft.get_source_path() == source_path, "restored Level Module binding or clean state changed")
	_expect(draft.get_size() == definition.size and is_equal_approx(draft.get_weight(), 150.25), "restored Level Module size or weight changed")
	_expect(draft.get_cell(Vector3i(0, 3, 0)) == StructureCell.VOID, "restored Level Module changed a VOID cell")
	var sockets := draft.get_sockets()
	_expect(sockets.size() == 2 and sockets[0].socket_id == &"north_entry" and sockets[1].socket_id == &"south_exit", "restored Level Module changed socket order")
	var torches := draft.get_torches()
	_expect(torches.size() == 2 and torches[0].cell == Vector3i(3, 2, 3) and torches[1].cell == Vector3i(1, 2, 3), "restored Level Module changed torch order")
	_expect(torches[0].support_direction == Vector3i.RIGHT and torches[1].support_direction == Vector3i.LEFT, "restored Level Module changed torch directions")
	_expect(draft.get_spawn_marker().cell == Vector3i(1, 1, 2) and draft.get_spawn_marker().facing == LevelSocketDefinition.Direction.EAST, "restored Level Module changed its spawn marker")
	_expect(draft.get_return_door_marker().cell == Vector3i(3, 1, 2) and draft.get_return_door_marker().facing == LevelSocketDefinition.Direction.WEST, "restored Level Module changed its return marker")
	definition.cells[StructureCell.index_of(Vector3i(4, 0, 4), definition.size)] = BlockId.Type.DIRT
	definition.weight = 2.0
	definition.sockets[0].socket_id = &"mutated"
	definition.torches[0].cell = Vector3i.ZERO
	definition.spawn_marker.cell = Vector3i.ZERO
	sockets[0].socket_id = &"query_mutation"
	torches[0].cell = Vector3i.ZERO
	var copied_spawn := draft.get_spawn_marker()
	copied_spawn.cell = Vector3i.ZERO
	_expect(draft.get_cell(Vector3i(4, 0, 4)) == BlockId.Type.STONE and is_equal_approx(draft.get_weight(), 150.25), "restored Level Module retained mutable definition cells or weight")
	_expect(draft.get_sockets()[0].socket_id == &"north_entry" and draft.get_torches()[0].cell == Vector3i(3, 2, 3), "Level Module metadata query exposed sockets or torches")
	_expect(draft.get_spawn_marker().cell == Vector3i(1, 1, 2), "Level Module marker query exposed mutable state")
	var required_air: Array[Vector3i] = [
		Vector3i(2, 1, 0),
		Vector3i(2, 2, 0),
		Vector3i(2, 1, 1),
		Vector3i(2, 2, 1),
		Vector3i(2, 1, 4),
		Vector3i(2, 2, 4),
		Vector3i(2, 1, 3),
		Vector3i(2, 2, 3),
		Vector3i(1, 1, 2),
		Vector3i(1, 2, 2),
		Vector3i(3, 1, 2),
		Vector3i(3, 2, 2),
	]
	for cell in required_air:
		_expect(not draft.can_place_block(cell, BlockId.Type.DIRT), "metadata-required AIR placement query accepted %s" % cell)
		_expect(not draft.try_place_block(cell, BlockId.Type.DIRT).succeeded, "metadata-required AIR accepted a block at %s" % cell)
	for cell in [Vector3i(2, 0, 0), Vector3i(2, 0, 4), Vector3i(1, 0, 2), Vector3i(3, 0, 2)]:
		_expect(not draft.try_remove_block(cell).succeeded, "metadata-required solid accepted removal at %s" % cell)
	_expect(not draft.is_dirty(), "rejected metadata edits dirtied the Level Module draft")
	_expect(draft.try_place_block(Vector3i(4, 3, 4), BlockId.Type.DIRT).succeeded, "unrelated Level Module placement was rejected")
	_expect(draft.try_remove_block(Vector3i(4, 0, 4)).succeeded, "unrelated Level Module removal was rejected")
	_expect(draft.is_dirty(), "unrelated Level Module edits did not dirty the draft")
	_expect(not draft.has_method("try_set_void") and not draft.has_method("try_add_socket") and not draft.has_method("try_set_markers") and not draft.has_method("try_set_weight"), "Level Module draft exposed metadata authoring commands")

func _test_malformed_module_definitions() -> void:
	var output: Array = []
	var exit_code := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://structures/tests/level_module_definition_malformed_probe.gd"],
		output,
		true,
	)
	var text := "\n".join(PackedStringArray(output))
	_expect(exit_code == 0, "malformed Level Module probe exited %d" % exit_code)
	_expect(text.contains("LEVEL_MODULE_DEFINITION_MALFORMED PASS"), "malformed Level Module probe did not reject every invalid resource")

func _test_bounded_chunk_queries() -> void:
	var draft := StructureDraft.create_generic(Vector3i(64, 64, 64))
	var interior_chunk := Vector3i.ONE
	var copied := draft.copy_cells_for_chunk(interior_chunk, 16)
	_expect(copied.size() == 18 * 18 * 18, "interior chunk query did not copy its exact one-cell halo")
	_expect(copied.size() < StructureDefinition.MAX_CELL_COUNT, "chunk query copied the full maximum plot")
	var inside := Vector3i(16, 16, 16)
	var halo := Vector3i(15, 15, 15)
	_expect(copied.has(inside) and copied.has(halo), "chunk query omitted owner or halo cells")
	_expect(not copied.has(Vector3i(14, 15, 15)), "chunk query copied cells beyond its halo")
	copied[inside] = BlockId.Type.STONE
	_expect(draft.get_cell(inside) == StructureCell.AIR, "chunk query exposed mutable draft state")

func _make_module_definition(identifier: StringName) -> LevelModuleDefinition:
	var definition := LevelModuleDefinition.new()
	definition.module_id = identifier
	definition.size = Vector3i(5, 4, 5)
	definition.weight = 150.25
	definition.cells.resize(definition.size.x * definition.size.y * definition.size.z)
	definition.cells.fill(StructureCell.AIR)
	for cell in [
		Vector3i(2, 0, 0),
		Vector3i(2, 0, 4),
		Vector3i(1, 0, 2),
		Vector3i(3, 0, 2),
		Vector3i(4, 2, 3),
		Vector3i(0, 2, 3),
		Vector3i(4, 0, 4),
	]:
		definition.cells[StructureCell.index_of(cell, definition.size)] = BlockId.Type.STONE
	definition.cells[StructureCell.index_of(Vector3i(0, 3, 0), definition.size)] = StructureCell.VOID
	var north := LevelSocketDefinition.new()
	north.socket_id = &"north_entry"
	north.cell = Vector3i(2, 1, 0)
	north.direction = LevelSocketDefinition.Direction.NORTH
	definition.sockets.append(north)
	var south := LevelSocketDefinition.new()
	south.socket_id = &"south_exit"
	south.cell = Vector3i(2, 1, 4)
	south.direction = LevelSocketDefinition.Direction.SOUTH
	definition.sockets.append(south)
	var east_torch := LevelTorchDefinition.new()
	east_torch.cell = Vector3i(3, 2, 3)
	east_torch.wall_direction = LevelSocketDefinition.Direction.EAST
	definition.torches.append(east_torch)
	var west_torch := LevelTorchDefinition.new()
	west_torch.cell = Vector3i(1, 2, 3)
	west_torch.wall_direction = LevelSocketDefinition.Direction.WEST
	definition.torches.append(west_torch)
	var spawn := LevelMarkerDefinition.new()
	spawn.cell = Vector3i(1, 1, 2)
	spawn.facing = LevelSocketDefinition.Direction.EAST
	definition.spawn_marker = spawn
	var return_marker := LevelMarkerDefinition.new()
	return_marker.cell = Vector3i(3, 1, 2)
	return_marker.facing = LevelSocketDefinition.Direction.WEST
	definition.return_door_marker = return_marker
	return definition

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
