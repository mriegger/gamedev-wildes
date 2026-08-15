extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	_test_size_contract()
	_test_block_and_torch_transactions()
	_test_indexed_torch_transactions()
	_test_copied_queries()
	_test_restore_and_binding()
	_test_module_restore_and_protection()
	_test_module_authoring_transactions()
	_test_variable_connection_aperture()
	_test_four_way_room_connections()
	_test_requirement_reference_counts()
	_test_module_authoring_snapshot()
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
	var rejected_void := draft.try_set_void(Vector3i.ZERO)
	_expect(not rejected_void.succeeded and draft.snapshot_cells() == original and not draft.is_dirty(), "generic VOID rejection mutated the draft")
	_expect(not draft.try_set_socket_unused_fill_block(&"missing", BlockId.Type.STONE).succeeded, "generic draft accepted socket fill metadata")
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
	_expect(sockets[0].unused_fill_block_id == BlockId.Type.MOSSY_STONE_BRICKS and sockets[1].unused_fill_block_id == StructureCell.AIR, "restored Level Module changed socket fill blocks")
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
	_expect(draft.try_place_block(Vector3i(4, 3, 3), BlockId.Type.DIRT).succeeded, "unrelated Level Module placement was rejected")
	_expect(draft.try_remove_block(Vector3i(4, 0, 4)).succeeded, "unrelated Level Module removal was rejected")
	_expect(draft.is_dirty(), "unrelated Level Module edits did not dirty the draft")

