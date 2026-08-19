extends RefCounted
class_name CraftingCoordinator

signal state_changed

var inventory_model: InventoryModel
var inventory_loadout: InventoryLoadoutCoordinator
var recipe_catalog: CraftingRecipeCatalog

func setup(
	p_inventory_model: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_recipe_catalog: CraftingRecipeCatalog,
) -> void:
	assert(p_inventory_model != null)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory_model)
	assert(p_recipe_catalog != null)
	assert(inventory_model == null)
	inventory_model = p_inventory_model
	inventory_loadout = p_inventory_loadout
	recipe_catalog = p_recipe_catalog
	inventory_model.inventory_changed.connect(_on_inventory_changed)

func can_craft(recipe_id: StringName) -> bool:
	if not recipe_catalog.has_definition(recipe_id):
		return false
	var recipe := recipe_catalog.get_definition(recipe_id)
	return inventory_loadout.can_exchange_inventory_items(
		recipe.get_ingredient_counts(),
		recipe.get_output_counts(),
	)

func craft(recipe_id: StringName) -> bool:
	if not can_craft(recipe_id):
		return false
	var recipe := recipe_catalog.get_definition(recipe_id)
	var ingredient_counts := recipe.get_ingredient_counts()
	var output_counts := recipe.get_output_counts()
	var crafted := inventory_loadout.exchange_inventory_items(
		ingredient_counts,
		output_counts,
	)
	if not crafted:
		return false
	return true

func _on_inventory_changed() -> void:
	state_changed.emit()
