extends SceneTree

const CATALOG_PATH: String = "res://levels/content/level_catalog.tres"
const LEVEL_ID: StringName = &"stone_dungeon"
const ENTRANCE_ID: StringName = &"overworld_dungeon_entrance"
const FUZZ_SEED_COUNT: int = 1000
const EXPECTED_GOLDEN_DIGEST: String = "54eb2e11958a406fe08aa8c6b86885a84859b3987f51c1ae1438751db5b4bce3"
const DIRECTIONS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]
const EXPECTED_MODULE_IDS: Array[StringName] = [
	&"dungeon_start_chamber",
	&"dungeon_straight_hall",
	&"dungeon_corner_hall",
	&"dungeon_small_room",
	&"dungeon_large_room",
	&"dungeon_t_junction",
	&"dungeon_compact_dead_end",
	&"dungeon_dead_end_chamber",
]

var _failures: int = 0
var _assertions: int = 0
var _catalog: LevelCatalog

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = load(CATALOG_PATH) as LevelCatalog
	_expect(_catalog != null, "level catalog did not load")
	if _catalog == null:
		_finish(0, 0)
		return
	_test_catalog_and_modules()
	_test_rotations()
	_test_seed_identity_and_failures()
	var fuzz_started := Time.get_ticks_msec()
	var successful_seeds := _test_generation_fuzz()
	var fuzz_msec := Time.get_ticks_msec() - fuzz_started
	_finish(successful_seeds, fuzz_msec)

