extends SceneTree

class FailingSaveStore extends StructureFileStore:
	func _save_temporary(_resource: Resource, _path: String) -> Error:
		return ERR_CANT_CREATE

class FailingReplaceStore extends StructureFileStore:
	func _replace_temporary(_temporary_path: String, _destination: String) -> Error:
		return ERR_CANT_CREATE

class InvalidRoundTripStore extends StructureFileStore:
	func _save_temporary(resource: Resource, path: String) -> Error:
		var result := super._save_temporary(resource, path)
		if result == OK:
			ResourceSaver.save(Resource.new(), path)
		return result

class ChangingBoundSourceStore extends StructureFileStore:
	var replacement_path: String

	func _save_temporary(resource: Resource, path: String) -> Error:
		var result := super._save_temporary(resource, path)
		if result == OK:
			ResourceSaver.save(Resource.new(), replacement_path)
		return result

var _failures: Array[String] = []
var _paths_to_remove: Array[String] = []
var _directories_to_remove: Array[String] = []

func _init() -> void:
	var root_path := ProjectSettings.globalize_path("res://../").simplify_path()
	var suffix := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var store := StructureFileStore.new(root_path)
	_test_import_discovery(store, root_path, suffix)
	_test_round_trip(store, root_path, suffix)
	_test_module_round_trip(store, root_path, suffix)
	_test_variable_module_round_trip(store, root_path, suffix)
	_test_export_failures(store, root_path, suffix)
	_test_write_failure_preservation(store, root_path, suffix)
	_test_temporary_cleanup(root_path, suffix)
	_cleanup()
	if _failures.is_empty():
		print("STRUCTURE_STORAGE PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_import_discovery(store: StructureFileStore, root_path: String, suffix: String) -> void:
	var first_id := StringName("aa_structure_%s" % suffix)
	var second_id := StringName("zz_structure_%s" % suffix)
	var unrelated_id := StringName("unrelated_structure_%s" % suffix)
	var mismatch_file_id := StringName("mismatch_file_%s" % suffix)
	var mismatch_resource_id := StringName("mismatch_resource_%s" % suffix)
	var nested_id := StringName("nested_structure_%s" % suffix)
	var module_id := StringName("module_structure_%s" % suffix)
	var first_path := _track_path(root_path.path_join("%s.tres" % first_id))
	var second_path := _track_path(root_path.path_join("%s.tres" % second_id))
	var unrelated_path := _track_path(root_path.path_join("%s.tres" % unrelated_id))
	var mismatch_path := _track_path(root_path.path_join("%s.tres" % mismatch_file_id))
	var module_path := _track_path(root_path.path_join("%s.tres" % module_id))
	var nested_directory := root_path.path_join("structure_storage_nested_%s" % suffix)
	var nested_path := nested_directory.path_join("%s.tres" % nested_id)
	_directories_to_remove.append(nested_directory)
	_expect(DirAccess.make_dir_absolute(nested_directory) == OK, "nested discovery fixture directory could not be created")
	_expect(ResourceSaver.save(_make_definition(first_id, BlockId.Type.STONE), first_path) == OK, "first discovery fixture could not be saved")
	_expect(ResourceSaver.save(_make_definition(second_id, BlockId.Type.DIRT), second_path) == OK, "second discovery fixture could not be saved")
	_expect(ResourceSaver.save(Resource.new(), unrelated_path) == OK, "unrelated discovery fixture could not be saved")
	_expect(ResourceSaver.save(_make_definition(mismatch_resource_id, BlockId.Type.STONE), mismatch_path) == OK, "mismatched discovery fixture could not be saved")
	_expect(ResourceSaver.save(_make_module_definition(module_id), module_path) == OK, "Level Module discovery fixture could not be saved")
	_expect(ResourceSaver.save(_make_definition(nested_id, BlockId.Type.STONE), nested_path) == OK, "nested discovery fixture could not be saved")
	var entries := store.list_importable()
	var first_index := _entry_index(entries, first_id)
	var second_index := _entry_index(entries, second_id)
	_expect(first_index != -1 and second_index != -1 and first_index < second_index, "direct generic resources were not listed in sorted order")
	var module_entry := _find_entry(entries, module_id)
	_expect(module_entry != null and module_entry.format == StructureDraft.Format.LEVEL_MODULE, "direct Level Module resource was not listed with its type")
	var second_entry := _find_entry(entries, second_id)
	_expect(second_entry != null and second_entry.format == StructureDraft.Format.GENERIC_STRUCTURE, "direct generic resource was not listed with its type")
	_expect(_find_entry(entries, unrelated_id) == null, "unrelated root resource was listed for import")
	_expect(_find_entry(entries, mismatch_file_id) == null, "resource with a mismatched filename and ID was listed for import")
	_expect(_find_entry(entries, nested_id) == null, "nested resource was listed as a direct root import")
	var listed_entry := _find_entry(entries, first_id)
	if listed_entry == null:
		return
	_expect(ResourceSaver.save(_make_definition(first_id, BlockId.Type.DIRT), first_path) == OK, "listed resource could not be changed")
	var changed_import := store.import_entry(listed_entry)
	_expect(changed_import.succeeded and changed_import.draft.get_cell(Vector3i.ZERO) == BlockId.Type.DIRT, "cache-bypass import did not observe a changed resource")
	_expect(ResourceSaver.save(_make_module_definition(first_id), first_path) == OK, "listed resource type could not be replaced")
	var replaced_import := store.import_entry(listed_entry)
	_expect(not replaced_import.succeeded and replaced_import.message == "Import resource type or ID changed", "import accepted a resource whose type changed after listing")
	var forged_entry := StructureFileEntry.new(first_id, StructureDraft.Format.GENERIC_STRUCTURE, nested_path)
	_expect(not store.import_entry(forged_entry).succeeded, "import accepted a nested forged entry")

func _test_round_trip(store: StructureFileStore, root_path: String, suffix: String) -> void:
	var identifier := StringName("round_trip_%s" % suffix)
	var path := _track_path(root_path.path_join("%s.tres" % identifier))
	var draft := _make_draft()
	var exported := store.export_draft(draft, identifier)
	_expect(exported.succeeded and FileAccess.file_exists(path), "root export failed: %s" % exported.message)
	_expect(draft.is_bound() and draft.get_source_path() == path and not draft.is_dirty(), "successful export did not bind and clean the draft")
	var text := FileAccess.get_file_as_string(path)
	_expect(text.contains("format_version = 1"), "resource did not physically serialize format version 1")
	var entry := _find_entry(store.list_importable(), identifier)
	_expect(entry != null and entry.format == StructureDraft.Format.GENERIC_STRUCTURE and entry.absolute_path == path, "exported structure was not listed with its generic type")
	if entry == null:
		return
	var imported := store.import_entry(entry)
	_expect(imported.succeeded and imported.draft != null and not imported.draft.is_dirty(), "exported structure could not be imported: %s" % imported.message)
	if not imported.succeeded:
		return
	_expect(imported.draft.snapshot_cells() == draft.snapshot_cells(), "import changed dense cells")
	var imported_torches := imported.draft.get_torches()
	_expect(imported_torches.size() == 1 and imported_torches[0].cell == Vector3i(1, 0, 0) and imported_torches[0].support_direction == Vector3i.LEFT, "import changed typed wall torches")
	_expect(imported.draft.try_place_block(Vector3i(0, 1, 0), BlockId.Type.DIRT).succeeded, "overwrite edit fixture failed")
	var overwritten := store.export_draft(imported.draft)
	_expect(overwritten.succeeded and not imported.draft.is_dirty(), "bound overwrite failed: %s" % overwritten.message)
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as StructureDefinition
	_expect(reloaded != null and reloaded.cell_at(Vector3i(0, 1, 0)) == BlockId.Type.DIRT, "cache-bypass reload did not observe the bound overwrite")
	_expect(imported.draft.try_place_block(Vector3i(1, 1, 0), BlockId.Type.STONE).succeeded, "external replacement fixture edit failed")
	_expect(ResourceSaver.save(Resource.new(), path) == OK, "bound source could not be externally replaced")
	var external_bytes := FileAccess.get_file_as_bytes(path)
	var refused := store.export_draft(imported.draft)
	_expect(not refused.succeeded and refused.message == "Bound source type or ID changed", "bound overwrite accepted an externally replaced source")
	_expect(FileAccess.get_file_as_bytes(path) == external_bytes and imported.draft.is_dirty(), "refused bound overwrite changed the file or draft state")

func _test_module_round_trip(store: StructureFileStore, root_path: String, suffix: String) -> void:
	var identifier := StringName("module_round_trip_%s" % suffix)
	var path := _track_path(root_path.path_join("%s.tres" % identifier))
	var original := _make_module_definition(identifier)
	_expect(ResourceSaver.save(original, path) == OK, "Level Module round-trip fixture could not be saved")
	var entry := _find_entry(store.list_importable(), identifier)
	_expect(entry != null and entry.format == StructureDraft.Format.LEVEL_MODULE and entry.absolute_path == path, "Level Module was not listed with its type")
	if entry == null:
		return
	var imported := store.import_entry(entry)
	_expect(imported.succeeded and imported.draft != null and imported.draft.get_format() == StructureDraft.Format.LEVEL_MODULE, "Level Module import failed: %s" % imported.message)
	if not imported.succeeded:
		return
	var draft := imported.draft
	_expect(draft.snapshot_cells() == original.cells and is_equal_approx(draft.get_weight(), 150.25), "Level Module import changed cells or weight")
	var sockets := draft.get_sockets()
	_expect(sockets.size() == 2 and sockets[0].socket_id == &"north_entry" and sockets[1].socket_id == &"south_exit", "Level Module import changed socket order")
	var torches := draft.get_torches()
	_expect(torches.size() == 2 and torches[0].cell == Vector3i(3, 2, 3) and torches[1].cell == Vector3i(1, 2, 3), "Level Module import changed torch order")
	_expect(draft.get_spawn_marker().cell == Vector3i(1, 1, 2) and draft.get_return_door_marker().cell == Vector3i(3, 1, 2), "Level Module import changed paired markers")
	var snapshot := StructureResourceAdapter.create_snapshot(draft, identifier) as LevelModuleDefinition
	_expect(snapshot != null and StructureResourceAdapter.resources_equal(original, snapshot), "Level Module adapter snapshot changed persisted fields")
	if snapshot != null:
		snapshot.cells[StructureCell.index_of(Vector3i(4, 0, 4), snapshot.size)] = BlockId.Type.DIRT
		snapshot.sockets[0].socket_id = &"mutated"
		snapshot.torches[0].cell = Vector3i.ZERO
		snapshot.spawn_marker.cell = Vector3i.ZERO
	_expect(draft.get_cell(Vector3i(4, 0, 4)) == BlockId.Type.STONE and draft.get_sockets()[0].socket_id == &"north_entry", "Level Module snapshot exposed cells or sockets")
	_expect(draft.get_torches()[0].cell == Vector3i(3, 2, 3) and draft.get_spawn_marker().cell == Vector3i(1, 1, 2), "Level Module snapshot exposed torches or markers")
	_expect(draft.try_place_block(Vector3i(4, 3, 3), BlockId.Type.DIRT).succeeded, "Level Module overwrite edit failed")
	var overwritten := store.export_draft(draft)
	_expect(overwritten.succeeded and not draft.is_dirty(), "bound Level Module overwrite failed: %s" % overwritten.message)
	var reloaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LevelModuleDefinition
	var expected := StructureResourceAdapter.create_snapshot(draft, identifier)
	_expect(reloaded != null and StructureResourceAdapter.resources_equal(expected, reloaded), "Level Module storage round trip was not exact")
	_expect(reloaded != null and reloaded.weight == 150.25 and reloaded.cells[StructureCell.index_of(Vector3i(0, 3, 0), reloaded.size)] == StructureCell.VOID, "Level Module overwrite changed weight or VOID cells")
	_expect(reloaded != null and reloaded.sockets.size() == 2 and reloaded.sockets[0].socket_id == &"north_entry" and reloaded.sockets[1].socket_id == &"south_exit", "Level Module overwrite changed socket order")
	_expect(reloaded != null and reloaded.torches.size() == 2 and reloaded.torches[0].cell == Vector3i(3, 2, 3) and reloaded.torches[1].cell == Vector3i(1, 2, 3), "Level Module overwrite changed torch order")
	_expect(reloaded != null and reloaded.spawn_marker.cell == Vector3i(1, 1, 2) and reloaded.return_door_marker.cell == Vector3i(3, 1, 2), "Level Module overwrite changed paired markers")
	_expect(draft.try_place_block(Vector3i(3, 3, 3), BlockId.Type.STONE).succeeded, "Level Module stale-type edit failed")
	_expect(ResourceSaver.save(_make_definition(identifier, BlockId.Type.STONE), path) == OK, "bound Level Module source could not be replaced with a generic structure")
	var replacement_bytes := FileAccess.get_file_as_bytes(path)
	var stale_type := store.export_draft(draft)
	_expect(not stale_type.succeeded and stale_type.message == "Bound source type or ID changed", "bound Level Module accepted a generic source replacement")
	_expect(FileAccess.get_file_as_bytes(path) == replacement_bytes and draft.is_dirty(), "stale Level Module type changed destination bytes or draft state")
	var new_identifier := StringName("new_module_%s" % suffix)
	var new_path := _track_path(root_path.path_join("%s.tres" % new_identifier))
	var new_draft := StructureDraft.create_level_module(Vector3i(3, 3, 3))
	_expect(new_draft.try_place_block(Vector3i.ZERO, BlockId.Type.STONE).succeeded, "new Level Module export fixture failed")
	var new_export := store.export_draft(new_draft, new_identifier)
	var new_resource := ResourceLoader.load(new_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_expect(new_export.succeeded and new_resource is LevelModuleDefinition, "new Level Module draft exported the wrong resource type")
	var new_entry := _find_entry(store.list_importable(), new_identifier)
	_expect(new_entry != null and new_entry.format == StructureDraft.Format.LEVEL_MODULE, "new Level Module export was not listed with its type")

func _test_variable_module_round_trip(store: StructureFileStore, root_path: String, suffix: String) -> void:
	var identifier := StringName("variable_module_%s" % suffix)
	var path := _track_path(root_path.path_join("%s.tres" % identifier))
	var draft := StructureDraft.create_level_module(Vector3i(4, 4, 4))
	for y in 4:
		for x in 4:
			_expect(draft.try_place_block(Vector3i(x, y, 0), BlockId.Type.STONE).succeeded, "variable module boundary setup failed")
	for x in range(1, 3):
		for y in range(1, 3):
			_expect(draft.try_remove_block(Vector3i(x, y, 0)).succeeded, "variable module opening setup failed")
	_expect(draft.try_add_socket(Vector3i(1, 1, 0), LevelSocketDefinition.Direction.NORTH).succeeded, "variable module socket setup failed")
	var exported := store.export_draft(draft, identifier)
	_expect(exported.succeeded and FileAccess.file_exists(path), "variable module root export failed: %s" % exported.message)
	var entry := _find_entry(store.list_importable(), identifier)
	_expect(entry != null and entry.format == StructureDraft.Format.LEVEL_MODULE, "variable module was not listed for import")
	if entry == null:
		return
	var imported := store.import_entry(entry)
	_expect(imported.succeeded and imported.draft != null, "variable module import failed: %s" % imported.message)
	if not imported.succeeded:
		return
	_expect(imported.draft.get_socket_aperture_cells(&"north").size() == 4, "variable module import changed the derived opening")
	var expected := StructureResourceAdapter.create_snapshot(draft, identifier)
	var actual := StructureResourceAdapter.create_snapshot(imported.draft, identifier)
	_expect(StructureResourceAdapter.resources_equal(expected, actual), "variable module round trip changed persisted fields")

func _test_export_failures(store: StructureFileStore, root_path: String, suffix: String) -> void:
	var existing_id := StringName("collision_%s" % suffix)
	var existing_path := _track_path(root_path.path_join("%s.tres" % existing_id))
	_expect(ResourceSaver.save(_make_definition(existing_id, BlockId.Type.STONE), existing_path) == OK, "collision fixture could not be saved")
	var draft := _make_draft()
	var existing_bytes := FileAccess.get_file_as_bytes(existing_path)
	var collision := store.export_draft(draft, existing_id)
	_expect(not collision.succeeded and collision.message == "Export destination already exists", "first export overwrote an existing path")
	_expect(FileAccess.get_file_as_bytes(existing_path) == existing_bytes and not draft.is_bound() and draft.is_dirty(), "collision changed the destination or draft binding")
	var directory_collision_id := StringName("directory_collision_%s" % suffix)
	var directory_collision_path := root_path.path_join("%s.tres" % directory_collision_id)
	_directories_to_remove.append(directory_collision_path)
	_expect(DirAccess.make_dir_absolute(directory_collision_path) == OK, "directory collision fixture could not be created")
	var directory_collision := store.export_draft(draft, directory_collision_id)
	_expect(not directory_collision.succeeded and directory_collision.message == "Export destination already exists", "first export replaced an existing directory")
	_expect(DirAccess.dir_exists_absolute(directory_collision_path) and not draft.is_bound() and draft.is_dirty(), "directory collision changed the destination or draft binding")
	var traversal := store.export_draft(draft, &"../escape")
	_expect(not traversal.succeeded and traversal.message == "Export ID must be lowercase snake_case", "traversal export ID was accepted")
	var empty := StructureDraft.create_generic(Vector3i(2, 2, 2))
	_expect(not store.export_draft(empty, StringName("empty_%s" % suffix)).succeeded, "empty draft was exported")
	var empty_module := StructureDraft.create_level_module(Vector3i(2, 2, 2))
	_expect(not store.export_draft(empty_module, StringName("empty_module_%s" % suffix)).succeeded, "empty Level Module draft was exported")
	var missing_root := root_path.path_join("structure_storage_missing_%s" % suffix)
	var missing_store := StructureFileStore.new(missing_root)
	var missing := missing_store.export_draft(draft, StringName("missing_%s" % suffix))
	_expect(not missing.succeeded and missing.message == "Repository root is unavailable", "missing repository root did not reject export")
	_expect(not draft.is_bound() and draft.is_dirty(), "failed export changed draft binding or dirty state")

func _test_write_failure_preservation(store: StructureFileStore, root_path: String, suffix: String) -> void:
	var save_failure_id := StringName("save_failure_%s" % suffix)
	var save_failure_path := _track_path(root_path.path_join("%s.tres" % save_failure_id))
	var save_failure_draft := _make_draft()
	var failed_save := FailingSaveStore.new(root_path).export_draft(save_failure_draft, save_failure_id)
	_expect(not failed_save.succeeded and failed_save.message == "Temporary resource save failed", "temporary save failure was not reported")
	_expect(not FileAccess.file_exists(save_failure_path) and not save_failure_draft.is_bound() and save_failure_draft.is_dirty(), "temporary save failure changed destination or draft state")
	var validation_failure_id := StringName("validation_failure_%s" % suffix)
	var validation_failure_path := _track_path(root_path.path_join("%s.tres" % validation_failure_id))
	var validation_failure_draft := _make_draft()
	var failed_validation := InvalidRoundTripStore.new(root_path).export_draft(validation_failure_draft, validation_failure_id)
	_expect(not failed_validation.succeeded and failed_validation.message == "Temporary resource round trip failed", "invalid temporary round trip was accepted")
	_expect(not FileAccess.file_exists(validation_failure_path) and not validation_failure_draft.is_bound() and validation_failure_draft.is_dirty(), "temporary validation failure changed destination or draft state")
	var replacement_id := StringName("replace_failure_%s" % suffix)
	var replacement_path := _track_path(root_path.path_join("%s.tres" % replacement_id))
	var replacement_draft := _make_draft()
	_expect(store.export_draft(replacement_draft, replacement_id).succeeded, "replacement failure fixture could not be exported")
	_expect(replacement_draft.try_place_block(Vector3i(0, 1, 0), BlockId.Type.DIRT).succeeded, "replacement failure fixture edit failed")
	var before := FileAccess.get_file_as_bytes(replacement_path)
	var failed_replace := FailingReplaceStore.new(root_path).export_draft(replacement_draft)
	_expect(not failed_replace.succeeded and failed_replace.message == "Validated resource could not replace the destination", "replacement failure was not reported")
	_expect(FileAccess.get_file_as_bytes(replacement_path) == before, "replacement failure changed existing destination bytes")
	_expect(replacement_draft.is_bound() and replacement_draft.get_identifier() == replacement_id and replacement_draft.get_source_path() == replacement_path and replacement_draft.is_dirty(), "replacement failure changed draft binding or dirty state")
	var changed_id := StringName("changed_during_validation_%s" % suffix)
	var changed_path := _track_path(root_path.path_join("%s.tres" % changed_id))
	var changed_draft := _make_draft()
	_expect(store.export_draft(changed_draft, changed_id).succeeded, "changing source fixture could not be exported")
	_expect(changed_draft.try_place_block(Vector3i(0, 1, 0), BlockId.Type.DIRT).succeeded, "changing source fixture edit failed")
	var changing_store := ChangingBoundSourceStore.new(root_path)
	changing_store.replacement_path = changed_path
	var changed_result := changing_store.export_draft(changed_draft)
	_expect(not changed_result.succeeded and changed_result.message == "Bound source type or ID changed", "source change during validation was not rejected")
	_expect(not ResourceLoader.load(changed_path, "", ResourceLoader.CACHE_MODE_IGNORE) is StructureDefinition, "source change during validation was overwritten")
	_expect(changed_draft.is_bound() and changed_draft.is_dirty(), "source change during validation changed draft binding or dirty state")

func _test_temporary_cleanup(root_path: String, suffix: String) -> void:
	var directory := DirAccess.open(root_path)
	_expect(directory != null, "repository root could not be reopened")
	if directory == null:
		return
	for filename in directory.get_files():
		if suffix in filename:
			_expect(not filename.begins_with("."), "temporary resource survived a storage operation")

func _make_definition(identifier: StringName, block_id: int) -> StructureDefinition:
	var definition := StructureDefinition.new()
	definition.format_version = StructureDefinition.CURRENT_FORMAT_VERSION
	definition.structure_id = identifier
	definition.size = Vector3i(2, 2, 2)
	definition.cells.resize(8)
	definition.cells.fill(StructureCell.AIR)
	definition.cells[StructureCell.index_of(Vector3i.ZERO, definition.size)] = block_id
	return definition

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

func _make_draft() -> StructureDraft:
	var draft := StructureDraft.create_generic(Vector3i(3, 3, 3))
	_expect(draft != null, "storage draft could not be created")
	if draft == null:
		return null
	_expect(draft.try_place_block(Vector3i.ZERO, BlockId.Type.STONE).succeeded, "storage block fixture failed")
	_expect(draft.try_place_torch(Vector3i(1, 0, 0), Vector3i.LEFT).succeeded, "storage torch fixture failed")
	return draft

func _track_path(path: String) -> String:
	_paths_to_remove.append(path)
	return path

func _entry_index(entries: Array[StructureFileEntry], identifier: StringName) -> int:
	for index in entries.size():
		if entries[index].identifier == identifier:
			return index
	return -1

func _find_entry(entries: Array[StructureFileEntry], identifier: StringName) -> StructureFileEntry:
	var index := _entry_index(entries, identifier)
	return entries[index] if index != -1 else null

func _cleanup() -> void:
	for path in _paths_to_remove:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for directory in _directories_to_remove:
		var opened := DirAccess.open(directory)
		if opened != null:
			for filename in opened.get_files():
				DirAccess.remove_absolute(directory.path_join(filename))
		if DirAccess.dir_exists_absolute(directory):
			DirAccess.remove_absolute(directory)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
