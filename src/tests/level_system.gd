extends SceneTree

const CATALOG_PATH: String = "res://levels/content/dungeons/stone/level_catalog.tres"
const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const ITEM_CATALOG_PATH: String = "res://items/item_catalog.tres"
const ENTRANCE_DEFINITION_PATH: String = "res://levels/content/dungeons/stone/entrance.tres"
const LEVEL_ID: StringName = &"stone_dungeon"
const ENTRANCE_ID: StringName = &"overworld_dungeon_entrance"
const STONE_MODULE_DIRECTORY: String = "res://levels/content/dungeons/stone/modules"
const FUZZ_SEED_COUNT: int = 1000
const DEEP_FUZZ_INTERVAL: int = 20
const LIVE_ROOM_COUNT: int = 7
const LIVE_HALLWAY_COUNT: int = 5
const LIVE_TARGET_MODULE_COUNT: int = 13
const EXPECTED_LIVE_GOLDEN_DIGEST: String = "24c08b52fcfd94162e03bc988e8dabafd293f0781d951bf050bac4fc0b27a4da"
const DIRECTIONS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]
const EXPECTED_MODULE_IDS: Array[StringName] = [
	&"stone_entry_path",
	&"stone_hallway",
	&"stone_master_room",
	&"stone_room",
	&"stone_chest_room",
]
const EXPECTED_HALLWAY_MODULE_IDS: Array[StringName] = [&"stone_hallway"]
const EXPECTED_ROOM_COUNTS: Dictionary = {
	&"master_room": 1,
	&"normal_room": 3,
	&"chest_room": 3,
}
const EXPECTED_ENCOUNTER_COUNTS: Dictionary = {
	&"master_room": 40,
	&"normal_room": 25,
}

var _failures: int = 0
var _assertions: int = 0
var _catalog: LevelCatalog
var _block_catalog: BlockCatalog
var _item_catalog: ItemCatalog
var _saw_connected_optional_socket: bool = false
var _saw_sealed_optional_socket: bool = false

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_catalog = load(CATALOG_PATH) as LevelCatalog
	_block_catalog = load(BLOCK_CATALOG_PATH) as BlockCatalog
	_item_catalog = load(ITEM_CATALOG_PATH) as ItemCatalog
	_expect(_catalog != null, "level catalog did not load")
	_expect(_block_catalog != null and _block_catalog.validate(), "block catalog did not load or validate")
	_expect(_item_catalog != null and _block_catalog != null and _item_catalog.validate(_block_catalog), "item catalog did not load or validate")
	if _catalog == null or _block_catalog == null or _item_catalog == null:
		_finish(0, 0)
		return
	_test_catalog_and_modules()
	_test_rotations()
	_test_variable_aperture_generation()
	_test_optional_socket_sealing()
	_test_extensible_room_requirements()
	_test_semantic_set_determinism()
	_test_seed_identity_and_failures()
	_test_entrance_placement_stability()
	var fuzz_started := Time.get_ticks_msec()
	var successful_seeds := _test_generation_fuzz()
	var fuzz_msec := Time.get_ticks_msec() - fuzz_started
	_test_level_state_and_mesher()
	_test_level_chest_overlay()
	_test_gameplay_location_state()
	_finish(successful_seeds, fuzz_msec)

