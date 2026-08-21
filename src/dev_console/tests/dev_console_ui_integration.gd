extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _errors: Array[String] = []
var _console: DevConsole
var _dungeon_clear_accepted: bool = false
var _dungeon_clear_call_count: int = 0
var _inventory: InventoryModel
var _structure_calls: Array[StringName] = []
var _structure_commands_accepted: bool = false
var _pumpkin_patch: PumpkinPatchCoordinator
var _ripple_strength: float = -1.0
var _stats: ActorStats

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_inventory = InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_pumpkin_patch = PumpkinPatchCoordinator.new()
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_console = (load("res://dev_console/presentation/dev_console.tscn") as PackedScene).instantiate() as DevConsole
	root.add_child(_console)
	root.add_child(_pumpkin_patch)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		var inventory_loadout := InventoryTestFixture.create_loadout(_inventory, _stats)
		_expect(inventory_loadout != null, "inventory loadout setup failed")
		_console.setup(
			_inventory,
			inventory_loadout,
			_stats,
			_pumpkin_patch,
			Callable(self, "_handle_structure_command").bind(&"new"),
			Callable(self, "_handle_structure_command").bind(&"import"),
			Callable(self, "_handle_structure_command").bind(&"export"),
			Callable(self, "_handle_structure_command").bind(&"exit"),
			Callable(self, "_handle_ripple_strength"),
			Callable(self, "_handle_bird_spawn"),
			Callable(self, "_handle_dungeon_clear"),
			Callable(self, "_handle_defeat_all"),
		)
		_check_closed_layout()
		_check_scene_ownership()
		_send_slash()
		_phase = 1
	elif _phase == 1 and _frame == 4:
		_expect(_console.is_open(), "slash did not open the developer console")
		var command_input := _console.get_command_input()
		_expect(command_input.has_focus(), "open console did not focus the command input")
		command_input.text = "unsubmitted draft"
		_send_history_key(KEY_UP)
		_expect(command_input.text == "unsubmitted draft", "up changed the input with empty command history")
		_send_history_key(KEY_DOWN)
		_expect(command_input.text == "unsubmitted draft", "down changed the input with empty command history")
		command_input.text = "spawn stone 5"
		command_input.text_submitted.emit(command_input.text)
		_phase = 2
	elif _phase == 2 and _frame == 6:
		_expect(_inventory.get_backpack_item_count(&"stone_block") == 5, "submitted command did not spawn into the backpack")
		_expect(_inventory.get_slot(0) == null, "submitted command spawned into the hotbar")
		_expect(_console.get_command_input().text.is_empty(), "submitted command did not clear the input")
		_expect(_console.get_command_input().has_focus(), "submitted command did not retain input focus")
		_expect(_console.is_open(), "keep-open command closed the developer console")
		var command_input := _console.get_command_input()
		command_input.text = "give_xp 50"
		command_input.text_submitted.emit(command_input.text)
		_expect(_stats.get_level() == 1 and _stats.get_experience() == 50, "submitted give_xp command did not update progression")
		_expect(_console.is_open(), "give_xp command closed the developer console")
		_stats.damage(75.0)
		command_input.text = "sethealth 40"
		command_input.text_submitted.emit(command_input.text)
		_expect(is_equal_approx(_stats.current_hp, 40.0), "submitted sethealth command did not update health")
		_expect(_console.is_open(), "sethealth command closed the developer console")
		command_input.text = "set ripple strength 0.7"
		command_input.text_submitted.emit(command_input.text)
		_expect(is_equal_approx(_ripple_strength, 0.7), "submitted ripple strength command passed the wrong value")
		_expect(_console.is_open(), "ripple strength command closed the developer console")
		command_input.text = "dev structure new"
		command_input.text_submitted.emit(command_input.text)
		_phase = 3
	elif _phase == 3 and _frame == 8:
		_expect(_console.is_open(), "rejected command closed the developer console")
		_expect(_console.get_command_input().text.is_empty(), "rejected command did not clear the input")
		_expect(_console.get_command_input().has_focus(), "rejected command did not retain input focus")
		_expect(_structure_calls == [&"new"], "rejected structure command did not route to new")
		var command_input := _console.get_command_input()
		command_input.text = "unfinished draft"
		_send_history_key(KEY_UP)
		_expect(command_input.text == "dev structure new", "up did not recall the newest rejected command")
		_expect(command_input.caret_column == command_input.text.length(), "history recall did not move the caret to the end")
		_expect(command_input.has_focus(), "history recall released input focus")
		_send_history_key(KEY_UP, true)
		_expect(command_input.text == "set ripple strength 0.7", "physical up did not recall the next older command")
		_send_history_key(KEY_UP, false, true)
		_expect(command_input.text == "sethealth 40", "repeated up did not recall an older command")
		_send_history_key(KEY_UP)
		_expect(command_input.text == "give_xp 50", "up skipped an older command")
		_send_history_key(KEY_UP)
		_expect(command_input.text == "spawn stone 5", "up did not reach the oldest command")
		_send_history_key(KEY_UP)
		_expect(command_input.text == "spawn stone 5", "up did not clamp at the oldest command")
		_send_history_key(KEY_DOWN)
		_expect(command_input.text == "give_xp 50", "down did not recall the next newer command")
		_send_history_key(KEY_DOWN, true)
		_expect(command_input.text == "sethealth 40", "physical down did not recall the next newer command")
		_send_history_key(KEY_DOWN)
		_send_history_key(KEY_DOWN)
		_expect(command_input.text == "dev structure new", "down did not reach the newest command")
		_send_history_key(KEY_DOWN)
		_expect(command_input.text == "unfinished draft", "down past the newest command did not restore the draft")
		_send_history_key(KEY_DOWN)
		_expect(command_input.text == "unfinished draft", "down did not clamp at the draft")
		_structure_commands_accepted = true
		_send_history_key(KEY_UP)
		_expect(command_input.text == "dev structure new", "up did not return to the newest command from the draft")
		command_input.text_submitted.emit(command_input.text)
		_phase = 4
	elif _phase == 4 and _frame == 10:
		_expect(not _console.is_open(), "close command kept the developer console open")
		_expect(_structure_calls == [&"new", &"new"], "accepted structure command did not route to new")
		var command_input := _console.get_command_input()
		command_input.text = "closed input"
		_send_history_key(KEY_UP)
		_expect(command_input.text == "closed input", "history navigation changed input while the console was closed")
		_send_slash()
		_phase = 5
	elif _phase == 5 and _frame == 12:
		_expect(_console.is_open(), "slash did not reopen the developer console")
		var command_input := _console.get_command_input()
		_send_history_key(KEY_UP)
		_expect(command_input.text == "dev structure new", "closing command was not retained across console reopen")
		_send_history_key(KEY_UP)
		_expect(command_input.text == "dev structure new", "duplicate command submissions were not retained")
		_send_history_key(KEY_UP)
		_expect(command_input.text == "set ripple strength 0.7", "duplicate history entries changed command order")
		_send_escape()
		_phase = 6
	elif _phase == 6 and _frame == 14:
		_expect(not _console.is_open(), "escape did not close the developer console")
		_send_slash()
		_phase = 7
	elif _phase == 7 and _frame == 16:
		_expect(_console.is_open(), "slash did not reopen the developer console after escape")
		var command_input := _console.get_command_input()
		command_input.text = "   "
		command_input.text_submitted.emit(command_input.text)
		command_input.text = "session draft"
		_send_history_key(KEY_UP)
		_expect(command_input.text == "dev structure new", "whitespace-only submission was added to history")
		_send_history_key(KEY_DOWN)
		_expect(command_input.text == "session draft", "draft was not restored after reopening the console")
		command_input.text = "  unknown original  "
		command_input.text_submitted.emit(command_input.text)
		_send_history_key(KEY_UP)
		_expect(command_input.text == "  unknown original  ", "history did not preserve the submitted command text")
		for index in range(DevConsole.MAX_COMMAND_HISTORY_ENTRIES + 1):
			command_input.text = "unknown_command_%03d" % index
			command_input.text_submitted.emit(command_input.text)
		command_input.text = "bounded draft"
		for _index in range(DevConsole.MAX_COMMAND_HISTORY_ENTRIES):
			_send_history_key(KEY_UP)
		_expect(command_input.text == "unknown_command_001", "history did not evict its oldest entry at capacity")
		_send_history_key(KEY_UP)
		_expect(command_input.text == "unknown_command_001", "bounded history did not clamp at its oldest retained entry")
		for _index in range(DevConsole.MAX_COMMAND_HISTORY_ENTRIES):
			_send_history_key(KEY_DOWN)
		_expect(command_input.text == "bounded draft", "bounded history did not restore the current draft")
		command_input.text = "dev dungeon clear"
		command_input.text_submitted.emit(command_input.text)
		_phase = 8
	elif _phase == 8 and _frame == 18:
		_expect(_console.is_open(), "rejected dungeon clear command closed the developer console")
		_expect(_dungeon_clear_call_count == 1, "rejected dungeon clear command did not call its handler")
		_dungeon_clear_accepted = true
		var command_input := _console.get_command_input()
		command_input.text = "dev dungeon clear"
		command_input.text_submitted.emit(command_input.text)
		_phase = 9
	elif _phase == 9 and _frame == 20:
		_expect(not _console.is_open(), "accepted dungeon clear command kept the developer console open")
		_expect(_dungeon_clear_call_count == 2, "accepted dungeon clear command did not call its handler")
		_send_slash()
		_phase = 10
	elif _phase == 10 and _frame == 22:
		_expect(_console.is_open(), "slash did not reopen the developer console after dungeon clear")
		_send_escape()
		_phase = 11
	elif _phase == 11 and _frame == 24:
		_expect(not _console.is_open(), "escape did not close the developer console")
		_send_slash()
		_phase = 12
	elif _phase == 12 and _frame == 26:
		_expect(_console.is_open(), "slash did not reopen the developer console after escape")
		_send_slash()
		_phase = 13
	elif _phase == 13 and _frame == 28:
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

func _check_scene_ownership() -> void:
	var game := (load("res://game/game.tscn") as PackedScene).instantiate() as Game
	_expect(game.get_node_or_null("DevConsole") is DevConsole, "Game does not own the developer console")
	_expect(game.get_node_or_null("HUD/DevConsole") == null, "HUD still owns the developer console")
	game.free()

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

func _send_history_key(key: Key, physical: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = echo
	if physical:
		event.physical_keycode = key
	else:
		event.keycode = key
	_console._input(event)

func _action_uses_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == key or key_event.physical_keycode == key:
				return true
	return false

func _handle_structure_command(action: StringName) -> bool:
	_structure_calls.append(action)
	return _structure_commands_accepted

func _handle_ripple_strength(strength: float) -> bool:
	_ripple_strength = strength
	return true

func _handle_bird_spawn(_variant_id: StringName, _count: int) -> bool:
	return true

func _handle_dungeon_clear() -> bool:
	_dungeon_clear_call_count += 1
	return _dungeon_clear_accepted

func _handle_defeat_all() -> bool:
	return true

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