func _test_catalog_and_modules() -> void:
	_expect(LevelCell.VOID == -1, "VOID encoding changed")
	_expect(LevelCell.AIR == 0, "AIR encoding changed")
	_expect(LevelCell.is_valid(LevelCell.VOID), "VOID is not a valid module cell")
	_expect(LevelCell.is_valid(LevelCell.AIR), "AIR is not a valid module cell")
	_expect(LevelCell.is_valid(BlockId.Type.STONE), "stable stone block ID is invalid")
	_expect(not LevelCell.is_valid(BlockId.Type.TORCH), "torch block ID was accepted as a dense module cell")
	_expect(not LevelCell.is_valid(BlockId.Type.WATER), "water block ID was accepted as a dense module cell")
	_expect(not LevelCell.is_valid(-2), "unknown negative cell value was accepted")
	_expect(not LevelCell.is_valid(BlockId.Type.COUNT), "unknown positive block ID was accepted")
	_expect(_catalog.validate(), "level catalog validation failed")
	_expect(_catalog.modules.size() == EXPECTED_MODULE_IDS.size(), "catalog must contain exactly eight initial modules")
	_expect(_catalog.levels.size() == 1, "catalog must contain exactly one initial level")
	var actual_ids: Array[StringName] = []
	for module in _catalog.modules:
		actual_ids.append(module.module_id)
	actual_ids.sort()
	var expected_ids := EXPECTED_MODULE_IDS.duplicate()
	expected_ids.sort()
	_expect(actual_ids == expected_ids, "catalog module IDs changed: %s" % str(actual_ids))
	_expect(_catalog.has_level(LEVEL_ID), "stone dungeon definition is missing")
	var definition := _catalog.get_level(LEVEL_ID)
	_expect(definition.validate(), "stone dungeon definition is invalid")
	_expect(definition.start_module_id == &"dungeon_start_chamber", "start module ID changed")
	_expect(definition.minimum_module_count == 8 and definition.maximum_module_count == 12, "module-count range must remain 8-12")
	_expect(definition.maximum_extent == Vector3i(96, 16, 96), "level extent bound changed")
	_expect(definition.maximum_explored_states == 10000, "search-state bound changed")
	_expect(definition.expansion_module_ids.size() == 5, "expansion pool must contain five modules")
	_expect(definition.cap_module_ids.size() == 2, "cap pool must contain two modules")
	var start_count := 0
	for module in _catalog.modules:
		_expect(module != null and module.validate(), "module failed validation: %s" % module.module_id)
		_expect(module.resource_path.ends_with(".tres"), "module is not backed by a typed resource: %s" % module.module_id)
		_expect(module.cells.size() == module.size.x * module.size.y * module.size.z, "dense cell count changed for %s" % module.module_id)
		_expect(module.weight > 0.0, "non-positive module weight for %s" % module.module_id)
		var seen_sockets: Dictionary = {}
		for socket in module.sockets:
			_expect(not seen_sockets.has(socket.socket_id), "duplicate socket ID in %s" % module.module_id)
			seen_sockets[socket.socket_id] = true
			_expect(_is_boundary(socket.cell, module.size, socket.direction), "socket is not on its declared boundary in %s" % module.module_id)
			_expect(module.cell_at(socket.cell) == LevelCell.AIR, "socket lower aperture is not AIR in %s" % module.module_id)
			_expect(module.cell_at(socket.cell + Vector3i.UP) == LevelCell.AIR, "socket upper aperture is not AIR in %s" % module.module_id)
			var inward := -LevelSocketDefinition.vector_for(socket.direction)
			_expect(module.cell_at(socket.cell + inward) == LevelCell.AIR, "socket does not open into lower interior AIR in %s" % module.module_id)
			_expect(module.cell_at(socket.cell + Vector3i.UP + inward) == LevelCell.AIR, "socket does not open into upper interior AIR in %s" % module.module_id)
			_expect(LevelCell.is_structure_solid(module.cell_at(socket.cell + Vector3i.DOWN)), "socket floor is missing in %s" % module.module_id)
		var seen_torches: Dictionary = {}
		for torch in module.torches:
			_expect(not seen_torches.has(torch.cell), "duplicate torch cell in %s" % module.module_id)
			seen_torches[torch.cell] = true
			_expect(module.cell_at(torch.cell) == LevelCell.AIR, "torch is not in AIR in %s" % module.module_id)
			var support := torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction)
			_expect(LevelCell.is_in_bounds(support, module.size) and LevelCell.is_structure_solid(module.cell_at(support)), "torch wall support is missing in %s" % module.module_id)
		for y in module.size.y:
			for z in module.size.z:
				for x in module.size.x:
					var cell := Vector3i(x, y, z)
					var index := LevelCell.index_of(cell, module.size)
					_expect(index >= 0 and index < module.cells.size(), "dense index escaped module bounds in %s" % module.module_id)
					_expect(module.cell_at(cell) == module.cells[index], "dense cell lookup mismatch in %s" % module.module_id)
					_expect(LevelCell.is_valid(module.cell_at(cell)), "module contains an invalid cell in %s" % module.module_id)
		if module.spawn_marker != null:
			start_count += 1
			_expect(module.module_id == definition.start_module_id, "non-start module has spawn markers: %s" % module.module_id)
			_expect(module.return_door_marker != null, "start module return marker is missing")
			_test_marker(module, module.spawn_marker, "spawn")
			_test_marker(module, module.return_door_marker, "return")
		else:
			_expect(module.return_door_marker == null, "module has an unpaired return marker: %s" % module.module_id)
		if module.module_id in definition.expansion_module_ids:
			_expect(module.sockets.size() >= 2, "expansion module lacks two sockets: %s" % module.module_id)
		if module.module_id in definition.cap_module_ids:
			_expect(module.sockets.size() == 1, "cap module must have one socket: %s" % module.module_id)
	_expect(start_count == 1, "catalog must have exactly one start module")

func _test_marker(module: LevelModuleDefinition, marker: LevelMarkerDefinition, label: String) -> void:
	_expect(LevelCell.is_in_bounds(marker.cell, module.size), "%s marker is outside %s" % [label, module.module_id])
	_expect(module.cell_at(marker.cell) == LevelCell.AIR, "%s marker is not in AIR in %s" % [label, module.module_id])
	_expect(LevelCell.is_in_bounds(marker.cell + Vector3i.UP, module.size) and module.cell_at(marker.cell + Vector3i.UP) == LevelCell.AIR, "%s marker has no headroom in %s" % [label, module.module_id])
	_expect(LevelCell.is_structure_solid(module.cell_at(marker.cell + Vector3i.DOWN)), "%s marker has no floor in %s" % [label, module.module_id])