func _test_catalog_and_modules() -> void:
	_expect(StructureCell.VOID == -1, "VOID encoding changed")
	_expect(StructureCell.AIR == 0, "AIR encoding changed")
	_expect(StructureCell.is_valid(StructureCell.VOID), "VOID is not a valid module cell")
	_expect(StructureCell.is_valid(StructureCell.AIR), "AIR is not a valid module cell")
	_expect(StructureCell.is_valid(BlockId.Type.STONE), "stable stone block ID is invalid")
	_expect(not StructureCell.is_valid(BlockId.Type.TORCH), "torch block ID was accepted as a dense module cell")
	_expect(not StructureCell.is_valid(BlockId.Type.WATER), "water block ID was accepted as a dense module cell")
	_expect(not StructureCell.is_valid(-2), "unknown negative cell value was accepted")
	_expect(not StructureCell.is_valid(BlockId.Type.COUNT), "unknown positive block ID was accepted")
	_expect(LevelSocketDefinition.is_valid_unused_fill_block(StructureCell.AIR), "required connection sentinel is invalid")
	_expect(LevelSocketDefinition.is_valid_unused_fill_block(BlockId.Type.STONE_BRICKS), "solid socket fill block is invalid")
	_expect(not LevelSocketDefinition.is_valid_unused_fill_block(StructureCell.VOID), "VOID socket fill block was accepted")
	_expect(not LevelSocketDefinition.is_valid_unused_fill_block(BlockId.Type.TORCH), "torch socket fill block was accepted")
	_expect(not LevelSocketDefinition.is_valid_unused_fill_block(BlockId.Type.WATER), "water socket fill block was accepted")
	_expect(not LevelSocketDefinition.is_valid_unused_fill_block(BlockId.Type.COUNT), "unknown socket fill block was accepted")
	_expect(_catalog.validate(), "level catalog validation failed")
	var chest_slot_count := _block_catalog.get_definition(BlockId.Type.CHEST).container.get_slot_count()
	_expect(LevelLootCatalogValidator.validate(_catalog, _item_catalog, chest_slot_count), "level chest loot catalog validation failed")
	_expect(_catalog.modules.size() == EXPECTED_MODULE_IDS.size(), "catalog must contain exactly the expected live stone modules")
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
	_expect(definition.format_version == LevelDefinition.FORMAT_VERSION, "stone dungeon format version changed")
	_expect(definition.one_time_chest_reward != null, "stone dungeon one-time chest reward is missing")
	if definition.one_time_chest_reward != null:
		var reward := definition.one_time_chest_reward
		_expect(reward.reward_id == &"stone_dungeon_one_time_chest_reward", "stone dungeon one-time reward ID changed")
		_expect(reward.loot_bundle != null and reward.loot_bundle.id == &"stone_dungeon_one_time_chest_reward_loot", "stone dungeon one-time reward bundle changed")
		if reward.loot_bundle != null:
			_expect(reward.loot_bundle.max_rewards == 1 and reward.loot_bundle.fixed_entries.size() == 1 and reward.loot_bundle.weighted_candidates.is_empty(), "stone dungeon one-time reward is not a guaranteed single entry")
			if reward.loot_bundle.fixed_entries.size() == 1:
				var drop := reward.loot_bundle.fixed_entries[0].drop
				_expect(drop != null and drop.item == _item_catalog.get_definition(&"basic_rune"), "stone dungeon one-time reward is not the canonical Basic Rune")
	_expect(definition.presentation != null and definition.presentation.terrain_shader != null, "stone dungeon presentation is missing")
	_expect(definition.presentation.terrain_shader.resource_path == "res://levels/presentation/level_terrain.gdshader", "stone dungeon terrain shader is not content-driven")
	_expect(definition.presentation.return_door_block_id == BlockId.Type.LOG, "stone dungeon return-door block changed")
	var entrance_definition := load(ENTRANCE_DEFINITION_PATH) as LevelEntranceDefinition
	_expect(entrance_definition != null and entrance_definition.validate(_catalog), "meadow dungeon entrance definition is invalid")
	if entrance_definition != null:
		_expect(entrance_definition.entrance_id == &"meadow_dungeon" and entrance_definition.level_id == LEVEL_ID, "meadow entrance IDs changed")
		_expect(entrance_definition.arch_block_id == BlockId.Type.STONE and entrance_definition.door_block_id == BlockId.Type.LOG, "meadow entrance blocks changed")
	_expect(definition.start_module_id == &"stone_entry_path", "stone entry path is not the selected start module")
	var entry_module := _catalog.get_module(definition.start_module_id)
	_expect(entry_module.spawn_marker.cell == Vector3i(7, 1, 3) and entry_module.spawn_marker.facing == LevelSocketDefinition.Direction.EAST, "stone entry player spawn changed")
	_expect(entry_module.return_door_marker.cell == Vector3i(3, 1, 1) and entry_module.return_door_marker.facing == LevelSocketDefinition.Direction.NORTH, "stone shared entrance/exit door changed")
	_expect(is_equal_approx(_catalog.get_module(&"stone_hallway").weight, 4.0), "stone hallway weight changed")
	_expect(is_equal_approx(_catalog.get_module(&"stone_master_room").weight, 1.0), "stone master-room weight changed")
	_expect(is_equal_approx(_catalog.get_module(&"stone_room").weight, 1.0), "stone room weight changed")
	_expect(is_equal_approx(_catalog.get_module(&"stone_chest_room").weight, 1.0), "stone chest-room weight changed")
	_expect(definition.maximum_extent == Vector3i(96, 16, 96), "level extent bound changed")
	_expect(definition.maximum_explored_states == 10000, "search-state bound changed")
	var actual_hallway_ids := definition.hallway_module_ids.duplicate()
	actual_hallway_ids.sort()
	var expected_hallway_ids := EXPECTED_HALLWAY_MODULE_IDS.duplicate()
	expected_hallway_ids.sort()
	_expect(actual_hallway_ids == expected_hallway_ids, "stone hallway pool changed: %s" % str(actual_hallway_ids))
	_expect(_room_requirement_counts(definition) == EXPECTED_ROOM_COUNTS, "stone room requirements changed: %s" % str(_room_requirement_counts(definition)))
	for requirement in definition.room_requirements:
		if requirement.room_type_id == &"chest_room":
			_expect(requirement.encounter == null, "stone chest room must be passive")
			_expect(requirement.chest_loot_bundle != null and requirement.chest_loot_bundle.id == &"stone_dungeon_chest", "stone chest room loot bundle changed")
			if requirement.chest_loot_bundle != null:
				_expect(requirement.chest_loot_bundle.max_rewards == 3, "stone chest reward limit changed")
				_expect(requirement.chest_loot_bundle.fixed_entries.size() == 1 and requirement.chest_loot_bundle.weighted_candidates.size() == 2, "stone chest loot composition changed")
				for candidate in requirement.chest_loot_bundle.weighted_candidates:
					_expect(candidate.drop.item.id != &"basic_rune", "repeatable stone chest directly awards Basic Rune")
					if candidate.drop.equipment_roll != null:
						_expect(candidate.drop.equipment_roll.fixed_runes.is_empty() and candidate.drop.equipment_roll.random_runes.is_empty(), "repeatable stone chest equipment bypasses Basic Rune progression")
			continue
		_expect(requirement.chest_loot_bundle == null, "encounter room unexpectedly owns chest loot: %s" % requirement.room_type_id)
		_expect(requirement.encounter != null and requirement.encounter.validate(String(requirement.room_type_id)), "stone room encounter is invalid: %s" % requirement.room_type_id)
		if requirement.encounter == null:
			continue
		_expect(requirement.encounter.enemy_groups.size() == 1, "stone room encounter does not have exactly one enemy group: %s" % requirement.room_type_id)
		if requirement.encounter.enemy_groups.size() == 1:
			var group := requirement.encounter.enemy_groups[0]
			_expect(group.entity_id == &"zombie", "stone room encounter does not use zombies: %s" % requirement.room_type_id)
			_expect(group.count == int(EXPECTED_ENCOUNTER_COUNTS[requirement.room_type_id]), "stone room encounter count changed: %s" % requirement.room_type_id)
	_expect(definition.get_room_count() == LIVE_ROOM_COUNT, "stone required room count changed")
	_expect(definition.get_hallway_count(entry_module.sockets.size()) == LIVE_HALLWAY_COUNT, "stone required hallway count changed")
	_expect(definition.get_target_module_count(entry_module.sockets.size()) == LIVE_TARGET_MODULE_COUNT, "stone target module count changed")
	var stone_module_ids: Array[StringName] = [definition.start_module_id]
	stone_module_ids.append_array(definition.hallway_module_ids)
	for requirement in definition.room_requirements:
		stone_module_ids.append_array(requirement.module_ids)
	var start_count := 0
	for module in _catalog.modules:
		_expect(module != null and module.validate(), "module failed validation: %s" % module.module_id)
		_expect(module.resource_path.ends_with(".tres"), "module is not backed by a typed resource: %s" % module.module_id)
		if stone_module_ids.has(module.module_id):
			_expect(module.resource_path.get_base_dir() == STONE_MODULE_DIRECTORY, "stone dungeon module escaped its content directory: %s" % module.module_id)
		_expect(module.cells.size() == module.size.x * module.size.y * module.size.z, "dense cell count changed for %s" % module.module_id)
		_expect(module.weight > 0.0, "non-positive module weight for %s" % module.module_id)
		var seen_sockets: Dictionary = {}
		for socket in module.sockets:
			_expect(not seen_sockets.has(socket.socket_id), "duplicate socket ID in %s" % module.module_id)
			seen_sockets[socket.socket_id] = true
			if module.module_id == definition.start_module_id or module.module_id in definition.hallway_module_ids:
				_expect(socket.requires_connection(), "production connector socket is sealable in %s" % module.module_id)
			else:
				_expect(socket.unused_fill_block_id == BlockId.Type.STONE_BRICKS, "production room socket fill is not Stone Bricks in %s" % module.module_id)
			_expect(_is_boundary(socket.cell, module.size, socket.direction), "socket is not on its declared boundary in %s" % module.module_id)
			var aperture := module.socket_aperture_cells(socket)
			_expect(aperture.size() == 18, "production socket opening is not 18 cells in %s" % module.module_id)
			_expect(LevelSocketAperture.dimensions(aperture, socket.direction) == Vector2i(3, 6), "production socket opening is not 3x6 in %s" % module.module_id)
			for aperture_cell in aperture:
				_expect(module.cell_at(aperture_cell) == StructureCell.AIR, "socket aperture is not AIR in %s" % module.module_id)
			var inward := -LevelSocketDefinition.vector_for(socket.direction)
			_expect(module.cell_at(socket.cell + inward) == StructureCell.AIR, "socket does not open into lower interior AIR in %s" % module.module_id)
			_expect(module.cell_at(socket.cell + Vector3i.UP + inward) == StructureCell.AIR, "socket does not open into upper interior AIR in %s" % module.module_id)
			_expect(StructureCell.is_structure_solid(module.cell_at(socket.cell + Vector3i.DOWN)), "socket floor is missing in %s" % module.module_id)
		var seen_torches: Dictionary = {}
		for torch in module.torches:
			_expect(not seen_torches.has(torch.cell), "duplicate torch cell in %s" % module.module_id)
			seen_torches[torch.cell] = true
			_expect(module.cell_at(torch.cell) == StructureCell.AIR, "torch is not in AIR in %s" % module.module_id)
			var support := torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction)
			_expect(StructureCell.is_in_bounds(support, module.size) and StructureCell.is_structure_solid(module.cell_at(support)), "torch wall support is missing in %s" % module.module_id)
		for y in module.size.y:
			for z in module.size.z:
				for x in module.size.x:
					var cell := Vector3i(x, y, z)
					var index := StructureCell.index_of(cell, module.size)
					_expect(index >= 0 and index < module.cells.size(), "dense index escaped module bounds in %s" % module.module_id)
					_expect(module.cell_at(cell) == module.cells[index], "dense cell lookup mismatch in %s" % module.module_id)
					_expect(StructureCell.is_valid(module.cell_at(cell)), "module contains an invalid cell in %s" % module.module_id)
		if module.spawn_marker != null:
			start_count += 1
			_expect(module.module_id == definition.start_module_id, "non-entry module has entry markers: %s" % module.module_id)
			_expect(module.return_door_marker != null, "entry module entrance/exit marker is missing")
			_test_marker(module, module.spawn_marker, "spawn")
			_test_marker(module, module.return_door_marker, "entrance/exit door")
		else:
			_expect(module.return_door_marker == null, "module has an unpaired entrance/exit marker: %s" % module.module_id)
		if module.module_id in definition.hallway_module_ids:
			_expect(module.sockets.size() == 2, "hallway module does not have exactly two sockets: %s" % module.module_id)
		elif module.module_id != definition.start_module_id:
			var requirement := _room_requirement_for_module(definition, module.module_id)
			_expect(requirement != null, "live module has no room requirement: %s" % module.module_id)
			if requirement != null:
				_expect((module.chest_marker != null) == (requirement.chest_loot_bundle != null), "module chest marker and loot bundle differ: %s" % module.module_id)
			if requirement != null and requirement.encounter == null:
				_expect(module.enemy_spawn_zones.is_empty() and module.get_enemy_spawn_candidate_cells().is_empty(), "passive room module has enemy spawn zones: %s" % module.module_id)
			else:
				_expect(not module.enemy_spawn_zones.is_empty() and not module.get_enemy_spawn_candidate_cells().is_empty(), "encounter room module has no usable enemy spawn zone: %s" % module.module_id)
	_expect(start_count == 1, "catalog must have exactly one entry module")

func _test_marker(module: LevelModuleDefinition, marker: LevelMarkerDefinition, label: String) -> void:
	_expect(StructureCell.is_in_bounds(marker.cell, module.size), "%s marker is outside %s" % [label, module.module_id])
	_expect(module.cell_at(marker.cell) == StructureCell.AIR, "%s marker is not in AIR in %s" % [label, module.module_id])
	_expect(StructureCell.is_in_bounds(marker.cell + Vector3i.UP, module.size) and module.cell_at(marker.cell + Vector3i.UP) == StructureCell.AIR, "%s marker has no headroom in %s" % [label, module.module_id])
	_expect(StructureCell.is_structure_solid(module.cell_at(marker.cell + Vector3i.DOWN)), "%s marker has no floor in %s" % [label, module.module_id])

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
						_expect(StructureCell.is_in_bounds(transformed, rotated_size), "rotation escaped bounds for %s q%d" % [module.module_id, quarter_turns])
						_expect(not occupied.has(transformed), "rotation collapsed cells for %s q%d" % [module.module_id, quarter_turns])
						occupied[transformed] = module.cell_at(source)
			_expect(occupied.size() == module.cells.size(), "rotation did not preserve dense cell count for %s q%d" % [module.module_id, quarter_turns])
			for socket in module.sockets:
				var transformed_socket := module.rotate_cell(socket.cell, quarter_turns)
				var transformed_direction := LevelSocketDefinition.rotate(socket.direction, quarter_turns)
				_expect(_is_boundary(transformed_socket, rotated_size, transformed_direction), "rotated socket left its boundary for %s q%d" % [module.module_id, quarter_turns])
				_expect(occupied[transformed_socket] == StructureCell.AIR, "rotated lower aperture changed for %s q%d" % [module.module_id, quarter_turns])
				_expect(occupied[transformed_socket + Vector3i.UP] == StructureCell.AIR, "rotated upper aperture changed for %s q%d" % [module.module_id, quarter_turns])
			for torch in module.torches:
				var transformed_torch := module.rotate_cell(torch.cell, quarter_turns)
				var transformed_direction := LevelSocketDefinition.rotate(torch.wall_direction, quarter_turns)
				var expected_support := module.rotate_cell(torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction), quarter_turns)
				_expect(transformed_torch + LevelSocketDefinition.vector_for(transformed_direction) == expected_support, "rotated torch direction detached from support in %s q%d" % [module.module_id, quarter_turns])
				_expect(int(occupied[transformed_torch]) == StructureCell.AIR and StructureCell.is_structure_solid(int(occupied[expected_support])), "rotated torch cells changed in %s q%d" % [module.module_id, quarter_turns])
			if module.spawn_marker != null:
				_test_rotated_marker(module, module.spawn_marker, quarter_turns, occupied, "spawn")
				_test_rotated_marker(module, module.return_door_marker, quarter_turns, occupied, "return")
		_expect(module.rotate_cell(Vector3i.ZERO, 4) == Vector3i.ZERO, "full rotation is not identity for %s" % module.module_id)
		_expect(module.rotate_cell(Vector3i.ZERO, -4) == Vector3i.ZERO, "negative full rotation is not identity for %s" % module.module_id)

