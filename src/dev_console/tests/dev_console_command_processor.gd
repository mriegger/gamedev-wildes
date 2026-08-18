extends SceneTree

class PumpkinPatchStub:
	extends PumpkinPatchCoordinator

	var spawn_count: int = 0

	func spawn_patch() -> bool:
		spawn_count += 1
		return true

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
	var pumpkin_patch := PumpkinPatchStub.new()
	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	inventory.slots[0] = InventoryStack.new(&"stone_block", 4)
	inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 10)
	var processor := DevConsoleCommandProcessor.new()
	_setup_processor(processor, inventory, stats, pumpkin_patch)
	_expect_result(processor.execute("spawn pumpkin_patch"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "pumpkin patch spawn command failed")
	_expect(pumpkin_patch.spawn_count == 1, "pumpkin patch command did not invoke the coordinator")

	_expect_result(processor.execute("spawn stone 5"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "stone spawn command failed")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE).count == 15, "spawn did not add to the existing backpack stack")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE + 1) == null, "spawn created a redundant backpack stack")
	_expect(inventory.get_slot(0).count == 4, "spawn changed the matching hotbar stack")
	_expect_result(processor.execute("spawn stone"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "default-count stone spawn command failed")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE).count == 16, "spawn without a count did not default to one")
	_expect(processor.execute("spawn pumpkin 1"), "pumpkin spawn command failed")
	_expect(inventory.get_inventory_item_count(&"pumpkin") == 1, "pumpkin spawn did not add one inventory item")

	for definition in item_catalog.definitions:
		var definition_inventory := InventoryModel.new(item_catalog)
		var definition_processor := DevConsoleCommandProcessor.new()
		_setup_processor(definition_processor, definition_inventory, stats, pumpkin_patch)
		_expect_result(definition_processor.execute("spawn %s 1" % definition.id), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "canonical item ID failed for %s" % definition.id)
		_expect(definition_inventory.get_backpack_item_count(definition.id) == 1, "%s ID did not add one item" % definition.id)
		_expect_result(definition_processor.execute("spawn %s 1" % definition.display_name), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "display name failed for %s" % definition.display_name)
		_expect(definition_inventory.get_backpack_item_count(definition.id) == 2, "%s display name did not add one item" % definition.display_name)
	var multi_word_inventory := InventoryModel.new(item_catalog)
	var multi_word_processor := DevConsoleCommandProcessor.new()
	_setup_processor(multi_word_processor, multi_word_inventory, stats, pumpkin_patch)
	_expect_result(multi_word_processor.execute("spawn Copper Pickaxe"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "multi-word display name failed without a count")
	_expect(multi_word_inventory.get_backpack_item_count(&"copper_pickaxe") == 1, "multi-word display name did not default to one item")

	var alias_inventory := InventoryModel.new(item_catalog)
	var alias_processor := DevConsoleCommandProcessor.new()
	_setup_processor(alias_processor, alias_inventory, stats, pumpkin_patch)
	var expected_aliases: Dictionary[String, StringName] = {
		"torches": &"torch",
	}
	for alias in expected_aliases:
		_expect_result(alias_processor.execute("spawn %s 1" % alias), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "spawn alias failed for %s" % alias)
		_expect(alias_inventory.get_backpack_item_count(expected_aliases[alias]) == 1, "%s alias spawned the wrong item" % alias)

	var split_stack_inventory := InventoryModel.new(item_catalog)
	split_stack_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 98)
	var split_stack_processor := DevConsoleCommandProcessor.new()
	_setup_processor(split_stack_processor, split_stack_inventory, stats, pumpkin_patch)
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

	_expect_result(processor.execute("give_xp 99"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "give_xp command failed")
	_expect(stats.level == 1 and stats.experience == 99, "give_xp did not add raw experience")
	_expect_result(processor.execute("GIVE_XP 126"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "case-insensitive give_xp command failed")
	_expect(stats.level == 3 and stats.experience == 0, "give_xp did not apply multi-level progression")
	_expect_result(processor.execute("give_xp +1"), DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN, "explicitly positive give_xp command failed")
	_expect(stats.level == 3 and stats.experience == 1, "explicitly positive give_xp command changed progression incorrectly")

	var maximum_grant_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var maximum_grant_processor := DevConsoleCommandProcessor.new()
	_setup_processor(maximum_grant_processor, InventoryModel.new(item_catalog), maximum_grant_stats, pumpkin_patch)
	_expect_result(
		maximum_grant_processor.execute("give_xp %d" % DevConsoleCommandProcessor.MAXIMUM_GIVE_XP_AMOUNT),
		DevConsoleCommandProcessor.ExecutionResult.KEEP_OPEN,
		"maximum give_xp amount was rejected",
	)
	_expect(
		maximum_grant_stats.get_total_experience() == DevConsoleCommandProcessor.MAXIMUM_GIVE_XP_AMOUNT,
		"maximum give_xp amount changed during leveling",
	)
	var maximum_grant_progress := maximum_grant_stats.snapshot_progression()
	_expect_result(
		maximum_grant_processor.execute("give_xp %d" % (DevConsoleCommandProcessor.MAXIMUM_GIVE_XP_AMOUNT + 1)),
		DevConsoleCommandProcessor.ExecutionResult.REJECTED,
		"give_xp amount above the command limit was accepted",
	)
	_expect(maximum_grant_stats.snapshot_progression() == maximum_grant_progress, "oversized give_xp amount changed progression")

	var before_invalid := inventory.to_dict()
	var level_before_invalid := stats.level
	var experience_before_invalid := stats.experience
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
	_expect_result(processor.execute("give_xp"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "incomplete give_xp command was accepted")
	_expect_result(processor.execute("give_xp 0"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "zero give_xp amount was accepted")
	_expect_result(processor.execute("give_xp -1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "negative give_xp amount was accepted")
	_expect_result(processor.execute("give_xp nope"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "non-numeric give_xp amount was accepted")
	_expect_result(processor.execute("give_xp 9223372036854775807"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "maximum integer give_xp amount was accepted")
	_expect_result(processor.execute("give_xp 9223372036854775808"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "overflowing integer token was accepted")
	_expect_result(processor.execute("give_xp 999999999999999999999999999999999999"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "unbounded integer token was accepted")
	_expect_result(processor.execute("give_xp 1 extra"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "give_xp command with extra arguments was accepted")
	_expect_result(processor.execute("give stone 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "unknown command was accepted")
	_expect_result(processor.execute("spawn"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "spawn command without an item was accepted")
	_expect_result(processor.execute("spawn pumpkin_patch 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "pumpkin patch count argument was accepted")
	_expect(pumpkin_patch.spawn_count == 1, "invalid pumpkin patch command invoked the coordinator")
	_expect(inventory.to_dict() == before_invalid, "invalid commands changed the inventory")
	_expect(stats.level == level_before_invalid and stats.experience == experience_before_invalid, "invalid commands changed player progression")

	var full_inventory := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		full_inventory.slots[index] = InventoryStack.new(&"dirt_block", 99)
	var full_before := full_inventory.to_dict()
	var full_processor := DevConsoleCommandProcessor.new()
	_setup_processor(full_processor, full_inventory, stats, pumpkin_patch)
	_expect_result(full_processor.execute("spawn stone 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "spawn succeeded without backpack capacity")
	_expect_result(full_processor.execute("spawn stone"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "default-count spawn succeeded without backpack capacity")
	_expect_result(full_processor.execute("spawn copper_pickaxe 1"), DevConsoleCommandProcessor.ExecutionResult.REJECTED, "equipment spawn succeeded without backpack capacity")
	_expect(full_inventory.to_dict() == full_before, "failed spawns partially changed the backpack")
	pumpkin_patch.free()

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

func _setup_processor(processor: DevConsoleCommandProcessor, inventory: InventoryModel, stats: ActorStats, pumpkin_patch: PumpkinPatchCoordinator) -> void:
	processor.setup(
		inventory,
		stats,
		pumpkin_patch,
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