func _test_rotations() -> void:
	for module in _catalog.modules:
		_expect(module.rotated_size(0) == module.size, "rotation zero changed size for %s" % module.module_id)
		_expect(module.rotated_size(1) == Vector3i(module.size.z, module.size.y, module.size.x), "quarter-turn size is wrong for %s" % module.module_id)
		_expect(module.rotated_size(2) == module.size, "half-turn size is wrong for %s" % module.module_id)
		_expect(module.rotated_size(3) == Vector3i(module.size.z, module.size.y, module.size.x), "three-quarter-turn size is wrong for %s" % module.module_id)
		for quarter_turns in range(4):
			var rotated_size := module.rotated_size(quarter_turns)
			var occupied: Dictionary = {}
			for y in module.size.y:
				for z in module.size.z:
					for x in module.size.x:
						var source := Vector3i(x, y, z)
						var transformed := module.rotate_cell(source, quarter_turns)
						_expect(LevelCell.is_in_bounds(transformed, rotated_size), "rotation escaped bounds for %s q%d" % [module.module_id, quarter_turns])
						_expect(not occupied.has(transformed), "rotation collapsed cells for %s q%d" % [module.module_id, quarter_turns])
						occupied[transformed] = module.cell_at(source)
			_expect(occupied.size() == module.cells.size(), "rotation did not preserve dense cell count for %s q%d" % [module.module_id, quarter_turns])
			for socket in module.sockets:
				var transformed_socket := module.rotate_cell(socket.cell, quarter_turns)
				var transformed_direction := LevelSocketDefinition.rotate(socket.direction, quarter_turns)
				_expect(_is_boundary(transformed_socket, rotated_size, transformed_direction), "rotated socket left its boundary for %s q%d" % [module.module_id, quarter_turns])
				_expect(occupied[transformed_socket] == LevelCell.AIR, "rotated lower aperture changed for %s q%d" % [module.module_id, quarter_turns])
				_expect(occupied[transformed_socket + Vector3i.UP] == LevelCell.AIR, "rotated upper aperture changed for %s q%d" % [module.module_id, quarter_turns])
			for torch in module.torches:
				var transformed_torch := module.rotate_cell(torch.cell, quarter_turns)
				var transformed_direction := LevelSocketDefinition.rotate(torch.wall_direction, quarter_turns)
				var expected_support := module.rotate_cell(torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction), quarter_turns)
				_expect(transformed_torch + LevelSocketDefinition.vector_for(transformed_direction) == expected_support, "rotated torch direction detached from support in %s q%d" % [module.module_id, quarter_turns])
				_expect(int(occupied[transformed_torch]) == LevelCell.AIR and LevelCell.is_structure_solid(int(occupied[expected_support])), "rotated torch cells changed in %s q%d" % [module.module_id, quarter_turns])
			if module.spawn_marker != null:
				_test_rotated_marker(module, module.spawn_marker, quarter_turns, occupied, "spawn")
				_test_rotated_marker(module, module.return_door_marker, quarter_turns, occupied, "return")
		_expect(module.rotate_cell(Vector3i.ZERO, 4) == Vector3i.ZERO, "full rotation is not identity for %s" % module.module_id)
		_expect(module.rotate_cell(Vector3i.ZERO, -4) == Vector3i.ZERO, "negative full rotation is not identity for %s" % module.module_id)