func _test_rotated_marker(module: LevelModuleDefinition, marker: LevelMarkerDefinition, quarter_turns: int, occupied: Dictionary, label: String) -> void:
	var transformed := module.rotate_cell(marker.cell, quarter_turns)
	var transformed_head := module.rotate_cell(marker.cell + Vector3i.UP, quarter_turns)
	var transformed_floor := module.rotate_cell(marker.cell + Vector3i.DOWN, quarter_turns)
	_expect(int(occupied[transformed]) == StructureCell.AIR, "rotated %s marker changed in %s q%d" % [label, module.module_id, quarter_turns])
	_expect(int(occupied[transformed_head]) == StructureCell.AIR, "rotated %s marker headroom changed in %s q%d" % [label, module.module_id, quarter_turns])
	_expect(StructureCell.is_structure_solid(int(occupied[transformed_floor])), "rotated %s marker floor changed in %s q%d" % [label, module.module_id, quarter_turns])
	_expect(LevelSocketDefinition.rotate(marker.facing, quarter_turns) == ((int(marker.facing) + quarter_turns) % 4 as LevelSocketDefinition.Direction), "rotated %s marker facing changed in %s q%d" % [label, module.module_id, quarter_turns])

func _test_variable_aperture_generation() -> void:
	var start := _make_aperture_module(
		&"aperture_start",
		[{"id": &"east", "direction": LevelSocketDefinition.Direction.EAST, "width": 3, "height": 6, "seed_offset": 1}],
		true,
	)
	var hub := _make_aperture_module(
		&"aperture_hub",
		[
			{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.STONE_BRICKS},
			{"id": &"east", "direction": LevelSocketDefinition.Direction.EAST, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.STONE_BRICKS},
		],
		false,
	)
	var hall := _make_aperture_module(
		&"aperture_hall",
		[
			{"id": &"north", "direction": LevelSocketDefinition.Direction.NORTH, "width": 3, "height": 6, "seed_offset": 0},
			{"id": &"south", "direction": LevelSocketDefinition.Direction.SOUTH, "width": 3, "height": 6, "seed_offset": 2},
		],
		false,
	)
	var leaf := _make_aperture_module(
		&"aperture_leaf",
		[{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.STONE_BRICKS}],
		false,
	)
	var definition := _make_level_definition(
		&"variable_aperture_level",
		start.module_id,
		[hall.module_id],
		[
			_make_room_requirement(&"hub_room", 1, [hub.module_id]),
			_make_room_requirement(&"leaf_room", 1, [leaf.module_id]),
		]
	)
	var catalog := LevelCatalog.new()
	catalog.modules.assign([start, hub, hall, leaf])
	catalog.levels.append(definition)
	_expect(catalog.validate(), "variable-aperture catalog failed validation")
	var result := LevelGenerator.new().generate(catalog, definition.level_id, 81, &"variable_aperture", Vector3i.ZERO)
	_expect(result.succeeded, "matching 3×6 openings did not generate: %s" % result.failure_reason)
	if result.succeeded:
		_expect(result.layout.placed_modules.size() == 4, "variable-aperture layout placed the wrong module count")
		var seam_edges: Dictionary = {}
		var records: Array[Dictionary] = []
		var rotated_hall := false
		for placement_index in result.layout.placed_modules.size():
			var placement := result.layout.placed_modules[placement_index]
			if placement.definition.module_id == hall.module_id:
				rotated_hall = placement.rotation == 1 or placement.rotation == 3
			for socket in placement.definition.sockets:
				var aperture := placement.world_socket_aperture(socket)
				_expect(aperture.size() == 18, "generated 3×6 socket lost aperture cells")
				records.append({
					"placement": placement_index,
					"direction": placement.world_direction(socket.direction),
					"aperture": aperture,
				})
		_expect(rotated_hall, "variable-aperture hallway did not exercise quarter-turn matching")
		for record_index in records.size():
			var record := records[record_index]
			var direction := record["direction"] as LevelSocketDefinition.Direction
			var outward := LevelSocketDefinition.vector_for(direction)
			var aperture := record["aperture"] as Array[Vector3i]
			var partner_count := 0
			for other_index in records.size():
				if other_index == record_index:
					continue
				var other := records[other_index]
				if int(other["placement"]) == int(record["placement"]) or int(other["direction"]) != int(LevelSocketDefinition.opposite(direction)):
					continue
				if _translated_cells_equal(aperture, outward, other["aperture"] as Array[Vector3i]):
					partner_count += 1
			_expect(partner_count == 1, "variable-aperture socket did not have exactly one matching partner")
			for cell in aperture:
				var neighbor := cell + outward
				_expect(result.layout.get_cell(cell) == StructureCell.AIR and result.layout.get_cell(neighbor) == StructureCell.AIR, "variable-aperture seam was not open")
				seam_edges[_edge_key(cell, neighbor)] = true
		_expect(seam_edges.size() == 54, "variable-aperture layout did not create three 18-cell seams")
	var small_leaf := _make_aperture_module(
		&"small_aperture_leaf",
		[{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 1, "height": 2, "seed_offset": 0, "fill": BlockId.Type.STONE_BRICKS}],
		false,
	)
	var mismatch_definition := _make_level_definition(
		&"mismatched_aperture_level",
		start.module_id,
		[hall.module_id],
		[
			_make_room_requirement(&"hub_room", 1, [hub.module_id]),
			_make_room_requirement(&"leaf_room", 1, [small_leaf.module_id]),
		]
	)
	var mismatch_catalog := LevelCatalog.new()
	mismatch_catalog.modules.assign([start, hub, hall, small_leaf])
	mismatch_catalog.levels.append(mismatch_definition)
	_expect(mismatch_catalog.validate(), "mismatched-aperture catalog was structurally invalid")
	var mismatch := LevelGenerator.new().generate(mismatch_catalog, mismatch_definition.level_id, 81, &"variable_aperture", Vector3i.ZERO)
	_expect(not mismatch.succeeded, "3×6 opening connected to a 1×2 room")
	_expect(mismatch.failure_code == LevelGenerationResult.FailureCode.NO_LAYOUT, "structurally valid aperture mismatch returned the wrong failure")
	var shape_leaf := _make_aperture_module(
		&"shape_aperture_leaf",
		[{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.STONE_BRICKS}],
		false,
	)
	var missing_profile_cell := _aperture_boundary_cell(LevelSocketDefinition.Direction.WEST, 2, 6, shape_leaf.size)
	shape_leaf.cells[StructureCell.index_of(missing_profile_cell, shape_leaf.size)] = BlockId.Type.STONE
	_expect(shape_leaf.validate(), "asymmetric 3×6 room failed validation")
	_expect(LevelSocketAperture.dimensions(shape_leaf.socket_aperture_cells(shape_leaf.sockets[0]), LevelSocketDefinition.Direction.WEST) == Vector2i(3, 6), "asymmetric room lost its 3×6 bounds")
	var shape_definition := _make_level_definition(
		&"shape_aperture_level",
		start.module_id,
		[hall.module_id],
		[
			_make_room_requirement(&"hub_room", 1, [hub.module_id]),
			_make_room_requirement(&"leaf_room", 1, [shape_leaf.module_id]),
		]
	)
	var shape_catalog := LevelCatalog.new()
	shape_catalog.modules.assign([start, hub, hall, shape_leaf])
	shape_catalog.levels.append(shape_definition)
	_expect(shape_catalog.validate(), "asymmetric-aperture catalog was structurally invalid")
	var shape_mismatch := LevelGenerator.new().generate(shape_catalog, shape_definition.level_id, 81, &"variable_aperture", Vector3i.ZERO)
	_expect(not shape_mismatch.succeeded, "different opening shapes with identical 3×6 bounds connected")
	_expect(shape_mismatch.failure_code == LevelGenerationResult.FailureCode.NO_LAYOUT, "shape mismatch returned the wrong generation failure")

