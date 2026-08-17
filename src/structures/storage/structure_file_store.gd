extends RefCounted
class_name StructureFileStore

var _root_path: String

func _init(repository_root: String) -> void:
	_root_path = repository_root.simplify_path()

func list_importable() -> Array[StructureFileEntry]:
	var entries: Array[StructureFileEntry] = []
	if not _root_path.is_absolute_path():
		return entries
	var directory := DirAccess.open(_root_path)
	if directory == null:
		return entries
	for filename in directory.get_files():
		if filename.begins_with(".") or filename.get_extension() != "tres":
			continue
		var identifier := StringName(filename.get_basename())
		if not StructureDefinition.is_valid_id(identifier):
			continue
		var path := _root_path.path_join(filename).simplify_path()
		var definition := _load_definition(path)
		if definition == null or definition.structure_id != identifier:
			continue
		entries.append(StructureFileEntry.new(identifier, path))
	entries.sort_custom(func(first: StructureFileEntry, second: StructureFileEntry) -> bool:
		return String(first.identifier) < String(second.identifier)
	)
	return entries

func import_entry(entry: StructureFileEntry) -> StructureFileResult:
	if entry == null or not _is_valid_entry_path(entry):
		return StructureFileResult.failure("Import entry is outside the repository root")
	var definition := _load_definition(entry.absolute_path)
	if definition == null or definition.structure_id != entry.identifier:
		return StructureFileResult.failure("Import resource type or ID changed")
	var draft := StructureDraft.restore_structure(definition, entry.absolute_path)
	if draft == null:
		return StructureFileResult.failure("Import resource is invalid")
	return StructureFileResult.success(draft, entry)

func export_draft(draft: StructureDraft, requested_id: StringName = &"") -> StructureFileResult:
	if draft == null or draft.is_empty():
		return StructureFileResult.failure("Empty drafts cannot be exported")
	if not _root_path.is_absolute_path() or not DirAccess.dir_exists_absolute(_root_path):
		return StructureFileResult.failure("Repository root is unavailable")
	var identifier := draft.get_identifier() if draft.is_bound() else requested_id
	if not StructureDefinition.is_valid_id(identifier):
		return StructureFileResult.failure("Export ID must be lowercase snake_case")
	if draft.is_bound() and not requested_id.is_empty() and requested_id != identifier:
		return StructureFileResult.failure("A bound draft cannot be renamed")
	var destination := draft.get_source_path() if draft.is_bound() else _root_path.path_join("%s.tres" % identifier).simplify_path()
	if not _is_direct_resource_path(destination, identifier):
		return StructureFileResult.failure("Export destination is outside the repository root")
	if draft.is_bound():
		var current := _load_definition(destination)
		if current == null or current.structure_id != identifier:
			return StructureFileResult.failure("Bound source type or ID changed")
	elif _path_exists(destination):
		return StructureFileResult.failure("Export destination already exists")
	var snapshot := _create_snapshot(draft, identifier)
	if snapshot == null:
		return StructureFileResult.failure("Draft cannot produce a valid resource")
	var temporary_path := _temporary_path(identifier)
	var save_error := _save_temporary(snapshot, temporary_path)
	if save_error != OK:
		_remove_temporary(temporary_path)
		return StructureFileResult.failure("Temporary resource save failed")
	var reloaded := _load_definition(temporary_path)
	if reloaded == null or not _resources_equal(snapshot, reloaded):
		_remove_temporary(temporary_path)
		return StructureFileResult.failure("Temporary resource round trip failed")
	if draft.is_bound():
		var current := _load_definition(destination)
		if current == null or current.structure_id != identifier:
			_remove_temporary(temporary_path)
			return StructureFileResult.failure("Bound source type or ID changed")
	elif _path_exists(destination):
		_remove_temporary(temporary_path)
		return StructureFileResult.failure("Export destination appeared during validation")
	var replace_error := _replace_temporary(temporary_path, destination)
	if replace_error != OK:
		_remove_temporary(temporary_path)
		return StructureFileResult.failure("Validated resource could not replace the destination")
	var accepted := draft.accept_export(identifier, destination)
	assert(accepted)
	return StructureFileResult.success(draft, StructureFileEntry.new(identifier, destination))

func _create_snapshot(draft: StructureDraft, identifier: StringName) -> StructureDefinition:
	if draft == null or draft.is_empty() or not StructureDefinition.is_valid_id(identifier):
		return null
	if draft.is_bound() and draft.get_identifier() != identifier:
		return null
	var definition := StructureDefinition.new()
	definition.format_version = StructureDefinition.CURRENT_FORMAT_VERSION
	definition.structure_id = identifier
	definition.size = draft.get_size()
	definition.cells = draft.snapshot_cells()
	definition.torches.assign(draft.get_torches())
	if not definition.validate():
		return null
	return definition

func _resources_equal(first: StructureDefinition, second: StructureDefinition) -> bool:
	if first == null or second == null or not second.validate():
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

func _load_definition(path: String) -> StructureDefinition:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not resource is StructureDefinition:
		return null
	var definition := resource as StructureDefinition
	return definition if definition.validate() else null

func _is_valid_entry_path(entry: StructureFileEntry) -> bool:
	return StructureDefinition.is_valid_id(entry.identifier) and _is_direct_resource_path(entry.absolute_path, entry.identifier)

func _is_direct_resource_path(path: String, identifier: StringName) -> bool:
	var simplified := path.simplify_path()
	return simplified.is_absolute_path() and simplified.get_base_dir() == _root_path and simplified.get_file() == "%s.tres" % identifier

func _temporary_path(identifier: StringName) -> String:
	var suffix := 0
	while true:
		var path := _root_path.path_join(".%s.%d.%d.tmp.tres" % [identifier, Time.get_ticks_usec(), suffix]).simplify_path()
		if not _path_exists(path):
			return path
		suffix += 1
	return ""

func _save_temporary(resource: StructureDefinition, path: String) -> Error:
	return ResourceSaver.save(resource, path)

func _replace_temporary(temporary_path: String, destination: String) -> Error:
	return DirAccess.rename_absolute(temporary_path, destination)

func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)
