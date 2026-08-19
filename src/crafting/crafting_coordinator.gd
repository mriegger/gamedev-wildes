extends RefCounted
class_name CraftingCoordinator

signal state_changed

var inventory_model: InventoryModel
var recipe_catalog: CraftingRecipeCatalog
var equipment_instance_factory: EquipmentInstanceFactory

func setup(
	p_inventory_model: InventoryModel,
	p_recipe_catalog: CraftingRecipeCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
) -> void:
	assert(p_inventory_model != null)
	assert(p_recipe_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_inventory_model.equipment_instance_factory == p_equipment_instance_factory)
	assert(inventory_model == null)
	inventory_model = p_inventory_model
	recipe_catalog = p_recipe_catalog
	equipment_instance_factory = p_equipment_instance_factory
	inventory_model.inventory_changed.connect(_on_inventory_changed)

func can_craft(recipe_id: StringName) -> bool:
	if not recipe_catalog.has_definition(recipe_id):
		return false
	var recipe := recipe_catalog.get_definition(recipe_id)
	return inventory_model.can_exchange_inventory_items(
		recipe.get_ingredient_counts(),
		recipe.get_output_counts(),
		equipment_instance_factory,
	)

func craft(recipe_id: StringName) -> bool:
	if not can_craft(recipe_id):
		return false
	var recipe := recipe_catalog.get_definition(recipe_id)
	var ingredient_counts := recipe.get_ingredient_counts()
	var output_counts := recipe.get_output_counts()
	var crafted := inventory_model.exchange_inventory_items(
		ingredient_counts,
		output_counts,
		equipment_instance_factory,
	)
	if not crafted:
		return false
	return true

func _on_inventory_changed() -> void:
	state_changed.emit()