func _test_optional_socket_sealing() -> void:
	var start := _make_aperture_module(
		&"optional_start",
		[{"id": &"east", "direction": LevelSocketDefinition.Direction.EAST, "width": 3, "height": 6, "seed_offset": 1}],
		true,
	)
	var room := _make_aperture_module(
		&"optional_room",
		[
			{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.STONE_BRICKS},
			{"id": &"north", "direction": LevelSocketDefinition.Direction.NORTH, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.DIRT},
			{"id": &"south", "direction": LevelSocketDefinition.Direction.SOUTH, "width": 3, "height": 6, "seed_offset": 1, "fill": BlockId.Type.STONE_BRICKS},
		],
		false,
	)
	var definition := _make_level_definition(
		&"optional_sealing_level",
		start.module_id,
		[],
		[_make_room_requirement(&"sealed_room", 1, [room.module_id])]
	)
	var catalog := LevelCatalog.new()
	catalog.modules.assign([start, room])
	catalog.levels.append(definition)
	_expect(catalog.validate(), "optional-sealing catalog failed validation")
	var result := LevelGenerator.new().generate(catalog, definition.level_id, 91, &"optional_sealing", Vector3i.ZERO)
	_expect(result.succeeded, "optional socket did not seal: %s" % result.failure_reason)
	if not result.succeeded:
		return
	_expect(result.layout.placed_modules.size() == 2, "optional-socket layout placed the wrong module count")
	var records := _socket_records(result.layout)
	var connected_room_sockets := 0
	var sealed_room_sockets := 0
	for record_index in records.size():
		var record := records[record_index]
		if int(record["placement"]) != 1:
			continue
		var partner := _socket_partner_index(records, record_index)
		var placement := result.layout.placed_modules[1] as LevelPlacedModule
		var socket := placement.definition.sockets[int(record["socket"])]
		if partner >= 0:
			connected_room_sockets += 1
			for aperture_cell in record["aperture"] as Array[Vector3i]:
				_expect(result.layout.get_cell(aperture_cell) == StructureCell.AIR, "connected optional socket was sealed")
		else:
			sealed_room_sockets += 1
			var inward := -LevelSocketDefinition.vector_for(record["direction"] as LevelSocketDefinition.Direction)
			for aperture_cell in record["aperture"] as Array[Vector3i]:
				_expect(result.layout.get_cell(aperture_cell) == socket.unused_fill_block_id, "optional room socket ignored its fill block")
				_expect(result.layout.get_cell(aperture_cell + inward) == StructureCell.AIR, "optional socket sealing changed inward clearance")
	_expect(connected_room_sockets == 1 and sealed_room_sockets == 2, "optional room sockets did not split into one connection and two seals")
	var repeated := LevelGenerator.new().generate(catalog, definition.level_id, 91, &"optional_sealing", Vector3i.ZERO)
	_expect(repeated.succeeded and _layout_digest(repeated.layout) == _layout_digest(result.layout), "optional socket sealing is not deterministic")

func _test_extensible_room_requirements() -> void:
	var fixture := _make_extensible_fixture(false)
	var catalog := fixture["catalog"] as LevelCatalog
	var definition := fixture["definition"] as LevelDefinition
	_expect(catalog.validate(), "extensible room catalog failed validation")
	var seen_boss_modules: Dictionary = {}
	var generator := LevelGenerator.new()
	for seed in range(32):
		var result := generator.generate(catalog, definition.level_id, seed, &"extensible_rooms", Vector3i.ZERO)
		_expect(result.succeeded, "extensible room generation failed for seed %d: %s" % [seed, result.failure_reason])
		if not result.succeeded:
			continue
		var counts := _layout_room_counts(result.layout)
		_expect(counts == {&"hub_room": 1, &"boss_room": 1}, "extensible room quota changed for seed %d: %s" % [seed, str(counts)])
		for placement in result.layout.placed_modules:
			if placement.room_type_id == &"boss_room":
				seen_boss_modules[placement.definition.module_id] = true
	_expect(seen_boss_modules.has(&"boss_room_a") and seen_boss_modules.has(&"boss_room_b"), "weighted boss-room variants were not both reachable")

func _test_semantic_set_determinism() -> void:
	var forward := _make_extensible_fixture(false)
	var reversed := _make_extensible_fixture(true)
	var forward_catalog := forward["catalog"] as LevelCatalog
	var reversed_catalog := reversed["catalog"] as LevelCatalog
	var forward_definition := forward["definition"] as LevelDefinition
	var reversed_definition := reversed["definition"] as LevelDefinition
	_expect(forward_catalog.validate() and reversed_catalog.validate(), "semantic-order catalogs failed validation")
	var first := LevelGenerator.new().generate(forward_catalog, forward_definition.level_id, 417, &"semantic_order", Vector3i(3, 0, -8))
	var second := LevelGenerator.new().generate(reversed_catalog, reversed_definition.level_id, 417, &"semantic_order", Vector3i(3, 0, -8))
	_expect(first.succeeded and second.succeeded, "semantic-order generation failed")
	if first.succeeded and second.succeeded:
		_expect(_layout_digest(first.layout) == _layout_digest(second.layout), "requirements, module pools, or catalog order changed deterministic output")
		_expect(_topology_digest(first.layout) == _topology_digest(second.layout), "requirements, module pools, or catalog order changed deterministic topology")

func _make_extensible_fixture(reverse_semantic_sets: bool) -> Dictionary:
	var start := _make_aperture_module(
		&"extensible_start",
		[{"id": &"east", "direction": LevelSocketDefinition.Direction.EAST, "width": 1, "height": 2, "seed_offset": 0}],
		true,
	)
	var hall_a := _make_aperture_module(
		&"extensible_hall_a",
		[
			{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 1, "height": 2, "seed_offset": 0},
			{"id": &"east", "direction": LevelSocketDefinition.Direction.EAST, "width": 1, "height": 2, "seed_offset": 0},
		],
		false,
	)
	var hall_b := hall_a.duplicate(true) as LevelModuleDefinition
	hall_b.module_id = &"extensible_hall_b"
	var hub := _make_aperture_module(
		&"hub_room",
		[
			{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 1, "height": 2, "seed_offset": 0, "fill": BlockId.Type.STONE_BRICKS},
			{"id": &"east", "direction": LevelSocketDefinition.Direction.EAST, "width": 1, "height": 2, "seed_offset": 0, "fill": BlockId.Type.STONE_BRICKS},
		],
		false,
	)
	var boss_a := _make_aperture_module(
		&"boss_room_a",
		[{"id": &"west", "direction": LevelSocketDefinition.Direction.WEST, "width": 1, "height": 2, "seed_offset": 0, "fill": BlockId.Type.STONE_BRICKS}],
		false,
	)
	var boss_b := boss_a.duplicate(true) as LevelModuleDefinition
	boss_b.module_id = &"boss_room_b"
	var hallway_ids: Array[StringName] = [hall_a.module_id, hall_b.module_id]
	var boss_ids: Array[StringName] = [boss_a.module_id, boss_b.module_id]
	var modules: Array[LevelModuleDefinition] = [start, hall_a, hall_b, hub, boss_a, boss_b]
	if reverse_semantic_sets:
		hallway_ids.reverse()
		boss_ids.reverse()
		modules.reverse()
	var requirements: Array[LevelRoomRequirement] = [
		_make_room_requirement(&"hub_room", 1, [hub.module_id]),
		_make_room_requirement(&"boss_room", 1, boss_ids),
	]
	if reverse_semantic_sets:
		requirements.reverse()
	var definition := _make_level_definition(&"extensible_level", start.module_id, hallway_ids, requirements)
	var catalog := LevelCatalog.new()
	catalog.modules.assign(modules)
	catalog.levels.append(definition)
	return {"catalog": catalog, "definition": definition}

func _make_aperture_module(module_id: StringName, socket_specs: Array[Dictionary], with_markers: bool) -> LevelModuleDefinition:
	var module := LevelModuleDefinition.new()
	module.format_version = LevelModuleDefinition.CURRENT_FORMAT_VERSION
	module.module_id = module_id
	module.size = Vector3i(7, 8, 7)
	module.cells.resize(module.size.x * module.size.y * module.size.z)
	module.cells.fill(BlockId.Type.STONE)
	for y in range(1, module.size.y - 1):
		for z in range(1, module.size.z - 1):
			for x in range(1, module.size.x - 1):
				module.cells[StructureCell.index_of(Vector3i(x, y, z), module.size)] = StructureCell.AIR
	for spec in socket_specs:
		var direction := spec["direction"] as LevelSocketDefinition.Direction
		var width := int(spec["width"])
		var height := int(spec["height"])
		var transverse_start := (module.size.x - width) / 2 if direction == LevelSocketDefinition.Direction.NORTH or direction == LevelSocketDefinition.Direction.SOUTH else (module.size.z - width) / 2
		for y in range(1, height + 1):
			for transverse in range(transverse_start, transverse_start + width):
				var cell := _aperture_boundary_cell(direction, transverse, y, module.size)
				module.cells[StructureCell.index_of(cell, module.size)] = StructureCell.AIR
		var socket := LevelSocketDefinition.new()
		socket.socket_id = spec["id"] as StringName
		socket.cell = _aperture_boundary_cell(direction, transverse_start + int(spec["seed_offset"]), 1, module.size)
		socket.direction = direction
		socket.unused_fill_block_id = int(spec.get("fill", StructureCell.AIR))
		module.sockets.append(socket)
	if with_markers:
		module.spawn_marker = LevelMarkerDefinition.new()
		module.spawn_marker.cell = Vector3i(2, 1, 3)
		module.spawn_marker.facing = LevelSocketDefinition.Direction.EAST
		module.return_door_marker = LevelMarkerDefinition.new()
		module.return_door_marker.cell = Vector3i(4, 1, 3)
		module.return_door_marker.facing = LevelSocketDefinition.Direction.WEST
	var spawn_zone := LevelEnemySpawnZone.new()
	spawn_zone.zone_id = &"center"
	spawn_zone.minimum_feet_cell = Vector3i(3, 1, 3)
	spawn_zone.maximum_feet_cell = Vector3i(3, 1, 3)
	module.enemy_spawn_zones.append(spawn_zone)
	_expect(module.validate(), "synthetic aperture module failed validation: %s" % module_id)
	return module

func _make_level_definition(
	level_id: StringName,
	start_id: StringName,
	hallway_ids: Array,
	requirements: Array,
) -> LevelDefinition:
	var definition := LevelDefinition.new()
	definition.format_version = LevelDefinition.FORMAT_VERSION
	definition.level_id = level_id
	definition.presentation = _catalog.get_level(LEVEL_ID).presentation
	definition.start_module_id = start_id
	definition.hallway_module_ids.assign(hallway_ids)
	definition.room_requirements.assign(requirements)
	definition.maximum_extent = Vector3i(64, 16, 64)
	definition.maximum_explored_states = 1000
	return definition