func _test_rotated_marker(module: LevelModuleDefinition, marker: LevelMarkerDefinition, quarter_turns: int, occupied: Dictionary, label: String) -> void:
	var transformed := module.rotate_cell(marker.cell, quarter_turns)
	var transformed_head := module.rotate_cell(marker.cell + Vector3i.UP, quarter_turns)
	var transformed_floor := module.rotate_cell(marker.cell + Vector3i.DOWN, quarter_turns)
	_expect(int(occupied[transformed]) == LevelCell.AIR, "rotated %s marker changed in %s q%d" % [label, module.module_id, quarter_turns])
	_expect(int(occupied[transformed_head]) == LevelCell.AIR, "rotated %s marker headroom changed in %s q%d" % [label, module.module_id, quarter_turns])
	_expect(LevelCell.is_structure_solid(int(occupied[transformed_floor])), "rotated %s marker floor changed in %s q%d" % [label, module.module_id, quarter_turns])
	_expect(LevelSocketDefinition.rotate(marker.facing, quarter_turns) == ((int(marker.facing) + quarter_turns) % 4 as LevelSocketDefinition.Direction), "rotated %s marker facing changed in %s q%d" % [label, module.module_id, quarter_turns])

func _test_seed_identity_and_failures() -> void:
	var identity_seed := LevelGenerator.derive_seed(1337, &"entrance", Vector3i(1, 2, 3))
	_expect(identity_seed == 1925327387, "FNV-1a seed identity changed: %d" % identity_seed)
	_expect(LevelGenerator.derive_seed(1337, &"entrance", Vector3i(1, 2, 3)) == identity_seed, "identical seed identity is not stable")
	_expect(LevelGenerator.derive_seed(1338, &"entrance", Vector3i(1, 2, 3)) != identity_seed, "world seed is absent from level identity")
	_expect(LevelGenerator.derive_seed(1337, &"other", Vector3i(1, 2, 3)) != identity_seed, "entrance ID is absent from level identity")
	_expect(LevelGenerator.derive_seed(1337, &"entrance", Vector3i(1, 2, 4)) != identity_seed, "entrance coordinate is absent from level identity")
	var malformed := LevelGenerator.new().generate(null, LEVEL_ID, 1, ENTRANCE_ID, Vector3i.ZERO)
	_expect(not malformed.succeeded, "null catalog unexpectedly generated a level")
	_expect(malformed.failure_code == LevelGenerationResult.FailureCode.INVALID_CATALOG, "null catalog returned the wrong failure code")
	_expect(malformed.layout == null and not malformed.failure_reason.is_empty(), "malformed catalog failure lacks diagnostics")
	var unknown := LevelGenerator.new().generate(_catalog, &"missing_level", 1, ENTRANCE_ID, Vector3i.ZERO)
	_expect(not unknown.succeeded, "unknown level ID unexpectedly generated a level")
	_expect(unknown.failure_code == LevelGenerationResult.FailureCode.UNKNOWN_LEVEL, "unknown level returned the wrong failure code")
	_expect(unknown.layout == null and unknown.failure_reason.contains("missing_level"), "unknown level failure lacks its stable ID")
	var probe_output: Array = []
	var probe_exit := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/level_malformed_probe.gd"],
		probe_output,
		true
	)
	var probe_text := "\n".join(PackedStringArray(probe_output))
	_expect(probe_exit == 0, "malformed typed catalog probe exited %d" % probe_exit)
	_expect(probe_text.contains("LEVEL_MALFORMED_PROBE PASS"), "malformed typed catalog probe did not return the expected failure")

