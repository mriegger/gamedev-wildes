extends CanvasLayer
class_name DevConsole

signal open_state_changed(open: bool)

const MAX_COMMAND_HISTORY_ENTRIES: int = 100

@onready var _console_root: Control = $ConsoleRoot as Control
@onready var _command_input: LineEdit = $ConsoleRoot/ConsolePanel/CommandRow/CommandInput as LineEdit

var _command_processor: DevConsoleCommandProcessor
var _command_history: Array[String] = []
var _history_cursor: int = 0
var _history_draft: String = ""

func _ready() -> void:
	_console_root.visible = false
	set_process_input(false)
	_command_input.text_submitted.connect(_on_command_submitted)

func setup(
	inventory_model: InventoryModel,
	inventory_loadout: InventoryLoadoutCoordinator,
	actor_stats: ActorStats,
	pumpkin_patch: PumpkinPatchCoordinator,
	new_structure: Callable,
	import_structure: Callable,
	export_structure: Callable,
	exit_structure: Callable,
	set_ripple_strength: Callable,
	spawn_birds: Callable,
) -> void:
	assert(inventory_model != null and inventory_loadout != null and actor_stats != null and pumpkin_patch != null)
	assert(_command_processor == null)
	_command_processor = DevConsoleCommandProcessor.new()
	_command_processor.setup(
		inventory_model,
		inventory_loadout,
		actor_stats,
		pumpkin_patch,
		new_structure,
		import_structure,
		export_structure,
		exit_structure,
		set_ripple_strength,
		spawn_birds,
	)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_dev_console"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not is_open() or not event is InputEventKey or not event.pressed:
		return
	var key_event := event as InputEventKey
	if _is_key(key_event, KEY_UP):
		_recall_older_command()
		get_viewport().set_input_as_handled()
		return
	if _is_key(key_event, KEY_DOWN):
		_recall_newer_command()
		get_viewport().set_input_as_handled()
		return
	if not event.echo and _is_key(key_event, KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	if _command_processor == null or is_open():
		return
	_console_root.visible = true
	_command_input.clear()
	_reset_history_navigation()
	_command_input.call_deferred("grab_focus")
	open_state_changed.emit(true)

func close() -> void:
	if not is_open():
		return
	_command_input.release_focus()
	_command_input.clear()
	_reset_history_navigation()
	_console_root.visible = false
	open_state_changed.emit(false)

func is_open() -> bool:
	return _console_root.visible

func submit_command(command_line: String) -> DevConsoleCommandProcessor.ExecutionResult:
	if _command_processor == null:
		return DevConsoleCommandProcessor.ExecutionResult.REJECTED
	return _command_processor.execute(command_line)

func get_command_input() -> LineEdit:
	return _command_input

func get_console_root() -> Control:
	return _console_root

func _on_command_submitted(command_line: String) -> void:
	_record_command(command_line)
	var result := submit_command(command_line)
	if result == DevConsoleCommandProcessor.ExecutionResult.CLOSE:
		close()
		return
	_command_input.clear()
	_command_input.call_deferred("grab_focus")

func _record_command(command_line: String) -> void:
	if not command_line.strip_edges().is_empty():
		_command_history.append(command_line)
		if _command_history.size() > MAX_COMMAND_HISTORY_ENTRIES:
			_command_history.pop_front()
	_reset_history_navigation()

func _recall_older_command() -> void:
	if _command_history.is_empty():
		return
	if _history_cursor == _command_history.size():
		_history_draft = _command_input.text
	if _history_cursor > 0:
		_history_cursor -= 1
	_set_command_input_text(_command_history[_history_cursor])

func _recall_newer_command() -> void:
	if _history_cursor >= _command_history.size():
		return
	_history_cursor += 1
	if _history_cursor == _command_history.size():
		_set_command_input_text(_history_draft)
		return
	_set_command_input_text(_command_history[_history_cursor])

func _set_command_input_text(command_line: String) -> void:
	_command_input.text = command_line
	_command_input.caret_column = command_line.length()
	_command_input.deselect()

func _reset_history_navigation() -> void:
	_history_cursor = _command_history.size()
	_history_draft = ""

func _is_key(event: InputEventKey, key: Key) -> bool:
	return event.keycode == key or event.physical_keycode == key