func _make_room_requirement(room_type_id: StringName, count: int, module_ids: Array) -> LevelRoomRequirement:
	var requirement := LevelRoomRequirement.new()
	requirement.room_type_id = room_type_id
	requirement.count = count
	requirement.module_ids.assign(module_ids)
	var enemy_group := LevelEnemyGroupDefinition.new()
	enemy_group.entity_id = &"zombie"
	var encounter := LevelRoomEncounterDefinition.new()
	encounter.enemy_groups.append(enemy_group)
	requirement.encounter = encounter
	return requirement

func _room_requirement_counts(definition: LevelDefinition) -> Dictionary:
	var counts: Dictionary = {}
	for requirement in definition.room_requirements:
		counts[requirement.room_type_id] = requirement.count
	return counts

func _room_type_for_module(definition: LevelDefinition, module_id: StringName) -> StringName:
	var requirement := _room_requirement_for_module(definition, module_id)
	return requirement.room_type_id if requirement != null else &""

func _room_requirement_for_module(definition: LevelDefinition, module_id: StringName) -> LevelRoomRequirement:
	for requirement in definition.room_requirements:
		if requirement.module_ids.has(module_id):
			return requirement
	return null

func _layout_room_counts(layout: LevelLayout) -> Dictionary:
	var counts: Dictionary = {}
	for placement in layout.placed_modules:
		if placement.room_type_id.is_empty():
			continue
		counts[placement.room_type_id] = int(counts.get(placement.room_type_id, 0)) + 1
	return counts

func _socket_records(layout: LevelLayout) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for placement_index in layout.placed_modules.size():
		var placement := layout.placed_modules[placement_index]
		for socket_index in placement.definition.sockets.size():
			var socket := placement.definition.sockets[socket_index]
			records.append({
				"placement": placement_index,
				"socket": socket_index,
				"direction": placement.world_direction(socket.direction),
				"aperture": placement.world_socket_aperture(socket),
			})
	return records

func _socket_partner_index(records: Array[Dictionary], record_index: int) -> int:
	var record := records[record_index]
	var direction := record["direction"] as LevelSocketDefinition.Direction
	var outward := LevelSocketDefinition.vector_for(direction)
	for other_index in records.size():
		if other_index == record_index:
			continue
		var other := records[other_index]
		if int(other["placement"]) == int(record["placement"]):
			continue
		if int(other["direction"]) == int(LevelSocketDefinition.opposite(direction)) and _translated_cells_equal(record["aperture"] as Array[Vector3i], outward, other["aperture"] as Array[Vector3i]):
			return other_index
	return -1

func _aperture_boundary_cell(
	direction: LevelSocketDefinition.Direction,
	transverse: int,
	y: int,
	size: Vector3i,
) -> Vector3i:
	match direction:
		LevelSocketDefinition.Direction.NORTH:
			return Vector3i(transverse, y, 0)
		LevelSocketDefinition.Direction.EAST:
			return Vector3i(size.x - 1, y, transverse)
		LevelSocketDefinition.Direction.SOUTH:
			return Vector3i(transverse, y, size.z - 1)
		LevelSocketDefinition.Direction.WEST:
			return Vector3i(0, y, transverse)
	return Vector3i.ZERO

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

func _test_entrance_placement_stability() -> void:
	var voxel_world := VoxelWorld.new(20, 36, 5, 12.0, _block_catalog)
	for x in range(-16, 17):
		for z in range(-16, 17):
			voxel_world.height_map_dict[Vector2i(x, z)] = 4
			voxel_world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	var spawn := Vector3(0.5, 5.0, 0.5)
	var entrance_seed := 1729
	var initial: Variant = LevelEntrancePlacement.find_position(voxel_world, spawn, entrance_seed)
	_expect(initial is Vector3, "flat meadow did not produce an entrance position")
	if not initial is Vector3:
		return
	var initial_position := initial as Vector3
	var horizontal_offset := Vector2(initial_position.x - spawn.x, initial_position.z - spawn.z)
	_expect(horizontal_offset.length() >= 6.0 and horizontal_offset.length() <= 13.0, "entrance escaped its configured spawn radius")
	var center := Vector3i(floori(initial_position.x), floori(initial_position.y), floori(initial_position.z))
	voxel_world.restore_block_edits({center: BlockId.Type.STONE}, {})
	var after_placement: Variant = LevelEntrancePlacement.find_position(voxel_world, spawn, entrance_seed)
	_expect(after_placement is Vector3 and (after_placement as Vector3).is_equal_approx(initial_position), "placed block changed the stable entrance coordinate")
	_expect(LevelEntrancePlacement.has_edit_conflict(voxel_world, initial_position), "placed edit in entrance footprint was not reported as a conflict")
	voxel_world.restore_block_edits({}, {center + Vector3i.DOWN: true})
	var after_removal: Variant = LevelEntrancePlacement.find_position(voxel_world, spawn, entrance_seed)
	_expect(after_removal is Vector3 and (after_removal as Vector3).is_equal_approx(initial_position), "removed terrain changed the stable entrance coordinate")
	_expect(LevelEntrancePlacement.has_edit_conflict(voxel_world, initial_position), "removed edit in entrance footprint was not reported as a conflict")
	voxel_world.restore_block_edits({}, {})
	_expect(not LevelEntrancePlacement.has_edit_conflict(voxel_world, initial_position), "clean entrance footprint was reported as conflicted")
	var protected_cells := LevelEntrancePlacement.get_protected_cells(initial_position)
	var protected_set: Dictionary = {}
	for cell in protected_cells:
		protected_set[cell] = true
	_expect(protected_cells.size() == 45 and protected_set.size() == 45, "entrance protection volume is not a unique 3x5x3 prism")
	_expect(protected_set.has(center) and protected_set.has(center + Vector3i.DOWN), "entrance protection omits doorway or foundation cells")
	voxel_world.protect_edit_cells(protected_cells)
	var blocked_placement := VoxelWorldTestFixture.commit_place(voxel_world, center, BlockId.Type.STONE)
	var blocked_mining := VoxelWorldTestFixture.commit_mine(voxel_world, center + Vector3i.DOWN)
	_expect(blocked_placement == null, "entrance headspace accepted a block placement")
	_expect(blocked_mining == null, "entrance foundation accepted mining")
	_expect(voxel_world.get_block_edit_count() == 0, "rejected entrance edits changed voxel state")

func _test_generation_fuzz() -> int:
	var successful_seeds := 0
	var generator := LevelGenerator.new()
	for seed_index in range(FUZZ_SEED_COUNT):
		var world_seed := seed_index - 500
		var entrance_coordinate := Vector3i(seed_index % 29 - 14, seed_index % 7, seed_index % 31 - 15)
		var first := generator.generate(_catalog, LEVEL_ID, world_seed, ENTRANCE_ID, entrance_coordinate)
		_expect(first.succeeded, "generation failed for fuzz seed %d: %s" % [seed_index, first.failure_reason])
		if not first.succeeded:
			continue
		successful_seeds += 1
		var fuzz_label := "fuzz seed %d" % seed_index
		_validate_exact_composition(first.layout, fuzz_label)
		_validate_module_graph(first.layout, fuzz_label)
		if seed_index % DEEP_FUZZ_INTERVAL == 0:
			_validate_layout(first.layout, seed_index)
			var first_digest := _layout_digest(first.layout)
			var second := generator.generate(_catalog, LEVEL_ID, world_seed, ENTRANCE_ID, entrance_coordinate)
			_expect(second.succeeded, "repeat generation failed for fuzz seed %d: %s" % [seed_index, second.failure_reason])
			if second.succeeded:
				_expect(_layout_digest(second.layout) == first_digest, "layout changed across identical generation for fuzz seed %d" % seed_index)
				_expect(_topology_digest(second.layout) == _topology_digest(first.layout), "topology changed across identical generation for fuzz seed %d" % seed_index)
	var golden_result := generator.generate(_catalog, LEVEL_ID, 1337, ENTRANCE_ID, Vector3i(7, 0, -9))
	_expect(golden_result.succeeded, "live fixed layout failed generation")
	if golden_result.succeeded:
		_validate_exact_composition(golden_result.layout, "live quota golden")
		_validate_module_graph(golden_result.layout, "live quota golden")
		var digest := _layout_digest(golden_result.layout)
		_expect(digest == EXPECTED_LIVE_GOLDEN_DIGEST, "live fixed layout digest changed: %s" % digest)
	_expect(successful_seeds == FUZZ_SEED_COUNT, "only %d/%d fuzz seeds generated" % [successful_seeds, FUZZ_SEED_COUNT])
	_expect(_saw_connected_optional_socket, "1,000-seed fuzz never observed a connected optional socket")
	_expect(_saw_sealed_optional_socket, "1,000-seed fuzz never observed a sealed optional socket")
	return successful_seeds

func _validate_exact_composition(layout: LevelLayout, label: String) -> void:
	var definition := _catalog.get_level(LEVEL_ID)
	_expect(layout.target_module_count == LIVE_TARGET_MODULE_COUNT, "target module count changed for %s" % label)
	_expect(layout.placed_modules.size() == LIVE_TARGET_MODULE_COUNT, "placed module count changed for %s" % label)
	_expect(_layout_room_counts(layout) == EXPECTED_ROOM_COUNTS, "room quotas changed for %s: %s" % [label, str(_layout_room_counts(layout))])
	var hallway_count := 0
	for placement_index in layout.placed_modules.size():
		var placement := layout.placed_modules[placement_index]
		if placement_index == 0:
			_expect(placement.definition.module_id == definition.start_module_id and placement.room_type_id.is_empty(), "entry placement role changed for %s" % label)
		elif placement.room_type_id.is_empty():
			_expect(placement.definition.module_id in definition.hallway_module_ids, "untyped placement is not a hallway for %s" % label)
			hallway_count += 1
		else:
			var expected_type := _room_type_for_module(definition, placement.definition.module_id)
			_expect(placement.room_type_id == expected_type, "room type %s does not own %s for %s" % [placement.room_type_id, placement.definition.module_id, label])
	_expect(hallway_count == LIVE_HALLWAY_COUNT, "hallway count changed for %s" % label)

