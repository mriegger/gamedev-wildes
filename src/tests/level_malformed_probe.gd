extends SceneTree

func _init() -> void:
	var empty_result := LevelGenerator.new().generate(LevelCatalog.new(), &"stone_dungeon", 1, &"probe", Vector3i.ZERO)
	var source_catalog := load("res://levels/content/dungeons/stone/level_catalog.tres") as LevelCatalog
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	if source_catalog == null or entity_catalog == null:
		print("LEVEL_MALFORMED_PROBE FAILED")
		quit(1)
		return
	var source_level := source_catalog.get_level(&"stone_dungeon")
	var unsupported_version := source_level.duplicate(true) as LevelDefinition
	unsupported_version.format_version = LevelDefinition.FORMAT_VERSION + 1
	var unversioned := source_level.duplicate(true) as LevelDefinition
	unversioned.format_version = 0
	var obsolete_version := source_level.duplicate(true) as LevelDefinition
	obsolete_version.format_version = LevelDefinition.FORMAT_VERSION - 1
	var missing_presentation := source_catalog.get_level(&"stone_dungeon").duplicate(true) as LevelDefinition
	missing_presentation.presentation = null
	var missing_encounter := source_level.duplicate(true) as LevelDefinition
	missing_encounter.room_requirements[0].encounter = null
	var missing_encounter_catalog := _catalog_with(source_catalog, missing_encounter)
	var chest_encounter := source_level.duplicate(true) as LevelDefinition
	chest_encounter.room_requirements[2].encounter = chest_encounter.room_requirements[1].encounter
	var chest_encounter_catalog := _catalog_with(source_catalog, chest_encounter)
	var empty_encounter := LevelRoomEncounterDefinition.new()
	var null_group_encounter := LevelRoomEncounterDefinition.new()
	null_group_encounter.enemy_groups.append(null)
	var empty_entity_group := LevelEnemyGroupDefinition.new()
	var empty_entity_encounter := LevelRoomEncounterDefinition.new()
	empty_entity_encounter.enemy_groups.append(empty_entity_group)
	var zero_count_group := LevelEnemyGroupDefinition.new()
	zero_count_group.entity_id = &"zero"
	zero_count_group.count = 0
	var zero_count_encounter := LevelRoomEncounterDefinition.new()
	zero_count_encounter.enemy_groups.append(zero_count_group)
	var excessive_count_group := LevelEnemyGroupDefinition.new()
	excessive_count_group.entity_id = &"excessive"
	excessive_count_group.count = LevelEnemyGroupDefinition.MAX_COUNT + 1
	var excessive_count_encounter := LevelRoomEncounterDefinition.new()
	excessive_count_encounter.enemy_groups.append(excessive_count_group)
	var duplicate_enemy_encounter := source_level.room_requirements[0].encounter.duplicate(true) as LevelRoomEncounterDefinition
	duplicate_enemy_encounter.enemy_groups.append(duplicate_enemy_encounter.enemy_groups[0].duplicate(true) as LevelEnemyGroupDefinition)
	var oversized_encounter := LevelRoomEncounterDefinition.new()
	var first_oversized_group := LevelEnemyGroupDefinition.new()
	first_oversized_group.entity_id = &"first"
	first_oversized_group.count = 64
	var second_oversized_group := LevelEnemyGroupDefinition.new()
	second_oversized_group.entity_id = &"second"
	second_oversized_group.count = 1
	oversized_encounter.enemy_groups.assign([first_oversized_group, second_oversized_group])
	var unknown_enemy_level := source_level.duplicate(true) as LevelDefinition
	unknown_enemy_level.room_requirements[0].encounter.enemy_groups[0].entity_id = &"missing_enemy"
	var unknown_enemy_catalog := _catalog_with(source_catalog, unknown_enemy_level)
	var oversized_entity_catalog := EntityCatalog.new()
	var oversized_entity_definitions: Array[EntityDefinition] = []
	for definition in entity_catalog.definitions:
		var copied := definition.duplicate(true) as EntityDefinition
		if copied.id == &"zombie":
			copied.body_width = 100.0
		oversized_entity_definitions.append(copied)
	oversized_entity_catalog.definitions = oversized_entity_definitions
	var empty_room_type := LevelRoomRequirement.new()
	empty_room_type.count = 1
	empty_room_type.module_ids.assign([&"stone_room"])
	var zero_room_count := LevelRoomRequirement.new()
	zero_room_count.room_type_id = &"zero_room"
	zero_room_count.count = 0
	zero_room_count.module_ids.assign([&"stone_room"])
	var empty_room_pool := LevelRoomRequirement.new()
	empty_room_pool.room_type_id = &"empty_pool"
	empty_room_pool.count = 1
	var duplicate_room_modules := LevelRoomRequirement.new()
	duplicate_room_modules.room_type_id = &"duplicate_pool"
	duplicate_room_modules.count = 1
	duplicate_room_modules.module_ids.assign([&"stone_room", &"stone_room"])
	var duplicate_room_types := source_level.duplicate(true) as LevelDefinition
	var duplicated_requirement := duplicate_room_types.room_requirements[0].duplicate(true) as LevelRoomRequirement
	duplicated_requirement.module_ids.assign([&"stone_room"])
	duplicate_room_types.room_requirements.append(duplicated_requirement)
	var null_requirement := source_level.duplicate(true) as LevelDefinition
	null_requirement.room_requirements.append(null)
	var conflicting_roles := source_level.duplicate(true) as LevelDefinition
	conflicting_roles.hallway_module_ids.append(&"stone_room")
	var unknown_hallway := source_level.duplicate(true) as LevelDefinition
	unknown_hallway.hallway_module_ids.assign([&"missing_hallway"])
	var unknown_hallway_catalog := _catalog_with(source_catalog, unknown_hallway)
	var unknown_room := source_level.duplicate(true) as LevelDefinition
	unknown_room.room_requirements[0].module_ids.assign([&"missing_room"])
	var unknown_room_catalog := _catalog_with(source_catalog, unknown_room)
	var sealable_start := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	sealable_start.sockets[0].unused_fill_block_id = BlockId.Type.STONE_BRICKS
	var sealable_start_catalog := _catalog_with(source_catalog, source_level, {sealable_start.module_id: sealable_start})
	var one_socket_hallway := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	one_socket_hallway.sockets.resize(1)
	var one_socket_hallway_catalog := _catalog_with(source_catalog, source_level, {one_socket_hallway.module_id: one_socket_hallway})
	var sealable_hallway := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	sealable_hallway.sockets[0].unused_fill_block_id = BlockId.Type.STONE_BRICKS
	var sealable_hallway_catalog := _catalog_with(source_catalog, source_level, {sealable_hallway.module_id: sealable_hallway})
	var required_room := source_catalog.get_module(&"stone_room").duplicate(true) as LevelModuleDefinition
	required_room.sockets[0].unused_fill_block_id = StructureCell.AIR
	var required_room_catalog := _catalog_with(source_catalog, source_level, {required_room.module_id: required_room})
	var missing_spawn_zones := source_catalog.get_module(&"stone_room").duplicate(true) as LevelModuleDefinition
	missing_spawn_zones.enemy_spawn_zones.clear()
	var missing_spawn_zones_catalog := _catalog_with(source_catalog, source_level, {missing_spawn_zones.module_id: missing_spawn_zones})
	var disconnected_room := source_catalog.get_module(&"stone_chest_room").duplicate(true) as LevelModuleDefinition
	disconnected_room.cells[StructureCell.index_of(Vector3i.ZERO, disconnected_room.size)] = StructureCell.AIR
	var disconnected_room_catalog := _catalog_with(source_catalog, source_level, {disconnected_room.module_id: disconnected_room})
	var too_few_rooms := source_level.duplicate(true) as LevelDefinition
	too_few_rooms.room_requirements.resize(1)
	too_few_rooms.room_requirements[0].count = 1
	var too_few_rooms_catalog := _catalog_with(source_catalog, too_few_rooms)
	var oversized_composition := source_level.duplicate(true) as LevelDefinition
	oversized_composition.room_requirements.resize(1)
	oversized_composition.room_requirements[0].count = 33
	var oversized_composition_catalog := _catalog_with(source_catalog, oversized_composition)
	var missing_hallways := source_level.duplicate(true) as LevelDefinition
	missing_hallways.hallway_module_ids.clear()
	var missing_hallways_catalog := _catalog_with(source_catalog, missing_hallways)
	var oversized_module := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	oversized_module.size = Vector3i(LevelDefinition.HARD_MAX_EXTENT.x + 1, oversized_module.size.y, oversized_module.size.z)
	var one_cell_socket := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var one_cell_upper := one_cell_socket.sockets[0].cell + Vector3i.UP
	one_cell_socket.cells[StructureCell.index_of(one_cell_upper, one_cell_socket.size)] = BlockId.Type.STONE
	var overlapping_sockets := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var overlapping_socket := overlapping_sockets.sockets[0].duplicate(true) as LevelSocketDefinition
	overlapping_socket.socket_id = &"north_overlap"
	overlapping_sockets.sockets.append(overlapping_socket)
	var exposed_socket := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var exposed_aperture := exposed_socket.socket_aperture_cells(exposed_socket.sockets[0])
	var exposed_perimeter := exposed_aperture[0]
	for aperture_cell in exposed_aperture:
		if aperture_cell.y > exposed_perimeter.y:
			exposed_perimeter = aperture_cell
	exposed_perimeter += Vector3i.UP
	exposed_socket.cells[StructureCell.index_of(exposed_perimeter, exposed_socket.size)] = StructureCell.VOID
	var invalid_socket_fill := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	invalid_socket_fill.sockets[0].unused_fill_block_id = BlockId.Type.TORCH
	var torch_socket_overlap := source_catalog.get_module(&"stone_hallway").duplicate(true) as LevelModuleDefinition
	var overlapping_torch := LevelTorchDefinition.new()
	overlapping_torch.cell = torch_socket_overlap.sockets[0].cell + Vector3i.FORWARD
	overlapping_torch.wall_direction = LevelSocketDefinition.Direction.NORTH
	torch_socket_overlap.torches.append(overlapping_torch)
	var spawn_socket_overlap := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	spawn_socket_overlap.spawn_marker.cell = spawn_socket_overlap.sockets[0].cell
	var return_socket_overlap := source_catalog.get_module(&"stone_entry_path").duplicate(true) as LevelModuleDefinition
	return_socket_overlap.return_door_marker.cell = return_socket_overlap.sockets[0].cell
	var unknown_entrance := LevelEntranceDefinition.new()
	unknown_entrance.entrance_id = &"unknown"
	unknown_entrance.level_id = &"missing"
	var empty_failed := not empty_result.succeeded and empty_result.failure_code == LevelGenerationResult.FailureCode.INVALID_CATALOG and empty_result.layout == null and not empty_result.failure_reason.is_empty()
	var checks: Array[bool] = [
		empty_failed,
		not unsupported_version.validate(),
		not unversioned.validate(),
		not obsolete_version.validate(),
		not missing_presentation.validate(),
		missing_encounter.validate(),
		not missing_encounter_catalog.validate(),
		not chest_encounter_catalog.validate(),
		not empty_encounter.validate("probe"),
		not null_group_encounter.validate("probe"),
		not empty_entity_encounter.validate("probe"),
		not zero_count_encounter.validate("probe"),
		not excessive_count_encounter.validate("probe"),
		not duplicate_enemy_encounter.validate("probe"),
		not oversized_encounter.validate("probe"),
		LevelEncounterCatalogValidator.validate(source_catalog, entity_catalog),
		not LevelEncounterCatalogValidator.validate(unknown_enemy_catalog, entity_catalog),
		not LevelEncounterCatalogValidator.validate(source_catalog, oversized_entity_catalog),
		not empty_room_type.validate("probe"),
		not zero_room_count.validate("probe"),
		not empty_room_pool.validate("probe"),
		not duplicate_room_modules.validate("probe"),
		not duplicate_room_types.validate(),
		not null_requirement.validate(),
		not conflicting_roles.validate(),
		not unknown_hallway_catalog.validate(),
		not unknown_room_catalog.validate(),
		not sealable_start_catalog.validate(),
		not one_socket_hallway_catalog.validate(),
		not sealable_hallway_catalog.validate(),
		not required_room_catalog.validate(),
		not missing_spawn_zones_catalog.validate(),
		not disconnected_room_catalog.validate(),
		not too_few_rooms_catalog.validate(),
		not oversized_composition_catalog.validate(),
		not missing_hallways_catalog.validate(),
		not oversized_module.validate(),
		not one_cell_socket.validate(),
		not overlapping_sockets.validate(),
		not exposed_socket.validate(),
		not invalid_socket_fill.validate(),
		not torch_socket_overlap.validate(),
		not spawn_socket_overlap.validate(),
		not return_socket_overlap.validate(),
		not unknown_entrance.validate(source_catalog),
	]
	var passed := true
	for check in checks:
		passed = check and passed
	if passed:
		print("LEVEL_MALFORMED_PROBE PASS")
		quit(0)
	else:
		print("LEVEL_MALFORMED_PROBE FAILED")
		quit(1)

func _catalog_with(source: LevelCatalog, level: LevelDefinition, replacements: Dictionary = {}) -> LevelCatalog:
	var catalog := LevelCatalog.new()
	for module in source.modules:
		catalog.modules.append(replacements.get(module.module_id, module) as LevelModuleDefinition)
	catalog.levels.append(level)
	return catalog