func _test_module_authoring_transactions() -> void:
	var generic := StructureDraft.create_generic(Vector3i(3, 3, 3))
	_expect(not generic.try_set_void(Vector3i.ZERO).succeeded, "generic draft accepted VOID")
	_expect(not generic.try_add_socket(Vector3i.ZERO, LevelSocketDefinition.Direction.NORTH).succeeded, "generic draft accepted a socket")
	_expect(not generic.try_set_markers(Vector3i.ZERO, LevelSocketDefinition.Direction.NORTH, Vector3i.ONE, LevelSocketDefinition.Direction.SOUTH).succeeded, "generic draft accepted markers")
	_expect(not generic.try_set_weight(2.0).succeeded and not generic.is_dirty(), "generic draft accepted module metadata")
	var clean_module := StructureDraft.create_level_module(Vector3i(5, 4, 5))
	var clean_cells := clean_module.snapshot_cells()
	_expect(not clean_module.try_add_socket(Vector3i(2, 1, 0), LevelSocketDefinition.Direction.NORTH).succeeded, "clean module accepted a socket without a floor")
	_expect(not clean_module.try_set_markers(Vector3i(1, 1, 1), LevelSocketDefinition.Direction.NORTH, Vector3i(3, 1, 3), LevelSocketDefinition.Direction.SOUTH).succeeded, "clean module accepted markers without floors")
	_expect(not clean_module.try_set_weight(0.0).succeeded, "clean module accepted an invalid weight")
	_expect(not clean_module.is_dirty() and clean_module.snapshot_cells() == clean_cells and clean_module.get_sockets().is_empty(), "rejected clean-module metadata commands committed state")
	var draft := StructureDraft.create_level_module(Vector3i(5, 4, 5))
	for direction in LevelSocketDefinition.Direction.values():
		_build_boundary_wall(draft, direction as LevelSocketDefinition.Direction)
	var sockets: Array[Dictionary] = [
		{"cell": Vector3i(2, 1, 0), "direction": LevelSocketDefinition.Direction.NORTH, "id": &"north"},
		{"cell": Vector3i(4, 1, 2), "direction": LevelSocketDefinition.Direction.EAST, "id": &"east"},
		{"cell": Vector3i(2, 1, 4), "direction": LevelSocketDefinition.Direction.SOUTH, "id": &"south"},
		{"cell": Vector3i(0, 1, 2), "direction": LevelSocketDefinition.Direction.WEST, "id": &"west"},
	]
	var east_torch_cell := Vector3i(3, 2, 2)
	_expect(draft.try_place_torch(east_torch_cell, Vector3i.RIGHT).succeeded, "socket carving torch setup failed")
	for socket_data in sockets:
		var cell := socket_data.cell as Vector3i
		var change := draft.try_add_socket(cell, socket_data.direction as LevelSocketDefinition.Direction)
		_expect(change.succeeded and change.metadata_changed, "socket creation failed at %s" % cell)
		_expect(change.changed_cells == [cell, cell + Vector3i.UP], "socket creation returned incorrect aperture cells at %s" % cell)
		var expected_removed: Array[Vector3i] = []
		if socket_data.direction == LevelSocketDefinition.Direction.EAST:
			expected_removed.append(east_torch_cell)
		_expect(change.removed_torch_cells == expected_removed, "socket creation returned incorrect torch deltas at %s" % cell)
		_expect(draft.get_cell(cell) == StructureCell.AIR and draft.get_cell(cell + Vector3i.UP) == StructureCell.AIR, "socket creation did not carve its aperture at %s" % cell)
	var authored := draft.get_sockets()
	_expect(authored.size() == 4, "four-face socket authoring changed socket count")
	_expect(not draft.can_place_torch(authored[0].cell, Vector3i.RIGHT), "torch placement query accepted a socket aperture")
	for index in sockets.size():
		_expect(authored[index].socket_id == sockets[index].id and authored[index].direction == sockets[index].direction, "socket authoring changed direction-based IDs or order")
		_expect(authored[index].unused_fill_block_id == BlockId.Type.STONE, "socket did not inherit its wall fill block")
	var fill_change := draft.try_set_socket_unused_fill_block(&"north", BlockId.Type.MOSSY_STONE_BRICKS)
	_expect(fill_change.succeeded and fill_change.metadata_changed and draft.get_sockets()[0].unused_fill_block_id == BlockId.Type.MOSSY_STONE_BRICKS, "socket unused fill block edit failed")
	_expect(not draft.try_set_socket_unused_fill_block(&"north", BlockId.Type.MOSSY_STONE_BRICKS).succeeded, "socket accepted a no-op unused fill change")
	for invalid_fill in [StructureCell.VOID, BlockId.Type.TORCH, BlockId.Type.WATER, BlockId.Type.COUNT]:
		_expect(not draft.try_set_socket_unused_fill_block(&"north", invalid_fill).succeeded, "socket accepted invalid unused fill block %s" % invalid_fill)
	_expect(not draft.try_set_socket_unused_fill_block(&"missing", BlockId.Type.STONE).succeeded, "unknown socket accepted unused fill metadata")
	_expect(draft.try_set_socket_unused_fill_block(&"north", StructureCell.AIR).succeeded and draft.get_sockets()[0].unused_fill_block_id == StructureCell.AIR, "socket could not be marked as a required connection")
	authored[0].unused_fill_block_id = BlockId.Type.DIRT
	_expect(draft.get_sockets()[0].unused_fill_block_id == StructureCell.AIR, "socket fill query exposed mutable draft state")
	_expect(not draft.has_torch(east_torch_cell), "socket carving retained a torch whose support was removed")
	_expect(authored[1].cell == Vector3i(4, 1, 2), "east socket changed its selected boundary cell")
	var failed_cells := draft.snapshot_cells()
	var failed_sockets := draft.get_sockets()
	_expect(not draft.try_add_socket(Vector3i(3, 1, 1), LevelSocketDefinition.Direction.NORTH).succeeded, "non-boundary socket was accepted")
	_expect(not draft.try_add_socket(Vector3i(3, 1, 0), LevelSocketDefinition.Direction.NORTH).succeeded, "socket overlapping an existing aperture was accepted")
	_expect(draft.snapshot_cells() == failed_cells and draft.get_sockets().size() == failed_sockets.size(), "failed socket creation partially committed")
	var blocked := StructureDraft.create_level_module(Vector3i(7, 4, 7))
	_build_boundary_wall(blocked, LevelSocketDefinition.Direction.NORTH)
	_expect(blocked.try_place_block(Vector3i(3, 1, 1), BlockId.Type.STONE).succeeded, "blocked-inward socket body setup failed")
	var blocked_snapshot := blocked.snapshot_cells()
	_expect(not blocked.try_add_socket(Vector3i(3, 1, 0), LevelSocketDefinition.Direction.NORTH).succeeded, "socket with blocked inward body clearance was accepted")
	_expect(blocked.snapshot_cells() == blocked_snapshot and blocked.get_sockets().is_empty(), "blocked-inward socket partially committed")
	var torch_blocked := StructureDraft.create_level_module(Vector3i(7, 4, 7))
	_build_boundary_wall(torch_blocked, LevelSocketDefinition.Direction.NORTH)
	var occupied_aperture := Vector3i(3, 1, 0)
	_expect(torch_blocked.try_remove_block(occupied_aperture).succeeded and torch_blocked.try_remove_block(occupied_aperture + Vector3i.UP).succeeded, "torch-overlap aperture setup failed")
	_expect(torch_blocked.try_place_torch(occupied_aperture, Vector3i.RIGHT).succeeded, "torch-overlap fixture placement failed")
	_expect(not torch_blocked.try_add_socket(occupied_aperture, LevelSocketDefinition.Direction.NORTH).succeeded, "socket accepted a torch inside its aperture")
	var marker_blocked := StructureDraft.create_level_module(Vector3i(7, 4, 7))
	_build_boundary_wall(marker_blocked, LevelSocketDefinition.Direction.NORTH)
	var marked_aperture := Vector3i(3, 1, 0)
	var marked_return := Vector3i(2, 1, 3)
	_expect(marker_blocked.try_remove_block(marked_aperture).succeeded and marker_blocked.try_remove_block(marked_aperture + Vector3i.UP).succeeded, "marker-overlap aperture setup failed")
	_expect(marker_blocked.try_place_block(marked_return + Vector3i.DOWN, BlockId.Type.STONE).succeeded, "marker-overlap return floor setup failed")
	_expect(marker_blocked.try_set_markers(marked_aperture, LevelSocketDefinition.Direction.NORTH, marked_return, LevelSocketDefinition.Direction.SOUTH).succeeded, "marker-overlap fixture placement failed")
	_expect(not marker_blocked.try_add_socket(marked_aperture, LevelSocketDefinition.Direction.NORTH).succeeded, "socket accepted a marker inside its aperture")
	var repeated := StructureDraft.create_level_module(Vector3i(7, 4, 7))
	_build_boundary_wall(repeated, LevelSocketDefinition.Direction.NORTH)
	var first_north := Vector3i(1, 1, 0)
	var second_north := Vector3i(4, 1, 0)
	_expect(repeated.try_add_socket(first_north, LevelSocketDefinition.Direction.NORTH).succeeded, "first repeated north socket failed")
	_expect(repeated.try_add_socket(second_north, LevelSocketDefinition.Direction.NORTH).succeeded, "second repeated north socket failed")
	_expect(repeated.get_sockets()[-1].socket_id == &"north_2", "same-direction socket did not receive a unique ID")
	_expect(not repeated.try_place_block(second_north, BlockId.Type.DIRT).succeeded, "socket aperture accepted a block")
	_expect(not repeated.try_set_void(second_north).succeeded, "socket aperture accepted VOID")
	_expect(not repeated.try_remove_block(second_north + Vector3i.DOWN).succeeded, "socket floor accepted removal")
	_expect(not repeated.try_set_void(second_north + Vector3i.DOWN).succeeded, "socket floor accepted VOID")
	_expect(repeated.try_remove_socket(&"north_2").succeeded, "socket removal failed")
	_expect(repeated.get_cell(second_north) == StructureCell.AIR and repeated.get_cell(second_north + Vector3i.UP) == StructureCell.AIR, "socket removal refilled its aperture")
	var open_readd := repeated.try_add_socket(second_north, LevelSocketDefinition.Direction.NORTH)
	_expect(open_readd.succeeded and open_readd.changed_cells.is_empty() and repeated.get_sockets()[-1].socket_id == &"north_2", "open socket re-add changed cells or lost its next unique ID")
	var partial := StructureDraft.create_level_module(Vector3i(7, 4, 7))
	_build_boundary_wall(partial, LevelSocketDefinition.Direction.NORTH)
	var partial_cell := Vector3i(3, 1, 0)
	_expect(partial.try_remove_block(partial_cell).succeeded, "partial-aperture lower setup failed")
	var partial_carve := partial.try_add_socket(partial_cell, LevelSocketDefinition.Direction.NORTH)
	_expect(partial_carve.succeeded and partial_carve.changed_cells == [partial_cell + Vector3i.UP], "partial socket aperture did not return its one-cell carve")
	_expect(not draft.try_remove_socket(&"missing").succeeded, "missing socket removal succeeded")
	var unrelated_support := Vector3i(4, 3, 3)
	var unrelated_torch := Vector3i(3, 3, 3)
	var void_support := Vector3i(4, 2, 3)
	var void_torch := Vector3i(3, 2, 3)
	_expect(StructureCell.is_structure_solid(draft.get_cell(unrelated_support)), "unrelated torch support setup failed")
	_expect(draft.try_place_torch(unrelated_torch, Vector3i.RIGHT).succeeded, "unrelated torch setup failed")
	_expect(StructureCell.is_structure_solid(draft.get_cell(void_support)), "VOID torch support setup failed")
	_expect(draft.try_place_torch(void_torch, Vector3i.RIGHT).succeeded, "VOID torch setup failed")
	var void_change := draft.try_set_void(void_support)
	_expect(void_change.succeeded and void_change.changed_cells == [void_support] and void_change.removed_torch_cells == [void_torch], "VOID edit returned incorrect cell or torch deltas")
	_expect(draft.get_cell(void_support) == StructureCell.VOID and not draft.has_torch(void_torch) and draft.has_torch(unrelated_torch), "VOID edit changed unrelated torch state")
	_expect(not draft.try_set_void(void_support).succeeded, "unchanged VOID edit succeeded")
	var occupied_torch := draft.try_set_void(unrelated_torch)
	_expect(not occupied_torch.succeeded and draft.has_torch(unrelated_torch), "VOID edit removed a torch occupying its target")
	for weight in [0.05, 2.375, 150.25]:
		var weight_change := draft.try_set_weight(weight)
		_expect(weight_change.succeeded and weight_change.metadata_changed and draft.get_weight() == weight, "precise module weight was not retained: %s" % weight)
	_expect(not draft.try_set_weight(150.25).succeeded, "unchanged module weight succeeded")
	for invalid_weight in [0.0, -1.0, INF, NAN]:
		_expect(not draft.try_set_weight(invalid_weight).succeeded and draft.get_weight() == 150.25, "invalid module weight changed draft truth")

