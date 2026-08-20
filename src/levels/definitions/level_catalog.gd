extends Resource
class_name LevelCatalog

@export var modules: Array[LevelModuleDefinition] = []:
	set(value):
		modules = value
		_lookup_ready = false

@export var levels: Array[LevelDefinition] = []:
	set(value):
		levels = value
		_lookup_ready = false

var _modules_by_id: Dictionary = {}
var _levels_by_id: Dictionary = {}
var _valid_module_ids: Dictionary = {}
var _lookup_ready: bool = false
var _is_valid: bool = false

func validate() -> bool:
	_ensure_lookup()
	return _is_valid

func has_module(module_id: StringName) -> bool:
	_ensure_lookup()
	return _modules_by_id.has(module_id)

func get_module(module_id: StringName) -> LevelModuleDefinition:
	_ensure_lookup()
	assert(_modules_by_id.has(module_id))
	return _modules_by_id[module_id] as LevelModuleDefinition

func has_level(level_id: StringName) -> bool:
	_ensure_lookup()
	return _levels_by_id.has(level_id)

func get_level(level_id: StringName) -> LevelDefinition:
	_ensure_lookup()
	assert(_levels_by_id.has(level_id))
	return _levels_by_id[level_id] as LevelDefinition

func _ensure_lookup() -> void:
	if not _lookup_ready:
		_rebuild_lookup()

func _rebuild_lookup() -> void:
	_lookup_ready = true
	_is_valid = true
	_modules_by_id.clear()
	_levels_by_id.clear()
	_valid_module_ids.clear()
	if modules.is_empty() or levels.is_empty():
		push_error("[LevelCatalog] Modules and levels are required")
		_is_valid = false
	for module in modules:
		if module == null:
			push_error("[LevelCatalog] Null module definition")
			_is_valid = false
			continue
		var module_is_valid := module.validate()
		_is_valid = module_is_valid and _is_valid
		if module.module_id.is_empty() or _modules_by_id.has(module.module_id):
			push_error("[LevelCatalog] Empty or duplicate module ID: %s" % module.module_id)
			_is_valid = false
			continue
		_modules_by_id[module.module_id] = module
		if module_is_valid:
			_valid_module_ids[module.module_id] = true
	for level in levels:
		if level == null:
			push_error("[LevelCatalog] Null level definition")
			_is_valid = false
			continue
		_is_valid = level.validate() and _is_valid
		if level.level_id.is_empty() or _levels_by_id.has(level.level_id):
			push_error("[LevelCatalog] Empty or duplicate level ID: %s" % level.level_id)
			_is_valid = false
			continue
		_levels_by_id[level.level_id] = level
		_is_valid = _validate_level_modules(level) and _is_valid