func _test_generation_fuzz() -> int:
	var saw_minimum := false
	var saw_maximum := false
	var successful_seeds := 0
	var golden_digest := ""
	for seed_index in range(FUZZ_SEED_COUNT):
		var world_seed := seed_index - 500
		var entrance_coordinate := Vector3i(seed_index % 29 - 14, seed_index % 7, seed_index % 31 - 15)
		var first := LevelGenerator.new().generate(_catalog, LEVEL_ID, world_seed, ENTRANCE_ID, entrance_coordinate)
		_expect(first.succeeded, "generation failed for fuzz seed %d: %s" % [seed_index, first.failure_reason])
		if not first.succeeded:
			continue
		successful_seeds += 1
		_validate_layout(first.layout, seed_index)
		var first_digest := _layout_digest(first.layout)
		var second := LevelGenerator.new().generate(_catalog, LEVEL_ID, world_seed, ENTRANCE_ID, entrance_coordinate)
		_expect(second.succeeded, "repeat generation failed for fuzz seed %d: %s" % [seed_index, second.failure_reason])
		if second.succeeded:
			_expect(_layout_digest(second.layout) == first_digest, "layout changed across identical generation for fuzz seed %d" % seed_index)
		if first.layout.placed_modules.size() == 8:
			saw_minimum = true
		if first.layout.placed_modules.size() == 12:
			saw_maximum = true
		if world_seed == 1337:
			golden_digest = first_digest
	var golden_result := LevelGenerator.new().generate(_catalog, LEVEL_ID, 1337, ENTRANCE_ID, Vector3i(7, 0, -9))
	_expect(golden_result.succeeded, "fixed golden layout failed generation")
	if golden_result.succeeded:
		golden_digest = _layout_digest(golden_result.layout)
		_expect(golden_digest == EXPECTED_GOLDEN_DIGEST, "fixed layout digest changed: %s" % golden_digest)
	_expect(successful_seeds == FUZZ_SEED_COUNT, "only %d/%d fuzz seeds generated" % [successful_seeds, FUZZ_SEED_COUNT])
	_expect(saw_minimum, "1,000-seed fuzz never generated the minimum module count")
	_expect(saw_maximum, "1,000-seed fuzz never generated the maximum module count")
	return successful_seeds

