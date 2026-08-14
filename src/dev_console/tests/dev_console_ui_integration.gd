extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _errors: Array[String] = []
var _console: DevConsole
var _inventory: InventoryModel
var _pumpkin_preview: PumpkinPatchPreview

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_inventory = InventoryModel.new(item_catalog)
	_pumpkin_preview = PumpkinPatchPreview.new()
	_console = (load("res://dev_console/presentation/dev_console.tscn") as PackedScene).instantiate() as DevConsole
	root.add_child(_console)
	root.add_child(_pumpkin_preview)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		_console.setup(_inventory, _pumpkin_preview)
		_check_closed_layout()
		_send_slash()
		_phase = 1
	elif _phase == 1 and _frame == 4:
		_expect(_console.is_open(), "slash did not open the developer console")
		var command_input := _console.get_command_input()
		_expect(command_input.has_focus(), "open console did not focus the command input")
		command_input.text = "spawn stone 5"
		command_input.text_submitted.emit(command_input.text)
		_phase = 2
	elif _phase == 2 and _frame == 6:
		_expect(_inventory.get_backpack_item_count(&"stone_block") == 5, "submitted command did not spawn into the backpack")
		_expect(_inventory.get_slot(0) == null, "submitted command spawned into the hotbar")
		_expect(_console.get_command_input().text.is_empty(), "submitted command did not clear the input")
		_expect(_console.get_command_input().has_focus(), "submitted command did not retain input focus")
		_send_escape()
		_phase = 3
	elif _phase == 3 and _frame == 8:
		_expect(not _console.is_open(), "escape did not close the developer console")
		_send_slash()
		_phase = 4
	elif _phase == 4 and _frame == 10:
		_expect(_console.is_open(), "slash did not reopen the developer console")
		_send_slash()
		_phase = 5
	elif _phase == 5 and _frame == 12:
		_expect(not _console.is_open(), "slash did not close the developer console")
		_finish()
	return false

func _check_closed_layout() -> void:
	_expect(not _console.is_open(), "developer console started open")
	_expect(_action_uses_key(&"toggle_dev_console", KEY_SLASH), "developer console action was not mapped to slash")
	var console_root := _console.get_console_root()
	var panel := console_root.get_node("ConsolePanel") as PanelContainer
	var prompt := panel.get_node("CommandRow/Prompt") as Label
	var command_input := _console.get_command_input()
	_expect(console_root.mouse_filter == Control.MOUSE_FILTER_STOP, "open console did not block gameplay mouse input")
	_expect(panel.anchor_bottom == 1.0 and panel.anchor_top == 1.0, "developer console was not anchored to the bottom")
	_expect(panel.offset_left == 0.0 and panel.offset_right == 0.0 and panel.offset_bottom == 0.0, "developer console did not reach the screen edges")
	_expect(prompt.text == "> ", "developer console prompt was not prepended")
	var prompt_font := prompt.get_theme_font("font")
	var input_font := command_input.get_theme_font("font")
	_expect(prompt_font is SystemFont and input_font == prompt_font, "developer console did not use one system monospace font")
	if prompt_font is SystemFont:
		var system_font := prompt_font as SystemFont
		_expect(system_font.font_names.has("monospace"), "developer console font did not include a generic monospace fallback")
	_expect(command_input.placeholder_text.is_empty(), "developer console unexpectedly showed placeholder text")
	_expect(command_input.keep_editing_on_text_submit, "developer console did not retain editing focus after submission")
	var panel_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
	_expect(panel_style != null and panel_style.bg_color.get_luminance() < 0.05, "developer console background was not black")
	_expect(panel_style != null and panel_style.content_margin_left >= 12.0, "developer console prompt did not have horizontal padding")

func _send_slash() -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_SLASH
	event.physical_keycode = KEY_SLASH
	_console._input(event)

func _send_escape() -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	_console._input(event)

func _action_uses_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == key or key_event.physical_keycode == key:
				return true
	return false

func _finish() -> void:
	if _errors.is_empty():
		print("DEV_CONSOLE_UI PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