func _validate_level_modules(level: LevelDefinition) -> bool:
	var valid := true
	if not _modules_by_id.has(level.start_module_id):
		push_error("[LevelCatalog] Unknown start module %s for %s" % [level.start_module_id, level.level_id])
		return false
	if not _valid_module_ids.has(level.start_module_id):
		push_error("[LevelCatalog] Invalid start module %s for %s" % [level.start_module_id, level.level_id])
		return false
	var start := _modules_by_id[level.start_module_id] as LevelModuleDefinition
	if start.spawn_marker == null or start.return_door_marker == null or start.chest_marker != null or start.sockets.is_empty() or not _has_only_required_sockets(start):
		push_error("[LevelCatalog] Start module must have markers and required sockets for %s" % level.level_id)
		valid = false
	elif not start.has_connected_traversable_air(false):
		push_error("[LevelCatalog] Start module air must be connected for %s" % level.level_id)
		valid = false
	var claimed_roles: Dictionary = {level.start_module_id: "start"}
	for module_id in level.hallway_module_ids:
		valid = _claim_role(module_id, "hallway", claimed_roles, level.level_id) and valid
		if not _modules_by_id.has(module_id):
			push_error("[LevelCatalog] Unknown hallway module %s for %s" % [module_id, level.level_id])
			valid = false
			continue
		if not _valid_module_ids.has(module_id):
			push_error("[LevelCatalog] Invalid hallway module %s for %s" % [module_id, level.level_id])
			valid = false
			continue
		var hallway := _modules_by_id[module_id] as LevelModuleDefinition
		if hallway.sockets.size() != 2 or hallway.spawn_marker != null or hallway.return_door_marker != null or hallway.chest_marker != null or not _has_only_required_sockets(hallway):
			push_error("[LevelCatalog] Hallway module must have exactly two required sockets and no markers: %s for %s" % [module_id, level.level_id])
			valid = false
		elif not hallway.has_connected_traversable_air(false):
			push_error("[LevelCatalog] Hallway module air must be connected: %s for %s" % [module_id, level.level_id])
			valid = false
	var room_branch_capacity := 0
	for requirement in level.room_requirements:
		if requirement == null:
			continue
		var has_encounter := requirement.encounter != null
		var has_chest_loot := requirement.chest_loot_bundle != null
		var maximum_extra_sockets := -1
		for module_id in requirement.module_ids:
			valid = _claim_role(module_id, "room", claimed_roles, level.level_id) and valid
			if not _modules_by_id.has(module_id):
				push_error("[LevelCatalog] Unknown room module %s for %s" % [module_id, level.level_id])
				valid = false
				continue
			if not _valid_module_ids.has(module_id):
				push_error("[LevelCatalog] Invalid room module %s for %s" % [module_id, level.level_id])
				valid = false
				continue
			var room := _modules_by_id[module_id] as LevelModuleDefinition
			if (room.chest_marker != null) != has_chest_loot:
				push_error("[LevelCatalog] Room module chest marker and loot bundle must be configured together: %s for %s" % [module_id, level.level_id])
				valid = false
			if has_encounter and room.enemy_spawn_zones.is_empty():
				push_error("[LevelCatalog] Room module requires enemy spawn zones: %s for %s" % [module_id, level.level_id])
				valid = false
			elif not has_encounter and not room.enemy_spawn_zones.is_empty():
				push_error("[LevelCatalog] Passive room module cannot have enemy spawn zones: %s for %s" % [module_id, level.level_id])
				valid = false
			if room.sockets.is_empty() or room.spawn_marker != null or room.return_door_marker != null or not _has_only_sealable_sockets(room):
				push_error("[LevelCatalog] Room module must have sealable sockets and no markers: %s for %s" % [module_id, level.level_id])
				valid = false
			elif not room.has_connected_traversable_air(true):
				push_error("[LevelCatalog] Room air must remain connected with unused sockets sealed: %s for %s" % [module_id, level.level_id])
				valid = false
			maximum_extra_sockets = maxi(maximum_extra_sockets, room.sockets.size() - 1)
		if maximum_extra_sockets >= 0:
			room_branch_capacity += requirement.count * maximum_extra_sockets
	var room_count := level.get_room_count()
	var start_socket_count := start.sockets.size()
	if room_count < start_socket_count:
		push_error("[LevelCatalog] Room count cannot satisfy all start sockets for %s" % level.level_id)
		valid = false
	var hallway_count := level.get_hallway_count(start_socket_count)
	if hallway_count > 0 and level.hallway_module_ids.is_empty():
		push_error("[LevelCatalog] Hallway modules are required for %s" % level.level_id)
		valid = false
	if level.get_target_module_count(start_socket_count) > LevelDefinition.HARD_MAX_MODULE_COUNT:
		push_error("[LevelCatalog] Exact module count exceeds the hard limit for %s" % level.level_id)
		valid = false
	if hallway_count >= 0 and room_branch_capacity < hallway_count:
		push_error("[LevelCatalog] Room modules lack branch capacity for %s" % level.level_id)
		valid = false
	return valid

func _claim_role(module_id: StringName, role: String, claimed_roles: Dictionary, level_id: StringName) -> bool:
	if claimed_roles.has(module_id):
		push_error("[LevelCatalog] Module %s has conflicting %s and %s roles for %s" % [module_id, claimed_roles[module_id], role, level_id])
		return false
	claimed_roles[module_id] = role
	return true

func _has_only_required_sockets(module: LevelModuleDefinition) -> bool:
	if module.sockets.is_empty():
		return false
	for socket in module.sockets:
		if socket == null or not socket.requires_connection():
			return false
	return true

func _has_only_sealable_sockets(module: LevelModuleDefinition) -> bool:
	if module.sockets.is_empty():
		return false
	for socket in module.sockets:
		if socket == null or socket.requires_connection() or not StructureCell.is_structure_solid(socket.unused_fill_block_id):
			return false
	return true