func _validate_layout(layout: LevelLayout, seed_index: int) -> void:
	var label := "seed %d" % seed_index
	_expect(layout != null, "layout is null for %s" % label)
	if layout == null:
		return
	var definition := _catalog.get_level(LEVEL_ID)
	_expect(layout.target_module_count >= 8 and layout.target_module_count <= 12, "target count escaped 8-12 for %s" % label)
	_expect(layout.placed_modules.size() == layout.target_module_count, "placed count does not match target for %s" % label)
	_expect(layout.explored_state_count > 0 and layout.explored_state_count <= definition.maximum_explored_states, "explored-state count escaped bounds for %s" % label)
	var ownership: Dictionary = {}
	var rebuilt_min := Vector3i.ZERO
	var rebuilt_max := Vector3i.ZERO
	var has_rebuilt_bounds := false
	var socket_records: Array[Dictionary] = []
	var expected_torches: Dictionary = {}
	var marker_count := 0
	for placement_index in layout.placed_modules.size():
		var placement := layout.placed_modules[placement_index]
		_expect(placement.definition != null and _catalog.has_module(placement.definition.module_id), "placement has unknown definition for %s" % label)
		_expect(placement.rotation >= 0 and placement.rotation < 4, "placement rotation escaped quarter turns for %s" % label)
		var module := placement.definition
		for y in module.size.y:
			for z in module.size.z:
				for x in module.size.x:
					var local_cell := Vector3i(x, y, z)
					var value := module.cell_at(local_cell)
					if value == LevelCell.VOID:
						continue
					var world_cell := placement.world_cell(local_cell)
					_expect(not ownership.has(world_cell), "module overlap at %s for %s" % [world_cell, label])
					ownership[world_cell] = placement_index
					_expect(layout.has_cell(world_cell), "placement cell is unclaimed at %s for %s" % [world_cell, label])
					_expect(layout.get_cell(world_cell) == value, "placement cell value changed at %s for %s" % [world_cell, label])
					if not has_rebuilt_bounds:
						rebuilt_min = world_cell
						rebuilt_max = world_cell
						has_rebuilt_bounds = true
					else:
						rebuilt_min = rebuilt_min.min(world_cell)
						rebuilt_max = rebuilt_max.max(world_cell)
		for socket in module.sockets:
			socket_records.append({
				"placement": placement_index,
				"cell": placement.world_cell(socket.cell),
				"direction": placement.world_direction(socket.direction),
			})
		for torch in module.torches:
			var torch_cell := placement.world_cell(torch.cell)
			var torch_direction := placement.world_direction(torch.wall_direction)
			var key := _torch_key(torch_cell, torch_direction, module.module_id)
			_expect(not expected_torches.has(key), "duplicate reconstructed torch for %s" % label)
			expected_torches[key] = true
		if module.spawn_marker != null:
			marker_count += 1
			_expect(layout.spawn_cell == placement.world_cell(module.spawn_marker.cell), "spawn marker transform changed for %s" % label)
			_expect(layout.spawn_facing == placement.world_direction(module.spawn_marker.facing), "spawn facing transform changed for %s" % label)
			_expect(layout.return_door_cell == placement.world_cell(module.return_door_marker.cell), "return marker transform changed for %s" % label)
			_expect(layout.return_door_facing == placement.world_direction(module.return_door_marker.facing), "return facing transform changed for %s" % label)
	_expect(marker_count == 1, "layout does not contain exactly one marked start module for %s" % label)
	_expect(ownership.size() == layout.cells.size(), "layout contains cells not owned by one module for %s" % label)
	for cell in layout.cells:
		_expect(ownership.has(cell), "layout cell has no module owner at %s for %s" % [cell, label])
		_expect(LevelCell.is_valid(int(layout.cells[cell])) and int(layout.cells[cell]) != LevelCell.VOID, "layout contains invalid cell at %s for %s" % [cell, label])
	_expect(layout.bounds_min == rebuilt_min and layout.bounds_max == rebuilt_max, "stored bounds differ from claimed cells for %s" % label)
	var span := layout.bounds_max - layout.bounds_min + Vector3i.ONE
	_expect(span.x <= definition.maximum_extent.x and span.y <= definition.maximum_extent.y and span.z <= definition.maximum_extent.z, "layout exceeds configured extent for %s" % label)
	var allowed_cross_module_edges: Dictionary = {}
	for socket_index in socket_records.size():
		var socket := socket_records[socket_index]
		var cell := socket["cell"] as Vector3i
		var direction := socket["direction"] as LevelSocketDefinition.Direction
		var neighbor := cell + LevelSocketDefinition.vector_for(direction)
		var partner_count := 0
		for other_index in socket_records.size():
			if other_index == socket_index:
				continue
			var other := socket_records[other_index]
			if int(other["placement"]) == int(socket["placement"]):
				continue
			if other["cell"] == neighbor and int(other["direction"]) == int(LevelSocketDefinition.opposite(direction)):
				partner_count += 1
		_expect(partner_count == 1, "socket has %d partners instead of one at %s for %s" % [partner_count, cell, label])
		_expect(layout.get_cell(cell) == LevelCell.AIR and layout.get_cell(cell + Vector3i.UP) == LevelCell.AIR, "socket aperture is not open for %s" % label)
		_expect(layout.get_cell(neighbor) == LevelCell.AIR and layout.get_cell(neighbor + Vector3i.UP) == LevelCell.AIR, "socket partner aperture is not open for %s" % label)
		allowed_cross_module_edges[_edge_key(cell, neighbor)] = true
		allowed_cross_module_edges[_edge_key(cell + Vector3i.UP, neighbor + Vector3i.UP)] = true
	for cell in layout.cells:
		if int(layout.cells[cell]) != LevelCell.AIR:
			continue
		var world_cell := cell as Vector3i
		var owner := int(ownership[world_cell])
		for direction in DIRECTIONS:
			var neighbor := world_cell + direction
			if not ownership.has(neighbor) or int(ownership[neighbor]) == owner or layout.get_cell(neighbor) != LevelCell.AIR:
				continue
			_expect(allowed_cross_module_edges.has(_edge_key(world_cell, neighbor)), "unintended cross-module AIR adjacency at %s for %s" % [world_cell, label])
	var reachable: Dictionary = {layout.spawn_cell: true}
	var pending: Array[Vector3i] = [layout.spawn_cell]
	var pending_index := 0
	while pending_index < pending.size():
		var cell := pending[pending_index]
		pending_index += 1
		for direction in DIRECTIONS:
			var neighbor := cell + direction
			if reachable.has(neighbor) or layout.get_cell(neighbor) != LevelCell.AIR:
				continue
			reachable[neighbor] = true
			pending.append(neighbor)
	var air_count := 0
	for cell in layout.cells:
		if int(layout.cells[cell]) == LevelCell.AIR:
			air_count += 1
	_expect(reachable.size() == air_count, "only %d/%d AIR cells are reachable for %s" % [reachable.size(), air_count, label])
	var actual_torches: Dictionary = {}
	for torch in layout.torches:
		var key := _torch_key(torch.cell, torch.wall_direction, torch.module_id)
		_expect(not actual_torches.has(key), "duplicate placed torch for %s" % label)
		actual_torches[key] = true
		_expect(layout.get_cell(torch.cell) == LevelCell.AIR, "placed torch is not in AIR for %s" % label)
		var support := torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction)
		_expect(LevelCell.is_structure_solid(layout.get_cell(support)), "placed torch has no solid support for %s" % label)
	_expect(actual_torches == expected_torches, "placed torch set differs from authored markers for %s" % label)

