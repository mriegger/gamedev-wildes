extends SceneTree

var _failures: Array[String] = []
var _draft_entries: Array[StructureDraft] = []
var _exit_request_count: int
var _new_requests: Array[Vector3i] = []
var _import_requests: Array[StructureFileEntry] = []
var _export_requests: Array[StringName] = []
var _overwrite_request_count: int
var _discard_request_count: int
var _open_states: Array[bool] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_dialog_contracts()
	await _test_workflow_state()
	if _failures.is_empty():
		print("STRUCTURE_DESIGNER_WORKFLOW PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_dialog_contracts() -> void:
	_reset_records()
	var dialogs := await _create_dialogs()
	dialogs.new_draft_requested.connect(_on_new_draft_requested)
	dialogs.import_requested.connect(_on_import_requested)
	dialogs.export_id_requested.connect(_on_export_id_requested)
	dialogs.overwrite_confirmed.connect(_on_overwrite_confirmed)
	dialogs.discard_confirmed.connect(_on_discard_confirmed)
	dialogs.open_state_changed.connect(_on_open_state_changed)
	var length := dialogs.get_node("NewDialog/Fields/LengthRow/Length") as SpinBox
	var width := dialogs.get_node("NewDialog/Fields/WidthRow/Width") as SpinBox
	var height := dialogs.get_node("NewDialog/Fields/HeightRow/Height") as SpinBox
	_expect(dialogs.get_node_or_null("NewDialog/Fields/Format") == null, "generic new dialog included a module format selector")
	_expect(dialogs.show_new_dialog(), "new dialog did not open")
	_expect((dialogs.get_node("NewDialog") as ConfirmationDialog).title == "Buildable Plot Size", "new dialog title changed")
	_expect(Vector3i(int(length.value), int(height.value), int(width.value)) == StructureDefinition.DEFAULT_SIZE, "dialog defaults changed")
	_expect(Vector3i(int(length.max_value), int(height.max_value), int(width.max_value)) == StructureDefinition.MAX_EXTENT, "dialog limits changed")
	length.value = 11
	width.value = 13
	height.value = 7
	dialogs._on_new_confirmed()
	_expect(_new_requests == [Vector3i(11, 7, 13)], "dialog did not map length, height, and width to x, y, and z")
	_expect(_open_states == [true, false] and not dialogs.is_open(), "new confirmation did not close its dialog")
	var first_entry := StructureFileEntry.new(&"first_structure", "/first_structure.tres")
	var second_entry := StructureFileEntry.new(&"second_structure", "/second_structure.tres")
	_expect(dialogs.show_import_dialog([first_entry, second_entry]), "import dialog did not open")
	var import_list := dialogs.get_node("ImportDialog/ImportList") as ItemList
	_expect(import_list.item_count == 2 and import_list.get_item_text(0) == "first_structure" and not import_list.get_item_text(0).contains("Module"), "import dialog did not present generic IDs only")
	import_list.select(1)
	dialogs._on_import_confirmed()
	_expect(_import_requests == [second_entry], "import dialog did not emit the selected entry")
	_expect(dialogs.show_export_id_dialog(), "export ID dialog did not open")
	(dialogs.get_node("ExportDialog/Fields/Identifier") as LineEdit).text = "stone_arch"
	dialogs._on_export_confirmed()
	_expect(_export_requests == [&"stone_arch"], "export dialog did not emit its trimmed ID")
	_expect(dialogs.show_overwrite_dialog(&"stone_arch"), "overwrite dialog did not open")
	_expect((dialogs.get_node("OverwriteDialog") as ConfirmationDialog).dialog_text.contains("stone_arch.tres"), "overwrite dialog omitted the bound filename")
	dialogs._on_overwrite_confirmed()
	_expect(_overwrite_request_count == 1, "overwrite confirmation did not emit")
	_expect(dialogs.show_discard_dialog(), "discard dialog did not open")
	dialogs._on_discard_confirmed()
	_expect(_discard_request_count == 1, "discard confirmation did not emit")
	dialogs.show_message("Export Complete", "Saved stone_arch.tres")
	_expect(dialogs.is_open() and (dialogs.get_node("MessageDialog") as AcceptDialog).title == "Export Complete", "message dialog did not present workflow feedback")
	dialogs.close_active()
	dialogs.queue_free()
	await process_frame

func _test_workflow_state() -> void:
	_reset_records()
	var repository_root := ProjectSettings.globalize_path("user://structure_workflow_%d" % Time.get_ticks_usec()).simplify_path()
	_expect(DirAccess.make_dir_absolute(repository_root) == OK, "workflow repository fixture could not be created")
	var dialogs := await _create_dialogs()
	var workflow := StructureDesignerWorkflow.new()
	root.add_child(workflow)
	workflow.setup(dialogs, StructureFileStore.new(repository_root))
	workflow.designer_entry_requested.connect(_on_designer_entry_requested)
	workflow.designer_exit_requested.connect(_on_designer_exit_requested)
	_expect(not workflow.request_exit() and not workflow.request_export(), "draft-only command was accepted without a draft")
	_expect(workflow.request_new(), "new command did not open its dialog")
	_expect(workflow.is_dialog_open(), "workflow did not report its open dialog")
	_expect(not workflow.request_new() and not workflow.request_import(), "duplicate entry command was accepted")
	_set_dimensions(dialogs, Vector3i(4, 3, 5))
	dialogs._on_new_confirmed()
	_expect(_draft_entries.size() == 1 and _draft_entries[0] == workflow._draft, "new command did not publish its draft")
	_expect(workflow._draft.get_size() == Vector3i(4, 3, 5), "workflow changed the requested plot size")
	_expect(workflow._draft.try_place_block(Vector3i.ZERO, BlockId.Type.STONE).succeeded, "first export fixture edit failed")
	var unbound_draft := workflow._draft
	_expect(workflow.request_export(), "first export did not request an ID")
	(dialogs.get_node("ExportDialog/Fields/Identifier") as LineEdit).text = "Invalid-ID"
	dialogs._on_export_confirmed()
	_expect(workflow._draft == unbound_draft and workflow._draft.is_dirty() and not workflow._draft.is_bound(), "invalid first export changed the active draft, dirty state, or binding")
	_expect((dialogs.get_node("MessageDialog") as AcceptDialog).title == "Export Failed", "invalid first export did not present failure feedback")
	dialogs.close_active()
	_expect(workflow.request_export(), "first export could not retry after an invalid ID")
	(dialogs.get_node("ExportDialog/Fields/Identifier") as LineEdit).text = "workflow_structure"
	dialogs._on_export_confirmed()
	var exported_path := repository_root.path_join("workflow_structure.tres")
	_expect(FileAccess.file_exists(exported_path), "first workflow export did not create its resource")
	_expect(workflow.has_active_draft() and workflow._draft.is_bound() and not workflow._draft.is_dirty(), "first export did not stay open with a clean bound draft")
	_expect(_exit_request_count == 0 and (dialogs.get_node("MessageDialog") as AcceptDialog).title == "Export Complete", "successful export exited or omitted completion feedback")
	dialogs.close_active()
	_expect(workflow._draft.try_place_block(Vector3i(1, 0, 0), BlockId.Type.DIRT).succeeded, "bound overwrite fixture edit failed")
	_expect(workflow.request_export(), "bound export did not request overwrite confirmation")
	_expect((dialogs.get_node("OverwriteDialog") as ConfirmationDialog).dialog_text.contains("workflow_structure.tres"), "bound export confirmation omitted its source")
	dialogs._on_overwrite_confirmed()
	_expect(workflow.has_active_draft() and not workflow._draft.is_dirty() and _exit_request_count == 0, "successful overwrite exited or retained dirty state")
	dialogs.close_active()
	_expect(workflow.request_exit(), "clean exported draft did not exit immediately")
	_expect(_exit_request_count == 1, "clean exit did not emit exactly once")
	workflow.complete_exit()
	_expect(workflow.request_import(), "import command did not open its dialog")
	var import_list := dialogs.get_node("ImportDialog/ImportList") as ItemList
	_expect(import_list.item_count == 1 and import_list.get_item_text(0) == "workflow_structure", "import command did not list the exported generic resource")
	dialogs._on_import_confirmed()
	_expect(_draft_entries.size() == 2 and workflow._draft == _draft_entries[1], "import command did not publish its restored draft")
	_expect(workflow._draft.is_bound() and not workflow._draft.is_dirty() and workflow._draft.get_cell(Vector3i(1, 0, 0)) == BlockId.Type.DIRT, "imported workflow draft changed binding, cleanliness, or cells")
	_expect(not workflow.request_new() and not workflow.request_import(), "entry command was accepted with an imported draft active")
	_expect(workflow._draft.try_place_block(Vector3i(2, 0, 0), BlockId.Type.STONE).succeeded, "dirty-exit fixture edit failed")
	_expect(workflow.request_exit(), "dirty imported draft did not request confirmation")
	_expect(workflow.is_dialog_open() and not workflow.request_exit(), "dirty exit was accepted while confirmation was open")
	_expect(workflow.cancel_active_dialog(), "active discard dialog did not cancel")
	_expect(workflow.has_active_draft(), "cancelled discard removed the draft")
	_expect(workflow.request_exit(), "dirty draft did not reopen discard confirmation")
	dialogs._on_discard_confirmed()
	_expect(_exit_request_count == 2 and workflow.has_active_draft(), "discard confirmation changed ownership before exit completion")
	workflow.complete_exit()
	workflow.queue_free()
	dialogs.queue_free()
	await process_frame
	_cleanup_directory(repository_root)

func _create_dialogs() -> StructureDesignerDialogs:
	var dialogs := (load("res://structures/presentation/structure_designer_dialogs.tscn") as PackedScene).instantiate() as StructureDesignerDialogs
	root.add_child(dialogs)
	await process_frame
	return dialogs

func _set_dimensions(dialogs: StructureDesignerDialogs, size: Vector3i) -> void:
	(dialogs.get_node("NewDialog/Fields/LengthRow/Length") as SpinBox).value = size.x
	(dialogs.get_node("NewDialog/Fields/WidthRow/Width") as SpinBox).value = size.z
	(dialogs.get_node("NewDialog/Fields/HeightRow/Height") as SpinBox).value = size.y

func _cleanup_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory != null:
		for filename in directory.get_files():
			DirAccess.remove_absolute(path.path_join(filename))
	if DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)

func _reset_records() -> void:
	_draft_entries.clear()
	_exit_request_count = 0
	_new_requests.clear()
	_import_requests.clear()
	_export_requests.clear()
	_overwrite_request_count = 0
	_discard_request_count = 0
	_open_states.clear()

func _on_designer_entry_requested(draft: StructureDraft) -> void:
	_draft_entries.append(draft)

func _on_designer_exit_requested() -> void:
	_exit_request_count += 1

func _on_new_draft_requested(size: Vector3i) -> void:
	_new_requests.append(size)

func _on_import_requested(entry: StructureFileEntry) -> void:
	_import_requests.append(entry)

func _on_export_id_requested(identifier: StringName) -> void:
	_export_requests.append(identifier)

func _on_overwrite_confirmed() -> void:
	_overwrite_request_count += 1

func _on_discard_confirmed() -> void:
	_discard_request_count += 1

func _on_open_state_changed(open: bool) -> void:
	_open_states.append(open)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