func _test_variable_connection_aperture() -> void:
	var draft := StructureDraft.create_level_module(Vector3i(16, 8, 7))
	_build_boundary_wall(draft, LevelSocketDefinition.Direction.WEST)
	for y in range(1, 7):
		for z in range(2, 5):
			_expect(draft.try_remove_block(Vector3i(0, y, z)).succeeded, "large opening setup failed at %s" % Vector3i(0, y, z))
	var seed := Vector3i(0, 1, 3)
	var exposed_perimeter := Vector3i(0, 7, 3)
	_expect(draft.try_set_void(exposed_perimeter).succeeded, "exposed opening setup failed")
	var exposed_snapshot := draft.snapshot_cells()
	_expect(not draft.can_add_socket(seed, LevelSocketDefinition.Direction.WEST), "socket query accepted an opening with a VOID perimeter")
	_expect(not draft.try_add_socket(seed, LevelSocketDefinition.Direction.WEST).succeeded, "socket registration accepted an opening with a VOID perimeter")
	_expect(draft.snapshot_cells() == exposed_snapshot and draft.get_sockets().is_empty(), "rejected exposed opening partially committed")
	_expect(draft.try_place_block(exposed_perimeter, BlockId.Type.STONE).succeeded, "exposed opening perimeter could not be repaired")
	var before := draft.snapshot_cells()
	var candidate := draft.get_socket_candidate_cells(seed, LevelSocketDefinition.Direction.WEST)
	_expect(candidate.size() == 18, "large opening candidate did not include all 18 cells")
	_expect(LevelSocketAperture.dimensions(candidate, LevelSocketDefinition.Direction.WEST) == Vector2i(3, 6), "large opening dimensions changed")
	_expect(draft.try_add_socket(seed, LevelSocketDefinition.Direction.WEST).succeeded, "large opening registration failed")
	_expect(draft.snapshot_cells() == before, "registering a prebuilt opening changed dense cells")
	_expect(draft.get_sockets()[0].unused_fill_block_id == BlockId.Type.STONE, "prebuilt opening did not inherit its floor block")
	var copied := draft.get_socket_aperture_cells(&"west")
	copied.clear()
	_expect(draft.get_socket_aperture_cells(&"west").size() == 18, "aperture query exposed mutable draft state")
	_expect(not draft.try_place_block(Vector3i(1, 6, 4), BlockId.Type.STONE).succeeded, "large opening inward AIR accepted a block")
	_expect(not draft.try_remove_block(Vector3i(0, 0, 2)).succeeded, "large opening floor accepted removal")
	_expect(not draft.try_remove_block(Vector3i(0, 3, 1)).succeeded, "registered opening expanded through an ordinary cell edit")
	_expect(draft.try_remove_socket(&"west").succeeded, "large opening socket removal failed")
	_expect(draft.try_remove_block(Vector3i(0, 3, 1)).succeeded, "unregistered opening could not be resized")
	_expect(draft.try_add_socket(seed, LevelSocketDefinition.Direction.WEST).succeeded, "resized opening could not be registered again")
	_expect(draft.get_socket_aperture_cells(&"west").size() == 19, "resized opening profile was not derived from geometry")

