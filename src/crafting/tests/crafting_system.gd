extends SceneTree

var _errors: Array[String] = []
var _state_change_count: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(recipe_catalog.validate(item_catalog), "crafting catalog invalid")
	var expected_recipe_ids: Array[StringName] = [
		&"torch_bundle",
		&"copper_pickaxe",
		&"copper_sword",
		&"copper_helmet",
		&"copper_chest_plate",
		&"copper_pants",
		&"copper_shoes",
	]
	_expect(recipe_catalog.definitions.size() == expected_recipe_ids.size(), "expected seven recipes")
	for recipe_id in expected_recipe_ids:
		_expect(recipe_catalog.has_definition(recipe_id), "missing recipe %s" % recipe_id)
	var copper_material_ids: Array[StringName] = [&"stone_block", &"sand_block", &"log_block"]
	for recipe in recipe_catalog.definitions:
		_expect(is_equal_approx(recipe.duration_seconds, 2.0), "recipe duration mismatch for %s" % recipe.id)
		for ingredient in recipe.ingredients:
			_expect(ingredient.count >= 1 and ingredient.count <= 5, "ingredient count outside recipe range")
			if recipe.id != &"torch_bundle":
				_expect(ingredient.item.id in copper_material_ids, "%s used unsupported material %s" % [recipe.id, ingredient.item.id])
		if recipe.id != &"torch_bundle":
			_expect(recipe.output_item.id == recipe.id, "%s output item mismatch" % recipe.id)
	var torch_recipe := recipe_catalog.get_definition(&"torch_bundle")
	_expect(torch_recipe.output_item.id == &"torch" and torch_recipe.output_count == 4, "torch recipe output mismatch")
	_expect(torch_recipe.get_ingredient_counts() == {&"log_block": 2, &"leaves_block": 2}, "torch recipe ingredients mismatch")

	var hotbar_only := InventoryModel.new(item_catalog)
	hotbar_only.slots[0] = InventoryStack.new(&"stone_block", 3)
	hotbar_only.slots[1] = InventoryStack.new(&"log_block", 2)
	var hotbar_coordinator := CraftingCoordinator.new()
	hotbar_coordinator.setup(hotbar_only, recipe_catalog)
	_expect(hotbar_coordinator.can_craft(&"copper_pickaxe"), "hotbar materials were not available for crafting")
	_expect(hotbar_coordinator.start(&"copper_pickaxe"), "hotbar-only craft did not start")
	_expect(hotbar_coordinator.advance_time(2.0), "hotbar-only craft did not complete")
	_expect(hotbar_only.get_inventory_item_count(&"stone_block") == 0, "hotbar-only craft retained stone")
	_expect(hotbar_only.get_inventory_item_count(&"log_block") == 0, "hotbar-only craft retained wood")
	_expect(hotbar_only.get_inventory_item_count(&"copper_pickaxe") == 1, "hotbar-only craft did not add output")

	var backpack_first := InventoryModel.new(item_catalog)
	backpack_first.slots[0] = InventoryStack.new(&"torch", 1)
	backpack_first.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"log_block", 2)
	backpack_first.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"leaves_block", 2)
	var backpack_first_coordinator := CraftingCoordinator.new()
	backpack_first_coordinator.setup(backpack_first, recipe_catalog)
	_expect(backpack_first_coordinator.start(&"torch_bundle"), "backpack-first craft did not start")
	_expect(backpack_first_coordinator.advance_time(2.0), "backpack-first craft did not complete")
	_expect(backpack_first.get_slot(0).count == 1, "crafted output changed a hotbar stack despite backpack capacity")
	_expect(backpack_first.get_backpack_item_count(&"torch") == 4, "crafted output did not prefer the backpack")

	var inventory := InventoryModel.new(item_catalog)
	inventory.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 3)
	inventory.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 2)
	var coordinator := CraftingCoordinator.new()
	coordinator.setup(inventory, recipe_catalog)
	coordinator.state_changed.connect(_on_state_changed)
	_expect(coordinator.can_craft(&"copper_pickaxe"), "available pickaxe recipe disabled")
	_expect(coordinator.start(&"copper_pickaxe"), "pickaxe craft did not start")
	_expect(not coordinator.advance_time(1.9), "pickaxe completed before two seconds")
	_expect(coordinator.is_crafting(), "pickaxe craft stopped early")
	_expect(is_equal_approx(coordinator.get_progress(), 0.95), "craft progress mismatch")
	_expect(coordinator.cancel(), "active craft did not cancel")
	_expect(not coordinator.is_crafting() and is_zero_approx(coordinator.get_progress()), "cancel did not reset progress")
	_expect(inventory.get_backpack_item_count(&"stone_block") == 3, "cancel consumed stone")
	_expect(inventory.get_backpack_item_count(&"log_block") == 2, "cancel consumed wood")
	_expect(coordinator.start(&"copper_pickaxe"), "second pickaxe craft did not start")
	_expect(coordinator.advance_time(2.0), "pickaxe did not complete at two seconds")
	_expect(inventory.get_backpack_item_count(&"stone_block") == 0, "completed craft retained stone")
	_expect(inventory.get_backpack_item_count(&"log_block") == 0, "completed craft retained wood")
	_expect(inventory.get_backpack_item_count(&"copper_pickaxe") == 1, "completed craft did not add output")
	_expect(not coordinator.can_craft(&"copper_pickaxe"), "depleted recipe remained enabled")
	_expect(_state_change_count > 0, "coordinator did not announce state changes")

	var crowded := InventoryModel.new(item_catalog)
	for index in range(InventoryModel.FILLABLE_SIZE):
		crowded.slots[index] = InventoryStack.new(&"dirt_block", 1)
	crowded.slots[InventoryModel.HOTBAR_SIZE] = InventoryStack.new(&"stone_block", 8)
	crowded.slots[InventoryModel.HOTBAR_SIZE + 1] = InventoryStack.new(&"log_block", 8)
	var crowded_before := crowded.to_dict()
	var crowded_coordinator := CraftingCoordinator.new()
	crowded_coordinator.setup(crowded, recipe_catalog)
	_expect(not crowded_coordinator.can_craft(&"copper_pickaxe"), "recipe enabled without output capacity")
	_expect(not crowded_coordinator.start(&"copper_pickaxe"), "craft started without output capacity")
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