func _validate_layout(layout: LevelLayout, seed_index: int) -> void:
	var label := "seed %d" % seed_index
	_expect(layout != null, "layout is null for %s" % label)
	if layout == null:
		return
	var definition := _catalog.get_level(LEVEL_ID)
	_validate_exact_composition(layout, label)
	_expect(layout.placed_modules.size() == layout.target_module_count, "placed count does not match target for %s" % label)
	_expect(layout.explored_state_count > 0 and layout.explored_state_count <= definition.maximum_explored_states, "explored-state count escaped bounds for %s" % label)
	var ownership: Dictionary = {}
	var rebuilt_min := Vector3i.ZERO
	var rebuilt_max := Vector3i.ZERO
	var has_rebuilt_bounds := false
	var socket_records: Array[Dictionary] = []
	var expected_torches: Dictionary = {}
	var expected_chests: Dictionary = {}
	var marker_count := 0
	for placement_index in layout.placed_modules.size():
		var placement := layout.placed_modules[placement_index]
		_expect(placement.definition != null and _catalog.has_module(placement.definition.module_id), "placement has unknown definition for %s" % label)
		_expect(placement.rotation >= 0 and placement.rotation < 4, "placement rotation escaped quarter turns for %s" % label)
		var module := placement.definition
		var optional_fill_by_cell: Dictionary = {}
		for socket in module.sockets:
			var aperture := placement.world_socket_aperture(socket)
			socket_records.append({
				"placement": placement_index,
				"cell": placement.world_cell(socket.cell),
				"direction": placement.world_direction(socket.direction),
				"aperture": aperture,
				"unused_fill_block_id": socket.unused_fill_block_id,
			})
			if socket.unused_fill_block_id == StructureCell.AIR:
				continue
			for aperture_cell in aperture:
				_expect(not optional_fill_by_cell.has(aperture_cell), "optional socket apertures overlap at %s for %s" % [aperture_cell, label])
				optional_fill_by_cell[aperture_cell] = socket.unused_fill_block_id
		for y in module.size.y:
			for z in module.size.z:
				for x in module.size.x:
					var local_cell := Vector3i(x, y, z)
					var value := module.cell_at(local_cell)
					if value == StructureCell.VOID:
						continue
					var world_cell := placement.world_cell(local_cell)
					_expect(not ownership.has(world_cell), "module overlap at %s for %s" % [world_cell, label])
					ownership[world_cell] = placement_index
					_expect(layout.has_cell(world_cell), "placement cell is unclaimed at %s for %s" % [world_cell, label])
					var actual_value := layout.get_cell(world_cell)
					if optional_fill_by_cell.has(world_cell):
						var optional_fill := int(optional_fill_by_cell[world_cell])
						_expect(actual_value == value or actual_value == optional_fill, "optional aperture has an unexpected value at %s for %s" % [world_cell, label])
					else:
						_expect(actual_value == value, "placement cell value changed at %s for %s" % [world_cell, label])
					if not has_rebuilt_bounds:
						rebuilt_min = world_cell
						rebuilt_max = world_cell
						has_rebuilt_bounds = true
					else:
						rebuilt_min = rebuilt_min.min(world_cell)
						rebuilt_max = rebuilt_max.max(world_cell)
		for torch in module.torches:
			var torch_cell := placement.world_cell(torch.cell)
			var torch_direction := placement.world_direction(torch.wall_direction)
			var key := _torch_key(torch_cell, torch_direction, module.module_id)
			_expect(not expected_torches.has(key), "duplicate reconstructed torch for %s" % label)
			expected_torches[key] = true
		if module.chest_marker != null:
			var requirement := _room_requirement_for_module(definition, module.module_id)
			_expect(requirement != null and requirement.chest_loot_bundle != null, "marked chest module has no loot bundle for %s" % label)
			expected_chests[placement.placement_id] = {
				"cell": placement.world_cell(module.chest_marker.cell),
				"loot_bundle": requirement.chest_loot_bundle if requirement != null else null,
			}
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
		_expect(StructureCell.is_valid(int(layout.cells[cell])) and int(layout.cells[cell]) != StructureCell.VOID, "layout contains invalid cell at %s for %s" % [cell, label])
	_expect(layout.bounds_min == rebuilt_min and layout.bounds_max == rebuilt_max, "stored bounds differ from claimed cells for %s" % label)
	var span := layout.bounds_max - layout.bounds_min + Vector3i.ONE
	_expect(span.x <= definition.maximum_extent.x and span.y <= definition.maximum_extent.y and span.z <= definition.maximum_extent.z, "layout exceeds configured extent for %s" % label)
	var allowed_cross_module_edges: Dictionary = {}
	for socket_index in socket_records.size():
		var socket := socket_records[socket_index]
		var cell := socket["cell"] as Vector3i
		var direction := socket["direction"] as LevelSocketDefinition.Direction
		var outward := LevelSocketDefinition.vector_for(direction)
		var aperture := socket["aperture"] as Array[Vector3i]
		var unused_fill_block_id := int(socket["unused_fill_block_id"])
		var partner_count := 0
		for other_index in socket_records.size():
			if other_index == socket_index:
				continue
			var other := socket_records[other_index]
			if int(other["placement"]) == int(socket["placement"]):
				continue
			if int(other["direction"]) == int(LevelSocketDefinition.opposite(direction)) and _translated_cells_equal(aperture, outward, other["aperture"] as Array[Vector3i]):
				partner_count += 1
		if partner_count == 1:
			if unused_fill_block_id != StructureCell.AIR:
				_saw_connected_optional_socket = true
			for aperture_cell in aperture:
				var neighbor := aperture_cell + outward
				_expect(layout.get_cell(aperture_cell) == StructureCell.AIR and layout.get_cell(neighbor) == StructureCell.AIR, "connected socket aperture is not open for %s" % label)
				allowed_cross_module_edges[_edge_key(aperture_cell, neighbor)] = true
		elif partner_count == 0 and StructureCell.is_structure_solid(unused_fill_block_id):
			_saw_sealed_optional_socket = true
			for aperture_cell in aperture:
				_expect(layout.get_cell(aperture_cell) == unused_fill_block_id, "unpaired optional socket was not sealed at %s for %s" % [aperture_cell, label])
		else:
			_expect(false, "socket has %d partners with fill %d at %s for %s" % [partner_count, unused_fill_block_id, cell, label])
	_validate_module_graph(layout, label)
	for cell in layout.cells:
		if int(layout.cells[cell]) != StructureCell.AIR:
			continue
		var world_cell := cell as Vector3i
		var owner := int(ownership[world_cell])
		for direction in DIRECTIONS:
			var neighbor := world_cell + direction
			if not ownership.has(neighbor) or int(ownership[neighbor]) == owner or layout.get_cell(neighbor) != StructureCell.AIR:
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
			if reachable.has(neighbor) or layout.get_cell(neighbor) != StructureCell.AIR:
				continue
			reachable[neighbor] = true
			pending.append(neighbor)
	var air_count := 0
	for cell in layout.cells:
		if int(layout.cells[cell]) == StructureCell.AIR:
			air_count += 1
	_expect(reachable.size() == air_count, "only %d/%d AIR cells are reachable for %s" % [reachable.size(), air_count, label])
	var actual_torches: Dictionary = {}
	for torch in layout.torches:
		var key := _torch_key(torch.cell, torch.wall_direction, torch.module_id)
		_expect(not actual_torches.has(key), "duplicate placed torch for %s" % label)
		actual_torches[key] = true
		_expect(layout.get_cell(torch.cell) == StructureCell.AIR, "placed torch is not in AIR for %s" % label)
		var support := torch.cell + LevelSocketDefinition.vector_for(torch.wall_direction)
		_expect(StructureCell.is_structure_solid(layout.get_cell(support)), "placed torch has no solid support for %s" % label)
	_expect(actual_torches == expected_torches, "placed torch set differs from authored markers for %s" % label)
	_expect(layout.chests.size() == expected_chests.size(), "placed chest count differs from authored markers for %s" % label)
	var previous_room_id := -1
	var actual_chest_cells: Dictionary = {}
	for chest in layout.chests:
		_expect(chest.room_id > previous_room_id, "placed chests are not ordered by room ID for %s" % label)
		previous_room_id = chest.room_id
		_expect(expected_chests.has(chest.room_id), "placed chest has no marked room for %s" % label)
		if not expected_chests.has(chest.room_id):
			continue
		var expected := expected_chests[chest.room_id] as Dictionary
		_expect(chest.cell == expected["cell"], "placed chest marker transform changed for %s" % label)
		_expect(chest.loot_bundle == expected["loot_bundle"], "placed chest loot bundle is not canonical for %s" % label)
		_expect(not actual_chest_cells.has(chest.cell), "duplicate placed chest cell for %s" % label)
		actual_chest_cells[chest.cell] = true
		_expect(layout.get_cell(chest.cell) == StructureCell.AIR, "placed chest marker is not in AIR for %s" % label)
		_expect(StructureCell.is_structure_solid(layout.get_cell(chest.cell + Vector3i.DOWN)), "placed chest marker has no floor for %s" % label)
		_expect(_has_accessible_chest_side(layout, chest.cell), "placed chest marker has no accessible side for %s" % label)

