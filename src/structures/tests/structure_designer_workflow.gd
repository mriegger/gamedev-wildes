extends SceneTree

var _failures: Array[String] = []
var _draft_entries: Array[StructureDraft] = []
var _exit_request_count: int
var _new_requests: Array[Vector3i] = []
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
	dialogs.discard_confirmed.connect(_on_discard_confirmed)
	dialogs.open_state_changed.connect(_on_open_state_changed)
	var length := dialogs.get_node("NewDialog/Fields/LengthRow/Length") as SpinBox
	var width := dialogs.get_node("NewDialog/Fields/WidthRow/Width") as SpinBox
	var height := dialogs.get_node("NewDialog/Fields/HeightRow/Height") as SpinBox
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
	_expect(dialogs.show_discard_dialog(), "discard dialog did not open")
	dialogs._on_discard_confirmed()
	_expect(_discard_request_count == 1, "discard confirmation did not emit")
	dialogs.queue_free()
	await process_frame

func _test_workflow_state() -> void:
	_reset_records()
	var dialogs := await _create_dialogs()
	var workflow := StructureDesignerWorkflow.new()
	root.add_child(workflow)
	workflow.setup(dialogs)
	workflow.designer_entry_requested.connect(_on_designer_entry_requested)
	workflow.designer_exit_requested.connect(_on_designer_exit_requested)
	_expect(not workflow.request_exit(), "exit was accepted without a draft")
	_expect(workflow.request_new(), "new command did not open its dialog")
	_expect(workflow.is_dialog_open(), "workflow did not report its open dialog")
	_expect(not workflow.request_new(), "duplicate new command was accepted")
	_set_dimensions(dialogs, Vector3i(4, 3, 5))
	dialogs._on_new_confirmed()
	_expect(_draft_entries.size() == 1 and _draft_entries[0] == workflow._draft, "new command did not publish its draft")
	_expect(workflow._draft.get_size() == Vector3i(4, 3, 5), "workflow changed the requested plot size")
	_expect(not workflow.request_new(), "new command was accepted with an active draft")
	_expect(workflow.request_exit(), "clean draft did not exit immediately")
	_expect(_exit_request_count == 1, "clean exit did not emit exactly once")
	workflow.complete_exit()
	_expect(not workflow.has_active_draft(), "completed exit retained the draft")
	_expect(workflow.request_new(), "new command did not reopen after completion")
	_set_dimensions(dialogs, Vector3i(3, 3, 3))
	dialogs._on_new_confirmed()
	_expect(workflow._draft.try_place_block(Vector3i.ZERO, BlockId.Type.STONE).succeeded, "dirty-exit fixture edit failed")
	_expect(workflow.request_exit(), "dirty draft did not request confirmation")
	_expect(workflow.is_dialog_open() and not workflow.request_exit(), "dirty exit accepted while confirmation was open")
	_expect(workflow.cancel_active_dialog(), "active discard dialog did not cancel")
	_expect(workflow.has_active_draft(), "cancelled discard removed the draft")
	_expect(workflow.request_exit(), "dirty draft did not reopen discard confirmation")
	dialogs._on_discard_confirmed()
	_expect(_exit_request_count == 2 and workflow.has_active_draft(), "discard confirmation changed ownership before exit completion")
	workflow.complete_exit()
	workflow.queue_free()
	dialogs.queue_free()
	await process_frame

func _create_dialogs() -> StructureDesignerDialogs:
	var dialogs := (load("res://structures/presentation/structure_designer_dialogs.tscn") as PackedScene).instantiate() as StructureDesignerDialogs
	root.add_child(dialogs)
	await process_frame
	return dialogs

func _set_dimensions(dialogs: StructureDesignerDialogs, size: Vector3i) -> void:
	(dialogs.get_node("NewDialog/Fields/LengthRow/Length") as SpinBox).value = size.x
	(dialogs.get_node("NewDialog/Fields/WidthRow/Width") as SpinBox).value = size.z
	(dialogs.get_node("NewDialog/Fields/HeightRow/Height") as SpinBox).value = size.y

func _reset_records() -> void:
	_draft_entries.clear()
	_exit_request_count = 0
	_new_requests.clear()
	_discard_request_count = 0
	_open_states.clear()

func _on_designer_entry_requested(draft: StructureDraft) -> void:
	_draft_entries.append(draft)

func _on_designer_exit_requested() -> void:
	_exit_request_count += 1

func _on_new_draft_requested(size: Vector3i) -> void:
	_new_requests.append(size)

func _on_discard_confirmed() -> void:
	_discard_request_count += 1

func _on_open_state_changed(open: bool) -> void:
	_open_states.append(open)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
