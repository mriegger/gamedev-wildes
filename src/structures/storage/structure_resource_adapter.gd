extends RefCounted
class_name StructureResourceAdapter

static func create_draft(resource: Resource, source_path: String) -> StructureDraft:
	if resource is StructureDefinition:
		return StructureDraft.restore_structure(resource as StructureDefinition, source_path)
	if resource is LevelModuleDefinition:
		return StructureDraft.restore_level_module(resource as LevelModuleDefinition, source_path)
	return null

static func create_snapshot(draft: StructureDraft, identifier: StringName) -> Resource:
	if draft == null or draft.is_empty() or not StructureDefinition.is_valid_id(identifier):
		return null
	if draft.is_bound() and draft.get_identifier() != identifier:
		return null
	if draft.get_format() == StructureDraft.Format.GENERIC_STRUCTURE:
		return _create_structure_snapshot(draft, identifier)
	return _create_module_snapshot(draft, identifier)

static func resources_equal(first: Resource, second: Resource) -> bool:
	if first is StructureDefinition and second is StructureDefinition:
		return _structures_equal(first as StructureDefinition, second as StructureDefinition)
	if first is LevelModuleDefinition and second is LevelModuleDefinition:
		return _modules_equal(first as LevelModuleDefinition, second as LevelModuleDefinition)
	return false

static func _create_structure_snapshot(draft: StructureDraft, identifier: StringName) -> StructureDefinition:
	var definition := StructureDefinition.new()
	definition.format_version = StructureDefinition.CURRENT_FORMAT_VERSION
	definition.structure_id = identifier
	definition.size = draft.get_size()
	definition.cells = draft.snapshot_cells()
	definition.torches.assign(draft.get_torches())
	if not definition.validate():
		return null
	return definition

static func _create_module_snapshot(draft: StructureDraft, identifier: StringName) -> LevelModuleDefinition:
	var definition := LevelModuleDefinition.new()
	definition.format_version = LevelModuleDefinition.CURRENT_FORMAT_VERSION
	definition.module_id = identifier
	definition.size = draft.get_size()
	definition.weight = draft.get_weight()
	definition.cells = draft.snapshot_cells()
	definition.sockets.assign(draft.get_sockets())
	definition.enemy_spawn_zones.assign(draft.get_enemy_spawn_zones())
	for source in draft.get_torches():
		var direction: Variant = LevelSocketDefinition.direction_for_vector(source.support_direction)
		if direction == null:
			return null
		var torch := LevelTorchDefinition.new()
		torch.cell = source.cell
		torch.wall_direction = direction as LevelSocketDefinition.Direction
		definition.torches.append(torch)
	definition.spawn_marker = draft.get_spawn_marker()
	definition.return_door_marker = draft.get_return_door_marker()
	definition.chest_marker = draft.get_chest_marker()
	if not definition.validate():
		return null
	return definition

static func _structures_equal(first: StructureDefinition, second: StructureDefinition) -> bool:
	if not first.validate() or not second.validate():
		return false
	if first.format_version != second.format_version or first.structure_id != second.structure_id or first.size != second.size or first.cells != second.cells:
		return false
	if first.torches.size() != second.torches.size():
		return false
	for index in first.torches.size():
		var left := first.torches[index]
		var right := second.torches[index]
		if left == null or right == null or left.cell != right.cell or left.support_direction != right.support_direction:
			return false
	return true

static func _modules_equal(first: LevelModuleDefinition, second: LevelModuleDefinition) -> bool:
	if not first.validate() or not second.validate():
		return false
	if first.format_version != second.format_version or first.module_id != second.module_id or first.size != second.size or first.cells != second.cells or first.weight != second.weight:
		return false
	if first.sockets.size() != second.sockets.size() or first.torches.size() != second.torches.size() or first.enemy_spawn_zones.size() != second.enemy_spawn_zones.size():
		return false
	for index in first.sockets.size():
		var left_socket := first.sockets[index]
		var right_socket := second.sockets[index]
		if left_socket == null or right_socket == null or left_socket.socket_id != right_socket.socket_id or left_socket.cell != right_socket.cell or left_socket.direction != right_socket.direction or left_socket.unused_fill_block_id != right_socket.unused_fill_block_id:
			return false
	for index in first.torches.size():
		var left_torch := first.torches[index]
		var right_torch := second.torches[index]
		if left_torch == null or right_torch == null or left_torch.cell != right_torch.cell or left_torch.wall_direction != right_torch.wall_direction:
			return false
	for index in first.enemy_spawn_zones.size():
		var left_zone := first.enemy_spawn_zones[index]
		var right_zone := second.enemy_spawn_zones[index]
		if left_zone == null or right_zone == null or left_zone.zone_id != right_zone.zone_id or left_zone.minimum_feet_cell != right_zone.minimum_feet_cell or left_zone.maximum_feet_cell != right_zone.maximum_feet_cell:
			return false
	return _markers_equal(first.spawn_marker, second.spawn_marker) \
		and _markers_equal(first.return_door_marker, second.return_door_marker) \
		and _chest_markers_equal(first.chest_marker, second.chest_marker)

static func _markers_equal(first: LevelMarkerDefinition, second: LevelMarkerDefinition) -> bool:
	if first == null or second == null:
		return first == second
	return first.cell == second.cell and first.facing == second.facing

static func _chest_markers_equal(first: LevelChestMarkerDefinition, second: LevelChestMarkerDefinition) -> bool:
	if first == null or second == null:
		return first == second
	return first.cell == second.cell