func _test_four_way_room_connections() -> void:
	var draft := StructureDraft.create_level_module(Vector3i(7, 4, 7))
	for direction in LevelSocketDefinition.Direction.values():
		_build_boundary_wall(draft, direction as LevelSocketDefinition.Direction)
	var connections: Array[Dictionary] = [
		{"cell": Vector3i(3, 1, 0), "direction": LevelSocketDefinition.Direction.NORTH},
		{"cell": Vector3i(6, 1, 3), "direction": LevelSocketDefinition.Direction.EAST},
		{"cell": Vector3i(3, 1, 6), "direction": LevelSocketDefinition.Direction.SOUTH},
		{"cell": Vector3i(0, 1, 3), "direction": LevelSocketDefinition.Direction.WEST},
	]
	for connection in connections:
		var cell := connection["cell"] as Vector3i
		var direction := connection["direction"] as LevelSocketDefinition.Direction
		_expect(draft.get_boundary_directions(cell).has(direction), "four-way room boundary query missed %s" % direction)
		_expect(draft.can_add_socket(cell, direction), "four-way room query rejected %s" % direction)
		_expect(draft.try_add_socket(cell, direction).succeeded, "four-way room failed to add %s" % direction)
		_expect(draft.get_cell(cell) == StructureCell.AIR and draft.get_cell(cell + Vector3i.UP) == StructureCell.AIR, "four-way room did not carve %s" % direction)
	_expect(draft.get_sockets().size() == 4, "four-way room did not retain four connections")
	for value in LevelSocketDefinition.Direction.values():
		_expect(draft.has_socket_direction(value as LevelSocketDefinition.Direction), "four-way room omitted direction %s" % value)