func _layout_digest(layout: LevelLayout) -> String:
	var lines := PackedStringArray()
	lines.append("seed=%d target=%d explored=%d" % [layout.seed_value, layout.target_module_count, layout.explored_state_count])
	lines.append("spawn=%s:%d return=%s:%d bounds=%s:%s" % [layout.spawn_cell, int(layout.spawn_facing), layout.return_door_cell, int(layout.return_door_facing), layout.bounds_min, layout.bounds_max])
	for placement in layout.placed_modules:
		lines.append("module=%s:%s:%d" % [placement.definition.module_id, placement.origin, placement.rotation])
	var ordered_cells: Array[Vector3i] = []
	for cell in layout.cells:
		ordered_cells.append(cell as Vector3i)
	ordered_cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _cell_less(a, b)
	)
	for cell in ordered_cells:
		lines.append("cell=%d,%d,%d:%d" % [cell.x, cell.y, cell.z, int(layout.cells[cell])])
	var torch_lines := PackedStringArray()
	for torch in layout.torches:
		torch_lines.append(_torch_key(torch.cell, torch.wall_direction, torch.module_id))
	torch_lines.sort()
	for torch_line in torch_lines:
		lines.append("torch=" + torch_line)
	return "\n".join(lines).sha256_text()

func _torch_key(cell: Vector3i, direction: LevelSocketDefinition.Direction, module_id: StringName) -> String:
	return "%d,%d,%d:%d:%s" % [cell.x, cell.y, cell.z, int(direction), module_id]

func _edge_key(first: Vector3i, second: Vector3i) -> String:
	if _cell_less(second, first):
		var swap := first
		first = second
		second = swap
	return "%d,%d,%d>%d,%d,%d" % [first.x, first.y, first.z, second.x, second.y, second.z]

func _cell_less(first: Vector3i, second: Vector3i) -> bool:
	if first.x != second.x:
		return first.x < second.x
	if first.y != second.y:
		return first.y < second.y
	return first.z < second.z

func _is_boundary(cell: Vector3i, size: Vector3i, direction: LevelSocketDefinition.Direction) -> bool:
	match direction:
		LevelSocketDefinition.Direction.NORTH:
			return cell.z == 0
		LevelSocketDefinition.Direction.EAST:
			return cell.x == size.x - 1
		LevelSocketDefinition.Direction.SOUTH:
			return cell.z == size.z - 1
		LevelSocketDefinition.Direction.WEST:
			return cell.x == 0
	return false

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	print("[level_system] FAIL: %s" % message)

func _finish(successful_seeds: int, fuzz_msec: int) -> void:
	if _failures == 0:
		print("LEVEL_SYSTEM PASS seeds=%d assertions=%d fuzz_msec=%d" % [successful_seeds, _assertions, fuzz_msec])
		quit(0)
	else:
		print("LEVEL_SYSTEM FAILED failures=%d assertions=%d seeds=%d" % [_failures, _assertions, successful_seeds])
		quit(1)
