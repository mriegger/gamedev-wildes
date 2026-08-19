extends SceneTree

var _errors: Array[String] = []
var _state_change_count: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var anvil_recipe_catalog := load("res://crafting/stations/anvil_recipe_catalog.tres") as CraftingRecipeCatalog
	var cauldron_recipe_catalog := load("res://crafting/stations/cauldron_recipe_catalog.tres") as CraftingRecipeCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(recipe_catalog.validate(item_catalog), "crafting catalog invalid")
	_expect(anvil_recipe_catalog.validate(item_catalog), "anvil crafting catalog invalid")
	_expect(cauldron_recipe_catalog.validate(item_catalog), "cauldron crafting catalog invalid")
	var recipe_catalogs: Array[CraftingRecipeCatalog] = [recipe_catalog, anvil_recipe_catalog, cauldron_recipe_catalog]
	for catalog in recipe_catalogs:
		for recipe in catalog.definitions:
			_expect(not recipe.output_item.description.strip_edges().is_empty(), "%s description is missing" % recipe.output_item.id)
	var expected_recipe_ids: Array[StringName] = [
		&"torch_bundle",
		&"chest",
		&"anvil",
		&"cauldron",
		&"campfire",
		&"stone_pickaxe",
		&"bow",
		&"stone_arrow_bundle",
	]
	_expect(recipe_catalog.definitions.size() == expected_recipe_ids.size(), "general recipe count differs")
	for index in range(expected_recipe_ids.size()):
		_expect(recipe_catalog.definitions[index].id == expected_recipe_ids[index], "recipe order differs at index %d" % index)
	for recipe in recipe_catalog.definitions:
		for ingredient in recipe.ingredients:
			_expect(ingredient.count >= 1, "ingredient count outside recipe range")
		if recipe.id not in [&"torch_bundle", &"stone_arrow_bundle"]:
			_expect(recipe.output_item.id == recipe.id, "%s output item mismatch" % recipe.id)
	var torch_recipe := recipe_catalog.get_definition(&"torch_bundle")
	_expect(torch_recipe.output_item.id == &"torch" and torch_recipe.output_count == 4, "torch recipe output mismatch")
	_expect(torch_recipe.get_ingredient_counts() == {&"log_block": 2, &"leaves_block": 2}, "torch recipe ingredients mismatch")
	var bow_recipe := recipe_catalog.get_definition(&"bow")
	_expect(bow_recipe.output_item.id == &"bow" and bow_recipe.output_count == 1, "bow recipe output mismatch")
	_expect(bow_recipe.get_ingredient_counts() == {&"log_block": 10}, "bow recipe ingredients mismatch")
	var stone_arrow_recipe := recipe_catalog.get_definition(&"stone_arrow_bundle")
	_expect(stone_arrow_recipe.output_item.id == &"stone_arrow" and stone_arrow_recipe.output_count == 10, "stone arrow recipe output mismatch")
	_expect(stone_arrow_recipe.get_ingredient_counts() == {&"log_block": 2, &"stone_block": 1}, "stone arrow recipe ingredients mismatch")
	var expected_copper_recipes := {
		&"copper_pickaxe": {&"copper": 10, &"log_block": 5},
		&"copper_hoe": {&"copper": 10, &"log_block": 5},
		&"copper_sword": {&"copper": 15, &"log_block": 5},
		&"copper_hammer": {&"copper": 15, &"log_block": 5},
		&"copper_helmet": {&"copper": 5},
		&"copper_chest_plate": {&"copper": 5},
		&"copper_pants": {&"copper": 5},
		&"copper_shoes": {&"copper": 5},
	}
	for recipe_id in expected_copper_recipes:
		_expect(not recipe_catalog.has_definition(recipe_id), "%s leaked into general crafting" % recipe_id)
		_expect(anvil_recipe_catalog.get_definition(recipe_id).get_ingredient_counts() == expected_copper_recipes[recipe_id], "%s ingredients mismatch" % recipe_id)
	var copper_arrow_recipe := anvil_recipe_catalog.get_definition(&"copper_arrow_bundle")
	_expect(copper_arrow_recipe.output_item.id == &"copper_arrow" and copper_arrow_recipe.output_count == 10, "copper arrow recipe output mismatch")
	_expect(copper_arrow_recipe.get_ingredient_counts() == {&"log_block": 2, &"copper": 1}, "copper arrow recipe ingredients mismatch")
	_expect(not recipe_catalog.has_definition(&"copper_arrow_bundle"), "copper arrows leaked into general crafting")
	_expect(anvil_recipe_catalog.definitions.size() == expected_copper_recipes.size() + 1, "anvil catalog does not contain every copper recipe and ammunition bundle")
	_expect(not anvil_recipe_catalog.has_definition(&"stone_pickaxe") and not anvil_recipe_catalog.has_definition(&"torch_bundle"), "non-metal recipe leaked into anvil crafting")
	_expect(not recipe_catalog.has_definition(&"basic_rune"), "Basic Rune progression reward remained directly craftable")
	_expect(
		not recipe_catalog.has_definition(&"iron_pickaxe")
		and not anvil_recipe_catalog.has_definition(&"iron_pickaxe")
		and not cauldron_recipe_catalog.has_definition(&"iron_pickaxe"),
		"Iron Pickaxe progression reward remained directly craftable",
	)
	_expect(recipe_catalog.get_definition(&"stone_pickaxe").get_ingredient_counts() == {&"stone_block": 10, &"log_block": 5}, "stone pickaxe ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"chest").get_ingredient_counts() == {&"log_block": 5}, "chest ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"anvil").get_ingredient_counts() == {&"copper": 10}, "anvil ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"cauldron").get_ingredient_counts() == {&"log_block": 3, &"stone_block": 2}, "cauldron ingredients mismatch")
	_expect(recipe_catalog.get_definition(&"campfire").get_ingredient_counts() == {&"stone_block": 12, &"log_block": 2}, "campfire ingredients mismatch")
	_expect(cauldron_recipe_catalog.definitions.size() == 1 and cauldron_recipe_catalog.has_definition(&"health_potion"), "cauldron catalog does not contain only the health potion")
	_expect(cauldron_recipe_catalog.get_definition(&"health_potion").get_ingredient_counts() == {&"pumpkin": 2, &"apple": 2}, "health potion ingredients mismatch")
	var ranged_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(ranged_inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"log_block", 14))
	InventoryTestFixture.restore_slot(ranged_inventory, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"stone_block", 1))
	InventoryTestFixture.restore_slot(ranged_inventory, InventoryModel.HOTBAR_SIZE + 2, InventoryStack.new(&"copper", 1))
	var ranged_loadout := InventoryTestFixture.create_loadout(ranged_inventory)
	var ranged_general := CraftingCoordinator.new()
	ranged_general.setup(ranged_inventory, ranged_loadout, recipe_catalog)
	_expect(ranged_general.craft(&"bow") and ranged_general.craft(&"stone_arrow_bundle"), "general ranged recipes did not craft")
	var ranged_anvil := CraftingCoordinator.new()
	ranged_anvil.setup(ranged_inventory, ranged_loadout, anvil_recipe_catalog)
	_expect(ranged_anvil.craft(&"copper_arrow_bundle"), "copper arrows did not craft at the anvil")
	_expect(ranged_inventory.get_inventory_item_count(&"bow") == 1, "bow craft did not add its output")
	_expect(ranged_inventory.get_inventory_item_count(&"stone_arrow") == 10, "stone arrow craft did not add ten arrows")
	_expect(ranged_inventory.get_inventory_item_count(&"copper_arrow") == 10, "copper arrow craft did not add ten arrows")
	_expect(ranged_inventory.get_inventory_item_count(&"log_block") == 0 and ranged_inventory.get_inventory_item_count(&"stone_block") == 0 and ranged_inventory.get_inventory_item_count(&"copper") == 0, "ranged recipes retained ingredients")

	var progression_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(progression_inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"stone_block", 10))
	InventoryTestFixture.restore_slot(progression_inventory, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"log_block", 5))
	var progression_coordinator := CraftingCoordinator.new()
	progression_coordinator.setup(progression_inventory, InventoryTestFixture.create_loadout(progression_inventory), recipe_catalog)
	_expect(progression_coordinator.craft(&"stone_pickaxe"), "stone pickaxe did not craft immediately")
	_expect(progression_inventory.get_inventory_item_count(&"stone_block") == 0, "stone pickaxe craft retained stone")
	_expect(progression_inventory.get_inventory_item_count(&"log_block") == 0, "stone pickaxe craft retained wood")
	_expect(progression_inventory.get_inventory_item_count(&"stone_pickaxe") == 1, "stone pickaxe craft did not add its output")

	var anvil_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(anvil_inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper", 10))
	var general_coordinator := CraftingCoordinator.new()
	general_coordinator.setup(anvil_inventory, InventoryTestFixture.create_loadout(anvil_inventory), recipe_catalog)
	_expect(general_coordinator.craft(&"anvil"), "anvil was not craftable from the general menu")
	_expect(anvil_inventory.get_inventory_item_count(&"copper") == 0, "anvil craft retained copper")
	_expect(anvil_inventory.get_inventory_item_count(&"anvil") == 1, "anvil craft did not add its output")

	var cauldron_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(cauldron_inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"pumpkin", 2))
	InventoryTestFixture.restore_slot(cauldron_inventory, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"apple", 2))
	var cauldron_coordinator := CraftingCoordinator.new()
	cauldron_coordinator.setup(cauldron_inventory, InventoryTestFixture.create_loadout(cauldron_inventory), cauldron_recipe_catalog)
	_expect(cauldron_coordinator.craft(&"health_potion"), "health potion was not craftable at the cauldron")
	_expect(cauldron_inventory.get_inventory_item_count(&"pumpkin") == 0 and cauldron_inventory.get_inventory_item_count(&"apple") == 0, "health potion craft retained ingredients")
	_expect(cauldron_inventory.get_inventory_item_count(&"health_potion") == 1, "health potion craft did not add its output")

	var hotbar_only := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(hotbar_only, 0, InventoryStack.new(&"copper", 10))
	InventoryTestFixture.restore_slot(hotbar_only, 1, InventoryStack.new(&"log_block", 5))
	var hotbar_coordinator := CraftingCoordinator.new()
	hotbar_coordinator.setup(hotbar_only, InventoryTestFixture.create_loadout(hotbar_only), anvil_recipe_catalog)
	_expect(hotbar_coordinator.can_craft(&"copper_pickaxe"), "hotbar materials were not available for crafting")
	_expect(hotbar_coordinator.craft(&"copper_pickaxe"), "hotbar-only craft did not complete immediately")
	_expect(hotbar_only.get_inventory_item_count(&"copper") == 0, "hotbar-only craft retained copper")
	_expect(hotbar_only.get_inventory_item_count(&"log_block") == 0, "hotbar-only craft retained wood")
	_expect(hotbar_only.get_inventory_item_count(&"copper_pickaxe") == 1, "hotbar-only craft did not add output")

	var backpack_first := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(backpack_first, 0, InventoryStack.new(&"torch", 1))
	InventoryTestFixture.restore_slot(backpack_first, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"log_block", 2))
	InventoryTestFixture.restore_slot(backpack_first, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"leaves_block", 2))
	var backpack_first_coordinator := CraftingCoordinator.new()
	backpack_first_coordinator.setup(backpack_first, InventoryTestFixture.create_loadout(backpack_first), recipe_catalog)
	_expect(backpack_first_coordinator.craft(&"torch_bundle"), "backpack-first craft did not complete immediately")
	_expect(backpack_first.get_slot(0).count == 1, "crafted output changed a hotbar stack despite backpack capacity")
	_expect(backpack_first.get_backpack_item_count(&"torch") == 4, "crafted output did not prefer the backpack")

	var chest_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(chest_inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"log_block", 5))
	var chest_coordinator := CraftingCoordinator.new()
	chest_coordinator.setup(chest_inventory, InventoryTestFixture.create_loadout(chest_inventory), recipe_catalog)
	_expect(chest_coordinator.craft(&"chest"), "chest did not craft from five wood")
	_expect(chest_inventory.get_inventory_item_count(&"log_block") == 0, "chest craft retained wood")
	_expect(chest_inventory.get_backpack_item_count(&"chest") == 1, "chest craft did not add its output")

	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper", 10))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"log_block", 5))
	var coordinator := CraftingCoordinator.new()
	coordinator.setup(inventory, InventoryTestFixture.create_loadout(inventory), anvil_recipe_catalog)
	coordinator.state_changed.connect(_on_state_changed)
	_expect(coordinator.can_craft(&"copper_pickaxe"), "available pickaxe recipe disabled")
	_expect(coordinator.craft(&"copper_pickaxe"), "pickaxe did not craft immediately")
	_expect(inventory.get_backpack_item_count(&"copper") == 0, "completed craft retained copper")
	_expect(inventory.get_backpack_item_count(&"log_block") == 0, "completed craft retained wood")
	_expect(inventory.get_backpack_item_count(&"copper_pickaxe") == 1, "completed craft did not add output")
	_expect(not coordinator.can_craft(&"copper_pickaxe"), "depleted recipe remained enabled")
	_expect(not coordinator.craft(&"copper_pickaxe"), "depleted recipe crafted")
	_expect(_state_change_count > 0, "coordinator did not announce state changes")

	var crowded := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	for index in range(InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(crowded, index, InventoryStack.new(&"dirt_block", 1))
	InventoryTestFixture.restore_slot(crowded, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"copper", 20))
	InventoryTestFixture.restore_slot(crowded, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"log_block", 8))
	var crowded_before := crowded.to_dict()
	var crowded_coordinator := CraftingCoordinator.new()
	crowded_coordinator.setup(crowded, InventoryTestFixture.create_loadout(crowded), anvil_recipe_catalog)
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
