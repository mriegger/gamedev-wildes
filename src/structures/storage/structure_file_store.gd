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
		var resource := _load_resource(path)
		var format: Variant = _resource_format(resource)
		if format == null or _resource_identifier(resource) != identifier:
			continue
		entries.append(StructureFileEntry.new(identifier, format as StructureDraft.Format, path))
	entries.sort_custom(func(first: StructureFileEntry, second: StructureFileEntry) -> bool:
		return String(first.identifier) < String(second.identifier)
	)
	return entries

func import_entry(entry: StructureFileEntry) -> StructureFileResult:
	if entry == null or not _is_valid_entry_path(entry):
		return StructureFileResult.failure("Import entry is outside the repository root")
	var resource := _load_resource(entry.absolute_path)
	var format: Variant = _resource_format(resource)
	if format == null or format as StructureDraft.Format != entry.format or _resource_identifier(resource) != entry.identifier:
		return StructureFileResult.failure("Import resource type or ID changed")
	var draft := StructureResourceAdapter.create_draft(resource, entry.absolute_path)
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
		var current := _load_resource(destination)
		if _resource_format(current) != draft.get_format() or _resource_identifier(current) != identifier:
			return StructureFileResult.failure("Bound source type or ID changed")
	elif _path_exists(destination):
		return StructureFileResult.failure("Export destination already exists")
	var snapshot := StructureResourceAdapter.create_snapshot(draft, identifier)
	if snapshot == null:
		return StructureFileResult.failure("Draft cannot produce a valid resource")
	var temporary_path := _temporary_path(identifier)
	var save_error := _save_temporary(snapshot, temporary_path)
	if save_error != OK:
		_remove_temporary(temporary_path)
		return StructureFileResult.failure("Temporary resource save failed")
	var reloaded := _load_resource(temporary_path)
	if reloaded == null or not StructureResourceAdapter.resources_equal(snapshot, reloaded):
		_remove_temporary(temporary_path)
		return StructureFileResult.failure("Temporary resource round trip failed")
	if draft.is_bound():
		var current := _load_resource(destination)
		if _resource_format(current) != draft.get_format() or _resource_identifier(current) != identifier:
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
	return StructureFileResult.success(draft, StructureFileEntry.new(identifier, draft.get_format(), destination))

func _load_resource(path: String) -> Resource:
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is StructureDefinition:
		return resource if (resource as StructureDefinition).validate() else null
	if resource is LevelModuleDefinition:
		return resource if (resource as LevelModuleDefinition).validate() else null
	return null

func _is_valid_entry_path(entry: StructureFileEntry) -> bool:
	var format_valid := entry.format == StructureDraft.Format.GENERIC_STRUCTURE or entry.format == StructureDraft.Format.LEVEL_MODULE
	return format_valid and StructureDefinition.is_valid_id(entry.identifier) and _is_direct_resource_path(entry.absolute_path, entry.identifier)

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

func _save_temporary(resource: Resource, path: String) -> Error:
	return ResourceSaver.save(resource, path)

func _replace_temporary(temporary_path: String, destination: String) -> Error:
	return DirAccess.rename_absolute(temporary_path, destination)

func _remove_temporary(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)

func _resource_format(resource: Resource) -> Variant:
	if resource is StructureDefinition:
		return StructureDraft.Format.GENERIC_STRUCTURE
	if resource is LevelModuleDefinition:
		return StructureDraft.Format.LEVEL_MODULE
	return null

func _resource_identifier(resource: Resource) -> StringName:
	if resource is StructureDefinition:
		return (resource as StructureDefinition).structure_id
	if resource is LevelModuleDefinition:
		return (resource as LevelModuleDefinition).module_id
	return &""