func _test_requirement_reference_counts() -> void:
	var draft := StructureDraft.create_level_module(Vector3i(5, 4, 5))
	_build_boundary_wall(draft, LevelSocketDefinition.Direction.NORTH)
	var socket_cell := Vector3i(2, 1, 0)
	var return_cell := Vector3i(4, 1, 4)
	_expect(draft.try_place_block(return_cell + Vector3i.DOWN, BlockId.Type.STONE).succeeded, "overlap return floor setup failed")
	_expect(draft.try_add_socket(socket_cell, LevelSocketDefinition.Direction.NORTH).succeeded, "overlap socket setup failed")
	var before_invalid := StructureResourceAdapter.create_snapshot(draft, &"overlap_module") as LevelModuleDefinition
	var marker_change := draft.try_set_markers(
		socket_cell,
		LevelSocketDefinition.Direction.NORTH,
		return_cell,
		LevelSocketDefinition.Direction.SOUTH,
	)
	_expect(not marker_change.succeeded, "marker footprint overlapped a socket aperture")
	var after_invalid := StructureResourceAdapter.create_snapshot(draft, &"overlap_module") as LevelModuleDefinition
	_expect(StructureResourceAdapter.resources_equal(before_invalid, after_invalid), "failed socket-overlap marker pair partially committed")
	_expect(draft.try_remove_socket(&"north").succeeded, "socket removal failed after rejected marker overlap")
	_expect(draft.try_place_block(socket_cell, BlockId.Type.DIRT).succeeded, "removed socket left a stale AIR requirement")
	_expect(draft.try_remove_block(socket_cell + Vector3i.DOWN).succeeded, "removed socket left a stale solid requirement")
	var coincident := StructureDraft.create_level_module(Vector3i(5, 4, 5))
	var shared_cell := Vector3i(2, 1, 2)
	var moved_return := Vector3i(3, 1, 3)
	_expect(coincident.try_place_block(shared_cell + Vector3i.DOWN, BlockId.Type.STONE).succeeded, "coincident marker floor setup failed")
	_expect(coincident.try_place_block(moved_return + Vector3i.DOWN, BlockId.Type.STONE).succeeded, "moved marker floor setup failed")
	_expect(coincident.try_set_markers(shared_cell, LevelSocketDefinition.Direction.NORTH, shared_cell, LevelSocketDefinition.Direction.SOUTH).succeeded, "coincident marker footprints were rejected")
	_expect(not coincident.try_place_block(shared_cell, BlockId.Type.DIRT).succeeded and not coincident.try_remove_block(shared_cell + Vector3i.DOWN).succeeded, "coincident marker requirements were not indexed")
	_expect(coincident.try_set_markers(shared_cell, LevelSocketDefinition.Direction.EAST, moved_return, LevelSocketDefinition.Direction.WEST).succeeded, "coincident marker replacement failed")
	_expect(not coincident.try_place_block(shared_cell, BlockId.Type.DIRT).succeeded and not coincident.try_remove_block(shared_cell + Vector3i.DOWN).succeeded, "marker replacement removed the surviving shared requirement")
	_expect(coincident.try_clear_markers().succeeded, "coincident marker clearing failed")
	_expect(coincident.try_place_block(shared_cell, BlockId.Type.DIRT).succeeded and coincident.try_remove_block(shared_cell + Vector3i.DOWN).succeeded, "coincident marker clearing left stale requirement counts")

