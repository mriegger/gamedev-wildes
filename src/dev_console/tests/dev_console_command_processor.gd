extends SceneTree

var _errors: Array[String] = []
var _structure_calls: Array[StringName] = []
var _structure_commands_accepted: bool = true

func _init() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(item_catalog.has_definition(&"copper"), "copper item was missing from the catalog")
	var copper := item_catalog.get_definition(&"copper")
	_expect(copper.display_name == "Copper", "copper display name mismatch")
	_expect(copper.max_stack == 99, "copper stack limit mismatch")
	_expect(copper.icon != null and copper.icon.resource_path == "res://assets/textures/blocks/copper.png", "copper texture mismatch")
	_expect(copper.icon != null and copper.icon.get_width() == 16 and copper.icon.get_height() == 16, "copper texture was not 16x16")
	var inventory := InventoryModel.new(item_catalog)
	inventory.slots[0] = InventoryStack.new(&"stone_block", 4)
	inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 10)
	var processor := DevConsoleCommandProcessor.new()
	_setup_processor(processor, inventory)

	_expect_result(processor.execute("spawn stone 5"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "stone spawn command failed")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE).count == 15, "spawn did not add to the existing backpack stack")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE + 1) == null, "spawn created a redundant backpack stack")
	_expect(inventory.get_slot(0).count == 4, "spawn changed the matching hotbar stack")

	var all_items_inventory := InventoryModel.new(item_catalog)
	var all_items_processor := DevConsoleCommandProcessor.new()
	_setup_processor(all_items_processor, all_items_inventory)
	for definition in item_catalog.definitions:
		var before_id_count := all_items_inventory.get_backpack_item_count(definition.id)
		_expect_result(all_items_processor.execute("spawn %s 1" % definition.id), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "canonical item ID failed for %s" % definition.id)
		_expect(all_items_inventory.get_backpack_item_count(definition.id) == before_id_count + 1, "%s ID did not add one item" % definition.id)
		var before_name_count := all_items_inventory.get_backpack_item_count(definition.id)
		_expect_result(all_items_processor.execute("spawn %s 1" % definition.display_name), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "display name failed for %s" % definition.display_name)
		_expect(all_items_inventory.get_backpack_item_count(definition.id) == before_name_count + 1, "%s display name did not add one item" % definition.display_name)

	var alias_inventory := InventoryModel.new(item_catalog)
	var alias_processor := DevConsoleCommandProcessor.new()
	_setup_processor(alias_processor, alias_inventory)
	var expected_aliases: Dictionary[String, StringName] = {
		"torches": &"torch",
	}
	for alias in expected_aliases:
		_expect_result(alias_processor.execute("spawn %s 1" % alias), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "spawn alias failed for %s" % alias)
		_expect(alias_inventory.get_backpack_item_count(expected_aliases[alias]) == 1, "%s alias spawned the wrong item" % alias)

	var split_stack_inventory := InventoryModel.new(item_catalog)
	split_stack_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 98)
	var split_stack_processor := DevConsoleCommandProcessor.new()
	_setup_processor(split_stack_processor, split_stack_inventory)
	_expect_result(split_stack_processor.execute("SPAWN STONE 3"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "case-insensitive spawn command failed")
	_expect(split_stack_inventory.get_slot(InventoryModel.HOTBAR_SIZE).count == 99, "spawn did not fill the existing stack first")
	_expect(split_stack_inventory.get_slot(InventoryModel.HOTBAR_SIZE + 1).count == 2, "spawn did not place overflow in a new stack")
	_structure_calls.clear()
	_structure_commands_accepted = true
	_expect_result(processor.execute("DeV StRuCtUrE NeW"), DevConsoleCommandProcessor.ExecutionResult.CLOSE, "new structure command did not close")
	_expect_result(processor.execute("dev STRUCTURE import"), DevConsoleCommandProcessor.ExecutionResult.CLOSE, "import structure command did not close")
	_expect_result(processor.execute("DEV structure EXPORT"), DevConsoleCommandProcessor.ExecutionResult.CLOSE, "export structure command did not close")
	_expect_result(processor.execute("dev structure exit"), DevConsoleCommandProcessor.ExecutionResult.CLOSE, "exit structure command did not close")
	_expect(_structure_calls == [&"new", &"import", &"export", &"exit"], "structure commands did not route to their injected handlers")
	_structure_commands_accepted = false
	_expect_result(processor.execute("dev structure export"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "rejected structure handler closed the console")
	_expect(_structure_calls.back() == &"export", "rejected structure command did not call its handler")
	var structure_call_count := _structure_calls.size()
	for invalid_command in [
		"dev structure",
		"dev structure new extra",
		"dev structures new",
		"structure new",
		"dev structure newest",
		"developer structure new",
	]:
		_expect_result(processor.execute(invalid_command), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "invalid structure command was accepted: %s" % invalid_command)
	_expect(_structure_calls.size() == structure_call_count, "invalid structure command called a handler")

	var before_invalid := inventory.to_dict()
	_expect_result(processor.execute("spawn unknown_item 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "unknown item command was accepted")
	_expect_result(processor.execute("spawn pickaxe 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "ambiguous pickaxe alias was accepted")
	_expect_result(processor.execute("spawn sword 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "ambiguous sword alias was accepted")
	_expect_result(processor.execute("spawn helmet 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "ambiguous helmet alias was accepted")
	_expect_result(processor.execute("spawn chest_plate 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "ambiguous chest plate alias was accepted")
	_expect_result(processor.execute("spawn pants 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "ambiguous pants alias was accepted")
	_expect_result(processor.execute("spawn shoes 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "ambiguous shoes alias was accepted")
	_expect_result(processor.execute("spawn stone 0"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "zero-count spawn command was accepted")
	_expect_result(processor.execute("spawn stone -1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "negative-count spawn command was accepted")
	_expect_result(processor.execute("spawn stone nope"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "non-numeric spawn count was accepted")
	_expect_result(processor.execute("give stone 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "unknown command was accepted")
	_expect_result(processor.execute("spawn stone"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "incomplete spawn command was accepted")
	_expect(inventory.to_dict() == before_invalid, "invalid commands changed the inventory")

	var full_inventory := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		full_inventory.slots[index] = InventoryStack.new(&"dirt_block", 99)
	var full_before := full_inventory.to_dict()
	var full_processor := DevConsoleCommandProcessor.new()
	_setup_processor(full_processor, full_inventory)
	_expect_result(full_processor.execute("spawn stone 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "spawn succeeded without backpack capacity")
	_expect_result(full_processor.execute("spawn copper_pickaxe 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "equipment spawn succeeded without backpack capacity")
	_expect(full_inventory.to_dict() == full_before, "failed spawns partially changed the backpack")

	if _errors.is_empty():
		print("DEV_CONSOLE_COMMAND PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _setup_processor(processor: DevConsoleCommandProcessor, inventory: InventoryModel) -> void:
	processor.setup(
		inventory,
		Callable(self, "_handle_structure_command").bind(&"new"),
		Callable(self, "_handle_structure_command").bind(&"import"),
		Callable(self, "_handle_structure_command").bind(&"export"),
		Callable(self, "_handle_structure_command").bind(&"exit"),
	)

func _handle_structure_command(action: StringName) -> bool:
	_structure_calls.append(action)
	return _structure_commands_accepted

func _expect_result(actual: DevConsoleCommandProcessor.ExecutionResult, expected: DevConsoleCommandProcessor.ExecutionResult, message: String) -> void:
	_expect(actual == expected, message)