func _validate_module_graph(layout: LevelLayout, label: String) -> void:
	var definition := _catalog.get_level(LEVEL_ID)
	var adjacency: Array[Dictionary] = []
	adjacency.resize(layout.placed_modules.size())
	var paired_socket_counts := PackedInt32Array()
	paired_socket_counts.resize(layout.placed_modules.size())
	var edges: Dictionary = {}
	var connected_sockets: Dictionary = {}
	for placement_index in layout.placed_modules.size():
		adjacency[placement_index] = {}
		_expect(layout.placed_modules[placement_index].placement_id == placement_index, "placement ID is not stable for %s" % label)
	_expect(layout.connections.size() == layout.placed_modules.size() - 1, "retained connection count changed for %s" % label)
	for connection_index in layout.connections.size():
		var connection := layout.connections[connection_index]
		_expect(connection != null, "retained null connection for %s" % label)
		if connection == null:
			continue
		_expect(connection.connection_id == connection_index, "connection ID is not stable for %s" % label)
		_expect(connection.first_placement_id >= 0 and connection.first_placement_id < layout.placed_modules.size(), "first connection placement escaped layout for %s" % label)
		_expect(connection.second_placement_id == connection_index + 1 and connection.second_placement_id < layout.placed_modules.size(), "second connection placement is not insertion-stable for %s" % label)
		if connection.first_placement_id < 0 or connection.first_placement_id >= layout.placed_modules.size() or connection.second_placement_id < 0 or connection.second_placement_id >= layout.placed_modules.size():
			continue
		var first_placement := layout.placed_modules[connection.first_placement_id]
		var second_placement := layout.placed_modules[connection.second_placement_id]
		var first_socket := _socket_with_id(first_placement.definition, connection.first_socket_id)
		var second_socket := _socket_with_id(second_placement.definition, connection.second_socket_id)
		_expect(first_socket != null and second_socket != null, "connection references an unknown socket for %s" % label)
		if first_socket == null or second_socket == null:
			continue
		var first_aperture := connection.first_aperture_cells
		var second_aperture := connection.second_aperture_cells
		_expect(connection.first_direction == first_placement.world_direction(first_socket.direction), "first connection direction changed for %s" % label)
		_expect(connection.second_direction == second_placement.world_direction(second_socket.direction), "second connection direction changed for %s" % label)
		_expect(connection.second_direction == LevelSocketDefinition.opposite(connection.first_direction), "connection directions do not oppose for %s" % label)
		_expect(first_aperture == first_placement.world_socket_aperture(first_socket), "first connection aperture changed for %s" % label)
		_expect(second_aperture == second_placement.world_socket_aperture(second_socket), "second connection aperture changed for %s" % label)
		_expect(_translated_cells_equal(first_aperture, LevelSocketDefinition.vector_for(connection.first_direction), second_aperture), "connection apertures do not meet for %s" % label)
		var first_socket_key := "%d:%s" % [connection.first_placement_id, connection.first_socket_id]
		var second_socket_key := "%d:%s" % [connection.second_placement_id, connection.second_socket_id]
		_expect(not connected_sockets.has(first_socket_key) and not connected_sockets.has(second_socket_key), "socket belongs to multiple connections for %s" % label)
		connected_sockets[first_socket_key] = true
		connected_sockets[second_socket_key] = true
		paired_socket_counts[connection.first_placement_id] += 1
		paired_socket_counts[connection.second_placement_id] += 1
		adjacency[connection.first_placement_id][connection.second_placement_id] = true
		adjacency[connection.second_placement_id][connection.first_placement_id] = true
		edges[Vector2i(connection.first_placement_id, connection.second_placement_id)] = true
		if connection_index == 0:
			first_aperture.clear()
			second_aperture.clear()
			_expect(not connection.first_aperture_cells.is_empty() and not connection.second_aperture_cells.is_empty(), "connection exposed mutable aperture ownership for %s" % label)
	for placement_index in layout.placed_modules.size():
		var placement := layout.placed_modules[placement_index]
		var paired_count := paired_socket_counts[placement_index]
		if placement_index == 0:
			_expect(placement.room_type_id.is_empty() and placement.definition.module_id == definition.start_module_id, "graph root is not the untyped entry for %s" % label)
			_expect(paired_count == placement.definition.sockets.size(), "entry has an unpaired socket for %s" % label)
			_expect(adjacency[placement_index].size() == placement.definition.sockets.size(), "entry sockets do not lead to distinct rooms for %s" % label)
		elif placement.room_type_id.is_empty():
			_expect(placement.definition.module_id in definition.hallway_module_ids, "graph connector is not a hallway for %s" % label)
			_expect(placement.definition.sockets.size() == 2 and paired_count == 2, "hallway has an unpaired end for %s" % label)
			_expect(adjacency[placement_index].size() == 2, "hallway does not connect two distinct rooms for %s" % label)
		else:
			_expect(not adjacency[placement_index].is_empty(), "room is disconnected for %s" % label)
	for edge in edges:
		var first_index := (edge as Vector2i).x
		var second_index := (edge as Vector2i).y
		var first_is_connector := (layout.placed_modules[first_index] as LevelPlacedModule).room_type_id.is_empty()
		var second_is_connector := (layout.placed_modules[second_index] as LevelPlacedModule).room_type_id.is_empty()
		_expect(first_is_connector != second_is_connector, "module graph contains a room-room or connector-connector edge for %s" % label)
	_expect(edges.size() == layout.placed_modules.size() - 1, "module graph is not a tree for %s" % label)
	var reached: Dictionary = {0: true}
	var pending: Array[int] = [0]
	var pending_index := 0
	while pending_index < pending.size():
		var placement_index := pending[pending_index]
		pending_index += 1
		for neighbor_variant in adjacency[placement_index]:
			var neighbor := int(neighbor_variant)
			if reached.has(neighbor):
				continue
			reached[neighbor] = true
			pending.append(neighbor)
	_expect(reached.size() == layout.placed_modules.size(), "module graph is disconnected for %s" % label)

func _socket_with_id(module: LevelModuleDefinition, socket_id: StringName) -> LevelSocketDefinition:
	for socket in module.sockets:
		if socket.socket_id == socket_id:
			return socket
	return null

func _test_level_state_and_mesher() -> void:
	var stone := Vector3i.ZERO
	var cells: Dictionary = {stone: BlockId.Type.STONE}
	for direction in DIRECTIONS:
		if direction == Vector3i.RIGHT:
			continue
		var air := stone + direction
		cells[air] = StructureCell.AIR
	cells[stone + Vector3i.UP * 2] = StructureCell.AIR
	var state := LevelState.new(
		_block_catalog,
		cells,
		stone + Vector3i.UP,
		LevelSocketDefinition.Direction.NORTH,
		stone + Vector3i.UP,
		LevelSocketDefinition.Direction.WEST,
		Vector3i(-1, -1, -1),
		Vector3i(1, 1, 1)
	)
	_expect(state.get_cell_value(stone) == BlockId.Type.STONE, "LevelState lost a solid block")
	_expect(state.get_cell_value(stone + Vector3i.UP) == StructureCell.AIR, "LevelState lost claimed AIR")
	_expect(state.get_cell_value(stone + Vector3i.RIGHT) == StructureCell.VOID, "LevelState does not distinguish VOID")
	_expect(state.get_block_at(stone + Vector3i.UP) == null, "claimed AIR unexpectedly returns a block")
	_expect(state.get_block_at(stone + Vector3i.RIGHT) == null, "VOID unexpectedly returns a block")
	_expect(state.get_block_id_at(stone + Vector3i.UP) == BlockId.Type.AIR, "claimed AIR block ID query changed")
	_expect(state.get_block_id_at(stone + Vector3i.RIGHT) == BlockId.Type.AIR, "voxel query fallback for VOID changed")
	_expect(state.has_cell(stone) and state.has_cell(stone + Vector3i.UP), "claimed state changed")
	_expect(not state.has_cell(stone + Vector3i.RIGHT), "VOID is marked claimed")
	_expect(state.is_solid(stone) and state.is_raycast_solid(stone), "solid collision/raycast query failed")
	_expect(not state.is_solid(stone + Vector3i.UP), "AIR is solid")
	_expect(state.is_interior_open(stone + Vector3i.UP), "claimed AIR is not interior-open")
	_expect(not state.is_interior_open(stone + Vector3i.RIGHT), "VOID is interior-open")
	_expect(state.is_face_targetable(stone, Vector3i.UP), "interior-facing solid face is not targetable")
	_expect(not state.is_face_targetable(stone, Vector3i.RIGHT), "VOID-facing solid face is targetable")
	_expect(state.get_highest_top(0, 0) == 1.0, "highest solid top changed")
	_expect(state.get_highest_top(20, 20) == VoxelSpace.NO_SURFACE_Y, "empty column reports a surface")
	_expect(state.get_spawn_position().is_equal_approx(Vector3(0.5, 1.0, 0.5)), "level spawn conversion changed")
	_expect(state.get_return_door_position().is_equal_approx(Vector3(0.5, 1.0, 0.5)), "return-door conversion changed")
	var cell_snapshot := state.snapshot_cells()
	cell_snapshot.clear()
	_expect(state.get_cell_value(stone) == BlockId.Type.STONE and state.has_cell(stone), "LevelState exposed mutable cell storage")
	var texture_set := BlockTextureSet.new(_block_catalog)
	var mesher := LevelMesher.new(texture_set)
	var data := mesher.build_mesh_data(state) as Dictionary
	_expect(data != null, "mesher returned no data for interior-facing geometry")
	if data == null:
		return
	var vertices := data["vertices"] as PackedVector3Array
	var normals := data["normals"] as PackedVector3Array
	var uvs := data["uvs"] as PackedVector2Array
	var texture_layers := data["texture_layers"] as PackedVector2Array
	var indices := data["indices"] as PackedInt32Array
	_expect(vertices.size() == 20, "interior-only mesher emitted %d vertices instead of 20" % vertices.size())
	_expect(normals.size() == vertices.size() and uvs.size() == vertices.size() and texture_layers.size() == vertices.size(), "mesh attribute lengths differ")
	_expect(indices.size() == 30, "interior-only mesher emitted %d indices instead of 30" % indices.size())
	var direction_counts: Dictionary = {}
	for normal in normals:
		var normal_key := Vector3i(roundi(normal.x), roundi(normal.y), roundi(normal.z))
		direction_counts[normal_key] = int(direction_counts.get(normal_key, 0)) + 1
	_expect(not direction_counts.has(Vector3i.RIGHT), "mesher emitted a VOID-facing exterior face")
	for direction in DIRECTIONS:
		if direction == Vector3i.RIGHT:
			continue
		_expect(int(direction_counts.get(direction, 0)) == 4, "mesher omitted or duplicated interior face %s" % direction)
	for triangle_index in range(0, indices.size(), 3):
		var first := vertices[indices[triangle_index]]
		var second := vertices[indices[triangle_index + 1]]
		var third := vertices[indices[triangle_index + 2]]
		var supplied_normal := normals[indices[triangle_index]]
		var winding_normal := (second - first).cross(third - first).normalized()
		_expect(winding_normal.dot(supplied_normal) < -0.999, "mesh triangle winding disagrees with its supplied normal")
	for vertex_index in texture_layers.size():
		var normal := normals[vertex_index]
		var expected_layer := texture_set.side_layers[BlockId.Type.STONE]
		if normal == Vector3.UP:
			expected_layer = texture_set.top_layers[BlockId.Type.STONE]
		elif normal == Vector3.DOWN:
			expected_layer = texture_set.bottom_layers[BlockId.Type.STONE]
		_expect(is_equal_approx(texture_layers[vertex_index].x, float(expected_layer)), "UV2 texture layer does not match the face definition")
		_expect(is_zero_approx(texture_layers[vertex_index].y), "UV2 secondary layer component changed")
	var mesh := mesher.create_mesh_from_data(data)
	_expect(mesh != null and mesh.get_surface_count() == 1, "mesh data did not create one surface")
	if mesh != null:
		var arrays := mesh.surface_get_arrays(0)
		_expect((arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array) == texture_layers, "UV2 layers were not installed on the mesh surface")

