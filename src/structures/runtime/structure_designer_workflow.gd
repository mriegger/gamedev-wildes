extends Node
class_name StructureDesignerWorkflow

signal designer_entry_requested(draft: StructureDraft)
signal designer_exit_requested

var _dialogs: StructureDesignerDialogs
var _draft: StructureDraft

func setup(dialogs: StructureDesignerDialogs) -> void:
	assert(dialogs != null)
	assert(_dialogs == null)
	_dialogs = dialogs
	_dialogs.new_draft_requested.connect(_on_new_draft_requested)
	_dialogs.discard_confirmed.connect(_on_discard_confirmed)

func request_new() -> bool:
	if _draft != null:
		return false
	return _dialogs.show_new_dialog()

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
	_draft = next_draft
	designer_entry_requested.emit(_draft)

func _on_discard_confirmed() -> void:
	designer_exit_requested.emit()
