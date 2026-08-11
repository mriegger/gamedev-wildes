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
	if modules.is_empty() or levels.is_empty():
		push_error("[LevelCatalog] Modules and levels are required")
		_is_valid = false
	for module in modules:
		if module == null:
			push_error("[LevelCatalog] Null module definition")
			_is_valid = false
			continue
		_is_valid = module.validate() and _is_valid
		if module.module_id.is_empty() or _modules_by_id.has(module.module_id):
			push_error("[LevelCatalog] Empty or duplicate module ID: %s" % module.module_id)
			_is_valid = false
			continue
		_modules_by_id[module.module_id] = module
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
	var start := _modules_by_id[level.start_module_id] as LevelModuleDefinition
	if start.spawn_marker == null or start.return_door_marker == null or start.sockets.is_empty():
		push_error("[LevelCatalog] Start module lacks markers or sockets for %s" % level.level_id)
		valid = false
	var minimum_terminal_count := 1 + start.sockets.size()
	if level.minimum_module_count < minimum_terminal_count:
		push_error("[LevelCatalog] Minimum module count for %s cannot close all start sockets" % level.level_id)
		valid = false
	for module_id in level.expansion_module_ids:
		if not _modules_by_id.has(module_id):
			push_error("[LevelCatalog] Unknown expansion module %s for %s" % [module_id, level.level_id])
			valid = false
			continue
		var module := _modules_by_id[module_id] as LevelModuleDefinition
		if module.sockets.size() < 2 or module.spawn_marker != null:
			push_error("[LevelCatalog] Invalid expansion module %s for %s" % [module_id, level.level_id])
			valid = false
	for module_id in level.cap_module_ids:
		if not _modules_by_id.has(module_id):
			push_error("[LevelCatalog] Unknown cap module %s for %s" % [module_id, level.level_id])
			valid = false
			continue
		var module := _modules_by_id[module_id] as LevelModuleDefinition
		if module.sockets.size() != 1 or module.spawn_marker != null:
			push_error("[LevelCatalog] Invalid cap module %s for %s" % [module_id, level.level_id])
			valid = false
	return valid