func _test_level_chest_overlay() -> void:
	var spawn_floor := Vector3i.ZERO
	var chest_floor := Vector3i.RIGHT
	var chest_cell := chest_floor + Vector3i.UP
	var cells: Dictionary = {
		spawn_floor: BlockId.Type.STONE,
		spawn_floor + Vector3i.UP: StructureCell.AIR,
		spawn_floor + Vector3i.UP * 2: StructureCell.AIR,
		chest_floor: BlockId.Type.STONE,
		chest_cell: StructureCell.AIR,
		chest_cell + Vector3i.UP: StructureCell.AIR,
	}
	var state := LevelState.new(
		_block_catalog,
		cells,
		spawn_floor + Vector3i.UP,
		LevelSocketDefinition.Direction.NORTH,
		spawn_floor + Vector3i.UP,
		LevelSocketDefinition.Direction.WEST,
		Vector3i.ZERO,
		Vector3i(1, 2, 0),
	)
	var terrain_cells := state.snapshot_cells()
	var terrain_solids := state.get_solid_cells()
	var terrain_mesh: Variant = LevelMesher.new(BlockTextureSet.new(_block_catalog)).build_mesh_data(state)
	state._configure_chest_cells([chest_cell])
	_expect(state.get_chest_cells() == [chest_cell], "LevelState omitted the configured chest overlay")
	var copied_chests := state.get_chest_cells()
	copied_chests.clear()
	_expect(state.get_chest_cells() == [chest_cell], "LevelState exposed mutable chest ownership")
	_expect(state.get_cell_value(chest_cell) == BlockId.Type.CHEST and state.get_block_id_at(chest_cell) == BlockId.Type.CHEST, "chest overlay did not project the canonical chest block")
	_expect(state.get_block_at(chest_cell) == BlockId.Type.CHEST and state.block_catalog.get_definition(state.get_block_id_at(chest_cell)).container != null, "chest overlay did not expose container metadata")
	_expect(state.is_solid(chest_cell) and state.is_raycast_solid(chest_cell), "chest overlay did not block bodies and raycasts")
	_expect(not state.is_interior_open(chest_cell) and state.is_base_interior_open(chest_cell), "chest overlay changed base interior ownership")
	_expect(state.is_face_targetable(chest_cell, Vector3i.UP), "chest overlay did not expose a targetable face")
	_expect(state.get_highest_top(chest_cell.x, chest_cell.z) == 2.0, "chest overlay did not contribute to the collision surface height")
	_expect(state.snapshot_cells() == terrain_cells and state.get_solid_cells() == terrain_solids, "chest overlay changed terrain snapshots or mesh cells")
	_expect(LevelMesher.new(BlockTextureSet.new(_block_catalog)).build_mesh_data(state) == terrain_mesh, "chest overlay entered terrain mesh data")
	var doorway := LevelDoorway.new(0, 1, LevelSocketDefinition.Direction.NORTH, [chest_cell], BlockId.Type.STONE_BRICKS)
	_expect(not state.configure_seals([doorway], [0]), "doorway seal overlapped a generated chest")

func _test_gameplay_location_state() -> void:
	var initial := Vector3(2.5, 9.0, -3.5)
	var location := GameplayLocationState.new(initial)
	_expect(not location.is_in_level(), "location starts inside a level")
	_expect(location.get_persisted_position().is_equal_approx(initial), "initial overworld position changed")
	var walking_position := Vector3(8.0, 10.0, 4.0)
	location.update_world_position(walking_position)
	_expect(location.get_persisted_position().is_equal_approx(walking_position), "world movement did not update persisted position")
	var doorway_position := Vector3(11.5, 12.0, -7.5)
	location.enter_level(doorway_position)
	_expect(location.is_in_level(), "enter_level did not change active location")
	_expect(location.get_persisted_position().is_equal_approx(doorway_position), "doorway return anchor was not persisted")
	location.update_world_position(Vector3(400.0, 2.0, 400.0))
	_expect(location.get_persisted_position().is_equal_approx(doorway_position), "level-local movement overwrote the persisted overworld anchor")
	location.return_to_world()
	_expect(not location.is_in_level(), "return_to_world did not restore world location")
	location.update_world_position(initial)
	_expect(location.get_persisted_position().is_equal_approx(initial), "world updates did not resume after leaving the level")
	var probe_output: Array = []
	var probe_exit := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tests/level_save_probe.gd"],
		probe_output,
		true
	)
	var probe_text := "\n".join(PackedStringArray(probe_output))
	_expect(probe_exit == 0, "isolated current-version save probe exited %d" % probe_exit)
	_expect(probe_text.contains("LEVEL_SAVE_PROBE PASS"), "isolated current-version save probe did not persist the overworld anchor")

func _layout_digest(layout: LevelLayout) -> String:
	var lines := PackedStringArray()
	lines.append("seed=%d target=%d explored=%d" % [layout.seed_value, layout.target_module_count, layout.explored_state_count])
	lines.append("spawn=%s:%d return=%s:%d bounds=%s:%s" % [layout.spawn_cell, int(layout.spawn_facing), layout.return_door_cell, int(layout.return_door_facing), layout.bounds_min, layout.bounds_max])
	for placement in layout.placed_modules:
		lines.append("module=%s:%s:%s:%d" % [placement.definition.module_id, placement.room_type_id, placement.origin, placement.rotation])
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
	for chest in layout.chests:
		lines.append("chest=%d:%d,%d,%d:%s" % [chest.room_id, chest.cell.x, chest.cell.y, chest.cell.z, chest.loot_bundle.id])
	return "\n".join(lines).sha256_text()

func _topology_digest(layout: LevelLayout) -> String:
	var lines := PackedStringArray()
	for placement in layout.placed_modules:
		lines.append("placement=%d:%s" % [placement.placement_id, placement.definition.module_id])
	for connection in layout.connections:
		lines.append("connection=%d:%d:%s:%d>%d:%s:%d" % [connection.connection_id, connection.first_placement_id, connection.first_socket_id, int(connection.first_direction), connection.second_placement_id, connection.second_socket_id, int(connection.second_direction)])
	return "\n".join(lines).sha256_text()

func _torch_key(cell: Vector3i, direction: LevelSocketDefinition.Direction, module_id: StringName) -> String:
	return "%d,%d,%d:%d:%s" % [cell.x, cell.y, cell.z, int(direction), module_id]

func _has_accessible_chest_side(layout: LevelLayout, chest_cell: Vector3i) -> bool:
	for offset in LevelChestMarkerDefinition.HORIZONTAL_NEIGHBORS:
		var feet_cell := chest_cell + offset
		if (
			layout.get_cell(feet_cell) == StructureCell.AIR
			and layout.get_cell(feet_cell + Vector3i.UP) == StructureCell.AIR
			and StructureCell.is_structure_solid(layout.get_cell(feet_cell + Vector3i.DOWN))
		):
			return true
	return false

func _edge_key(first: Vector3i, second: Vector3i) -> String:
	if _cell_less(second, first):
		var swap := first
		first = second
		second = swap
	return "%d,%d,%d>%d,%d,%d" % [first.x, first.y, first.z, second.x, second.y, second.z]

func _translated_cells_equal(first: Array[Vector3i], offset: Vector3i, second: Array[Vector3i]) -> bool:
	if first.size() != second.size():
		return false
	var second_cells: Dictionary = {}
	for cell in second:
		second_cells[cell] = true
	for cell in first:
		if not second_cells.has(cell + offset):
			return false
	return true

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
