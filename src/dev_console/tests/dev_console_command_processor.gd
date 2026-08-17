extends SceneTree

class PumpkinPatchStub:
	extends PumpkinPatchCoordinator

	var spawn_count: int = 0

	func spawn_patch() -> bool:
		spawn_count += 1
		return true

var _errors: Array[String] = []

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
	inventory.slots[0] = InventoryStack.new(&"stone_block", 4)
	inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 10)
	var processor := DevConsoleCommandProcessor.new()
	processor.setup(inventory, pumpkin_patch)
	_expect(processor.execute("spawn pumpkin_patch"), "pumpkin patch spawn command failed")
	_expect(pumpkin_patch.spawn_count == 1, "pumpkin patch command did not invoke the coordinator")

	_expect(processor.execute("spawn stone 5"), "stone spawn command failed")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE).count == 15, "spawn did not add to the existing backpack stack")
	_expect(inventory.get_slot(InventoryModel.HOTBAR_SIZE + 1) == null, "spawn created a redundant backpack stack")
	_expect(inventory.get_slot(0).count == 4, "spawn changed the matching hotbar stack")
	_expect(processor.execute("spawn pumpkin 1"), "pumpkin spawn command failed")
	_expect(inventory.get_inventory_item_count(&"pumpkin") == 1, "pumpkin spawn did not add one inventory item")

	var all_items_inventory := InventoryModel.new(item_catalog)
	var all_items_processor := DevConsoleCommandProcessor.new()
	all_items_processor.setup(all_items_inventory, pumpkin_patch)
	for definition in item_catalog.definitions:
		var before_id_count := all_items_inventory.get_backpack_item_count(definition.id)
		_expect(all_items_processor.execute("spawn %s 1" % definition.id), "canonical item ID failed for %s" % definition.id)
		_expect(all_items_inventory.get_backpack_item_count(definition.id) == before_id_count + 1, "%s ID did not add one item" % definition.id)
		var before_name_count := all_items_inventory.get_backpack_item_count(definition.id)
		_expect(all_items_processor.execute("spawn %s 1" % definition.display_name), "display name failed for %s" % definition.display_name)
		_expect(all_items_inventory.get_backpack_item_count(definition.id) == before_name_count + 1, "%s display name did not add one item" % definition.display_name)

	var alias_inventory := InventoryModel.new(item_catalog)
	var alias_processor := DevConsoleCommandProcessor.new()
	alias_processor.setup(alias_inventory, pumpkin_patch)
	var expected_aliases: Dictionary[String, StringName] = {
		"torches": &"torch",
	}
	for alias in expected_aliases:
		_expect(alias_processor.execute("spawn %s 1" % alias), "spawn alias failed for %s" % alias)
		_expect(alias_inventory.get_backpack_item_count(expected_aliases[alias]) == 1, "%s alias spawned the wrong item" % alias)

	var split_stack_inventory := InventoryModel.new(item_catalog)
	split_stack_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 98)
	var split_stack_processor := DevConsoleCommandProcessor.new()
	split_stack_processor.setup(split_stack_inventory, pumpkin_patch)
	_expect(split_stack_processor.execute("SPAWN STONE 3"), "case-insensitive spawn command failed")
	_expect(split_stack_inventory.get_slot(InventoryModel.HOTBAR_SIZE).count == 99, "spawn did not fill the existing stack first")
	_expect(split_stack_inventory.get_slot(InventoryModel.HOTBAR_SIZE + 1).count == 2, "spawn did not place overflow in a new stack")

	var before_invalid := inventory.to_dict()
	_expect(not processor.execute("spawn unknown_item 1"), "unknown item command was accepted")
	_expect(not processor.execute("spawn pickaxe 1"), "ambiguous pickaxe alias was accepted")
	_expect(not processor.execute("spawn sword 1"), "ambiguous sword alias was accepted")
	_expect(not processor.execute("spawn helmet 1"), "ambiguous helmet alias was accepted")
	_expect(not processor.execute("spawn chest_plate 1"), "ambiguous chest plate alias was accepted")
	_expect(not processor.execute("spawn pants 1"), "ambiguous pants alias was accepted")
	_expect(not processor.execute("spawn shoes 1"), "ambiguous shoes alias was accepted")
	_expect(not processor.execute("spawn stone 0"), "zero-count spawn command was accepted")
	_expect(not processor.execute("spawn stone -1"), "negative-count spawn command was accepted")
	_expect(not processor.execute("spawn stone nope"), "non-numeric spawn count was accepted")
	_expect(not processor.execute("give stone 1"), "unknown command was accepted")
	_expect(not processor.execute("spawn stone"), "incomplete spawn command was accepted")
	_expect(not processor.execute("spawn pumpkin_patch 1"), "pumpkin patch count argument was accepted")
	_expect(pumpkin_patch.spawn_count == 1, "invalid pumpkin patch command invoked the coordinator")
	_expect(inventory.to_dict() == before_invalid, "invalid commands changed the inventory")

	var full_inventory := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		full_inventory.slots[index] = InventoryStack.new(&"dirt_block", 99)
	var full_before := full_inventory.to_dict()
	var full_processor := DevConsoleCommandProcessor.new()
	full_processor.setup(full_inventory, pumpkin_patch)
	_expect(not full_processor.execute("spawn stone 1"), "spawn succeeded without backpack capacity")
	_expect(not full_processor.execute("spawn copper_pickaxe 1"), "equipment spawn succeeded without backpack capacity")
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