func _test_module_authoring_snapshot() -> void:
	var draft := StructureDraft.create_level_module(Vector3i(5, 4, 5))
	_build_boundary_wall(draft, LevelSocketDefinition.Direction.NORTH)
	var socket_cell := Vector3i(2, 1, 0)
	var spawn_cell := Vector3i(1, 1, 2)
	var return_cell := Vector3i(3, 1, 2)
	var torch_support := Vector3i(4, 2, 3)
	for floor_cell in [spawn_cell + Vector3i.DOWN, return_cell + Vector3i.DOWN]:
		_expect(draft.try_place_block(floor_cell, BlockId.Type.STONE).succeeded, "snapshot floor setup failed")
	_expect(draft.try_add_socket(socket_cell, LevelSocketDefinition.Direction.NORTH).succeeded, "snapshot socket command failed")
	_expect(draft.try_set_markers(spawn_cell, LevelSocketDefinition.Direction.EAST, return_cell, LevelSocketDefinition.Direction.WEST).succeeded, "snapshot marker command failed")
	_expect(draft.try_place_block(torch_support, BlockId.Type.STONE).succeeded, "snapshot torch support failed")
	_expect(draft.try_place_torch(Vector3i(3, 2, 3), Vector3i.RIGHT).succeeded, "snapshot torch command failed")
	_expect(draft.try_set_void(Vector3i(0, 3, 0)).succeeded, "snapshot VOID command failed")
	_expect(draft.try_set_weight(137.625).succeeded, "snapshot weight command failed")
	var snapshot := StructureResourceAdapter.create_snapshot(draft, &"authored_module") as LevelModuleDefinition
	_expect(snapshot != null and snapshot.validate(), "authored module snapshot was invalid")
	if snapshot == null:
		return
	var restored := StructureDraft.restore_level_module(snapshot, ProjectSettings.globalize_path("res://../authored_module.tres"))
	var restored_snapshot := StructureResourceAdapter.create_snapshot(restored, &"authored_module") as LevelModuleDefinition
	_expect(restored != null and StructureResourceAdapter.resources_equal(snapshot, restored_snapshot), "authored module snapshot did not round-trip exactly")
	_expect(restored.get_weight() == 137.625 and restored.get_sockets()[0].socket_id == &"north", "authored module round trip changed weight or socket order")
	_expect(restored.get_torches()[0].cell == Vector3i(3, 2, 3), "authored module round trip changed torch order")

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
	for y in definition.size.y:
		for x in definition.size.x:
			definition.cells[StructureCell.index_of(Vector3i(x, y, 0), definition.size)] = BlockId.Type.STONE
			definition.cells[StructureCell.index_of(Vector3i(x, y, definition.size.z - 1), definition.size)] = BlockId.Type.STONE
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
	for cell in [Vector3i(2, 1, 0), Vector3i(2, 2, 0), Vector3i(2, 1, 4), Vector3i(2, 2, 4)]:
		definition.cells[StructureCell.index_of(cell, definition.size)] = StructureCell.AIR
	definition.cells[StructureCell.index_of(Vector3i(0, 3, 0), definition.size)] = StructureCell.VOID
	var north := LevelSocketDefinition.new()
	north.socket_id = &"north_entry"
	north.cell = Vector3i(2, 1, 0)
	north.direction = LevelSocketDefinition.Direction.NORTH
	north.unused_fill_block_id = BlockId.Type.MOSSY_STONE_BRICKS
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

func _build_boundary_wall(draft: StructureDraft, direction: LevelSocketDefinition.Direction) -> void:
	var size := draft.get_size()
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var cell := Vector3i(x, y, z)
				if not LevelSocketAperture.is_boundary(cell, size, direction) or StructureCell.is_structure_solid(draft.get_cell(cell)):
					continue
				_expect(draft.try_place_block(cell, BlockId.Type.STONE).succeeded, "boundary wall setup failed at %s" % cell)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
