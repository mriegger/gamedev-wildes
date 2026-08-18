extends SceneTree

var _errors: Array[String] = []
var _state_change_count: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var anvil_recipe_catalog := load("res://crafting/stations/anvil_recipe_catalog.tres") as CraftingRecipeCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(recipe_catalog.validate(item_catalog), "crafting catalog invalid")
	_expect(anvil_recipe_catalog.validate(item_catalog), "anvil crafting catalog invalid")
	var expected_recipe_ids: Array[StringName] = [
		&"torch_bundle",
		&"chest",
		&"anvil",
		&"cauldron",
		&"stone_pickaxe",
		&"basic_rune",
	]
	_expect(recipe_catalog.definitions.size() == expected_recipe_ids.size(), "expected six general recipes")
	for index in range(expected_recipe_ids.size()):
		_expect(recipe_catalog.definitions[index].id == expected_recipe_ids[index], "recipe order differs at index %d" % index)
	for recipe in recipe_catalog.definitions:
		for ingredient in recipe.ingredients:
			_expect(ingredient.count >= 1, "ingredient count outside recipe range")
		if recipe.id != &"torch_bundle":
			_expect(recipe.output_item.id == recipe.id, "%s output item mismatch" % recipe.id)
	var torch_recipe := recipe_catalog.get_definition(&"torch_bundle")
	_expect(torch_recipe.output_item.id == &"torch" and torch_recipe.output_count == 4, "torch recipe output mismatch")
	_expect(torch_recipe.get_ingredient_counts() == {&"log_block": 2, &"leaves_block": 2}, "torch recipe ingredients mismatch")
	var expected_copper_recipes := {
		&"copper_pickaxe": {&"copper": 10, &"log_block": 5},
		&"copper_hoe": {&"copper": 10, &"log_block": 5},
		&"copper_sword": {&"copper": 15, &"log_block": 5},
		&"copper_helmet": {&"copper": 5},
		&"copper_chest_plate": {&"copper": 5},
		&"copper_pants": {&"copper": 5},
		&"copper_shoes": {&"copper": 5},
	}
	for recipe_id in expected_copper_recipes:
		_expect(not recipe_catalog.has_definition(recipe_id), "%s leaked into general crafting" % recipe_id)
		_expect(anvil_recipe_catalog.get_definition(recipe_id).get_ingredient_counts() == expected_copper_recipes[recipe_id], "%s ingredients mismatch" % recipe_id)
	_expect(anvil_recipe_catalog.definitions.size() == expected_copper_recipes.size(), "anvil catalog does not contain seven copper recipes")
	_expect(not anvil_recipe_catalog.has_definition(&"stone_pickaxe") and not anvil_recipe_catalog.has_definition(&"torch_bundle"), "non-metal recipe leaked into anvil crafting")
	_expect(recipe_catalog.get_definition(&"stone_pickaxe").get_ingredient_counts() == {&"stone_block": 10, &"log_block": 5}, "stone pickaxe ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"chest").get_ingredient_counts() == {&"log_block": 5}, "chest ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"basic_rune").get_ingredient_counts() == {&"sand_block": 32}, "basic rune ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"anvil").get_ingredient_counts() == {&"copper": 10}, "anvil ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"cauldron").get_ingredient_counts() == {&"log_block": 3, &"stone_block": 2}, "cauldron ingredients mismatch")
	var progression_inventory := InventoryModel.new(item_catalog)
	progression_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 10)
	progression_inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 5)
	var progression_coordinator := CraftingCoordinator.new()
	progression_coordinator.setup(progression_inventory, recipe_catalog)
	_expect(progression_coordinator.craft(&"stone_pickaxe"), "stone pickaxe did not craft immediately")
	_expect(progression_inventory.get_inventory_item_count(&"stone_block") == 0, "stone pickaxe craft retained stone")
	_expect(progression_inventory.get_inventory_item_count(&"log_block") == 0, "stone pickaxe craft retained wood")
	_expect(progression_inventory.get_inventory_item_count(&"stone_pickaxe") == 1, "stone pickaxe craft did not add its output")
	var anvil_inventory := InventoryModel.new(item_catalog)
	anvil_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"copper", 10)
	var general_coordinator := CraftingCoordinator.new()
	general_coordinator.setup(anvil_inventory, recipe_catalog)
	_expect(general_coordinator.craft(&"anvil"), "anvil was not craftable from the general menu")
	_expect(anvil_inventory.get_inventory_item_count(&"copper") == 0, "anvil craft retained copper")
	_expect(anvil_inventory.get_inventory_item_count(&"anvil") == 1, "anvil craft did not add its output")

	var hotbar_only := InventoryModel.new(item_catalog)
	hotbar_only.slots[0] = InventoryStack.new(&"copper", 10)
	hotbar_only.slots[1] = InventoryStack.new(&"log_block", 5)
	var hotbar_coordinator := CraftingCoordinator.new()
	hotbar_coordinator.setup(hotbar_only, anvil_recipe_catalog)
	_expect(hotbar_coordinator.can_craft(&"copper_pickaxe"), "hotbar materials were not available for crafting")
	_expect(hotbar_coordinator.craft(&"copper_pickaxe"), "hotbar-only craft did not complete immediately")
	_expect(hotbar_only.get_inventory_item_count(&"copper") == 0, "hotbar-only craft retained copper")
	_expect(hotbar_only.get_inventory_item_count(&"log_block") == 0, "hotbar-only craft retained wood")
	_expect(hotbar_only.get_inventory_item_count(&"copper_pickaxe") == 1, "hotbar-only craft did not add output")

	var backpack_first := InventoryModel.new(item_catalog)
	backpack_first.slots[0] = InventoryStack.new(&"torch", 1)
	backpack_first.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"log_block", 2)
	backpack_first.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"leaves_block", 2)
	var backpack_first_coordinator := CraftingCoordinator.new()
	backpack_first_coordinator.setup(backpack_first, recipe_catalog)
	_expect(backpack_first_coordinator.craft(&"torch_bundle"), "backpack-first craft did not complete immediately")
	_expect(backpack_first.get_slot(0).count == 1, "crafted output changed a hotbar stack despite backpack capacity")
	_expect(backpack_first.get_backpack_item_count(&"torch") == 4, "crafted output did not prefer the backpack")

	var chest_inventory := InventoryModel.new(item_catalog)
	chest_inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"log_block", 5)
	var chest_coordinator := CraftingCoordinator.new()
	chest_coordinator.setup(chest_inventory, recipe_catalog)
	_expect(chest_coordinator.craft(&"chest"), "chest did not craft from five wood")
	_expect(chest_inventory.get_inventory_item_count(&"log_block") == 0, "chest craft retained wood")
	_expect(chest_inventory.get_backpack_item_count(&"chest") == 1, "chest craft did not add its output")

	var inventory := InventoryModel.new(item_catalog)
	inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"copper", 10)
	inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 5)
	var coordinator := CraftingCoordinator.new()
	coordinator.setup(inventory, anvil_recipe_catalog)
	coordinator.state_changed.connect(_on_state_changed)
	_expect(coordinator.can_craft(&"copper_pickaxe"), "available pickaxe recipe disabled")
	_expect(coordinator.craft(&"copper_pickaxe"), "pickaxe did not craft immediately")
	_expect(inventory.get_backpack_item_count(&"copper") == 0, "completed craft retained copper")
	_expect(inventory.get_backpack_item_count(&"log_block") == 0, "completed craft retained wood")
	_expect(inventory.get_backpack_item_count(&"copper_pickaxe") == 1, "completed craft did not add output")
	_expect(not coordinator.can_craft(&"copper_pickaxe"), "depleted recipe remained enabled")
	_expect(not coordinator.craft(&"copper_pickaxe"), "depleted recipe crafted")
	_expect(_state_change_count > 0, "coordinator did not announce state changes")

	var crowded := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.FILLABLE_SIZE):
		crowded.slots[index] = InventoryStack.new(&"dirt_block", 1)
	crowded.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"copper", 20)
	crowded.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 8)
	var crowded_before := crowded.to_dict()
	var crowded_coordinator := CraftingCoordinator.new()
	crowded_coordinator.setup(crowded, anvil_recipe_catalog)
	_expect(not crowded_coordinator.can_craft(&"copper_pickaxe"), "recipe enabled without output capacity")
	_expect(not crowded_coordinator.craft(&"copper_pickaxe"), "craft completed without output capacity")
	_expect(crowded.to_dict() == crowded_before, "failed craft changed crowded inventory")

	if _errors.is_empty():
		print("CRAFTING_SYSTEM PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _on_state_changed() -> void:
	_state_change_count += 1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
