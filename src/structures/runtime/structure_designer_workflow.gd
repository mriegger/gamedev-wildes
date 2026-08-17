extends Node
class_name StructureDesignerWorkflow

signal designer_entry_requested(draft: StructureDraft)
signal designer_exit_requested

var _dialogs: StructureDesignerDialogs
var _file_store: StructureFileStore
var _draft: StructureDraft

func setup(dialogs: StructureDesignerDialogs, file_store: StructureFileStore) -> void:
	assert(dialogs != null)
	assert(file_store != null)
	assert(_dialogs == null)
	_dialogs = dialogs
	_file_store = file_store
	_dialogs.new_draft_requested.connect(_on_new_draft_requested)
	_dialogs.import_requested.connect(_on_import_requested)
	_dialogs.export_id_requested.connect(_on_export_id_requested)
	_dialogs.overwrite_confirmed.connect(_on_overwrite_confirmed)
	_dialogs.discard_confirmed.connect(_on_discard_confirmed)

func request_new() -> bool:
	if _draft != null:
		return false
	return _dialogs.show_new_dialog()

func request_import() -> bool:
	if _draft != null:
		return false
	return _dialogs.show_import_dialog(_file_store.list_importable())

func request_export() -> bool:
	if _draft == null or _dialogs.is_open():
		return false
	if _draft.is_bound():
		return _dialogs.show_overwrite_dialog(_draft.get_identifier())
	return _dialogs.show_export_id_dialog()

func request_exit() -> bool:
	if _draft == null or _dialogs.is_open():
		return false
	if _draft.is_dirty():
		return _dialogs.show_discard_dialog()
	designer_exit_requested.emit()
	return true

func cancel_active_dialog() -> bool:
	return _dialogs.close_active()

func has_active_draft() -> bool:
	return _draft != null

func is_dialog_open() -> bool:
	return _dialogs.is_open()

func complete_exit() -> void:
	assert(_draft != null)
	_draft = null

func _on_new_draft_requested(size: Vector3i) -> void:
	var next_draft := StructureDraft.create(size)
	assert(next_draft != null)
	_begin_draft(next_draft)

func _on_import_requested(entry: StructureFileEntry) -> void:
	var result := _file_store.import_entry(entry)
	if not result.succeeded:
		_dialogs.show_message("Import Failed", result.message)
		return
	_begin_draft(result.draft)

func _begin_draft(next_draft: StructureDraft) -> void:
	assert(_draft == null)
	_draft = next_draft
	designer_entry_requested.emit(_draft)

func _on_export_id_requested(identifier: StringName) -> void:
	_export(identifier)

func _on_overwrite_confirmed() -> void:
	_export()

func _export(identifier: StringName = &"") -> void:
	var result := _file_store.export_draft(_draft, identifier)
	if not result.succeeded:
		_dialogs.show_message("Export Failed", result.message)
		return
	_dialogs.show_message("Export Complete", "Saved %s.tres in the repository root." % result.entry.identifier)

func _on_discard_confirmed() -> void:
	designer_exit_requested.emit()
