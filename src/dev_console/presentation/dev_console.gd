extends CanvasLayer
class_name DevConsole

@onready var _console_root: Control = $ConsoleRoot as Control
@onready var _command_input: LineEdit = $ConsoleRoot/ConsolePanel/CommandRow/CommandInput as LineEdit

var _command_processor: DevConsoleCommandProcessor

func _ready() -> void:
	_console_root.visible = false
	set_process_input(false)
	_command_input.text_submitted.connect(_on_command_submitted)

func setup(inventory_model: InventoryModel, pumpkin_patch_preview: PumpkinPatchPreview) -> void:
	assert(inventory_model != null and pumpkin_patch_preview != null)
	assert(_command_processor == null)
	_command_processor = DevConsoleCommandProcessor.new()
	_command_processor.setup(inventory_model, pumpkin_patch_preview)
	set_process_input(true)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_dev_console"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if is_open() and event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

func toggle() -> void:
	if is_open():
		close()
	else:
		open()

func open() -> void:
	if _command_processor == null:
		return
	_console_root.visible = true
	_command_input.clear()
	_command_input.call_deferred("grab_focus")

func close() -> void:
	_command_input.release_focus()
	_command_input.clear()
	_console_root.visible = false

func is_open() -> bool:
	return _console_root.visible

func submit_command(command_line: String) -> bool:
	if _command_processor == null:
		return false
	return _command_processor.execute(command_line)

func get_command_input() -> LineEdit:
	return _command_input

func get_console_root() -> Control:
	return _console_root

func _on_command_submitted(command_line: String) -> void:
	submit_command(command_line)
	_command_input.clear()
	_command_input.call_deferred("grab_focus")
