extends RefCounted
class_name CraftingCoordinator

signal state_changed

var inventory_model: InventoryModel
var recipe_catalog: CraftingRecipeCatalog

var _active_recipe_id: StringName = &""
var _elapsed_seconds: float = 0.0

func setup(p_inventory_model: InventoryModel, p_recipe_catalog: CraftingRecipeCatalog) -> void:
	assert(p_inventory_model != null)
	assert(p_recipe_catalog != null)
	assert(inventory_model == null)
	inventory_model = p_inventory_model
	recipe_catalog = p_recipe_catalog
	inventory_model.inventory_changed.connect(_on_inventory_changed)

func can_craft(recipe_id: StringName) -> bool:
	if not recipe_catalog.has_definition(recipe_id):
		return false
	var recipe := recipe_catalog.get_definition(recipe_id)
	return inventory_model.can_exchange_inventory_items(recipe.get_ingredient_counts(), recipe.get_output_counts())

func start(recipe_id: StringName) -> bool:
	if is_crafting() or not can_craft(recipe_id):
		return false
	_active_recipe_id = recipe_id
	_elapsed_seconds = 0.0
	state_changed.emit()
	return true

func advance_time(delta: float) -> bool:
	assert(delta >= 0.0)
	if not is_crafting():
		return false
	if not can_craft(_active_recipe_id):
		cancel()
		return false
	var recipe := recipe_catalog.get_definition(_active_recipe_id)
	_elapsed_seconds = minf(_elapsed_seconds + delta, recipe.duration_seconds)
	if _elapsed_seconds < recipe.duration_seconds:
		return false
	var ingredient_counts := recipe.get_ingredient_counts()
	var output_counts := recipe.get_output_counts()
	_active_recipe_id = &""
	_elapsed_seconds = 0.0
	var crafted := inventory_model.exchange_inventory_items(ingredient_counts, output_counts)
	assert(crafted)
	return true

func cancel() -> bool:
	if not is_crafting():
		return false
	_active_recipe_id = &""
	_elapsed_seconds = 0.0
	state_changed.emit()
	return true

func is_crafting() -> bool:
	return not _active_recipe_id.is_empty()

func get_active_recipe_id() -> StringName:
	return _active_recipe_id

func get_progress() -> float:
	if not is_crafting():
		return 0.0
	var recipe := recipe_catalog.get_definition(_active_recipe_id)
	return clampf(_elapsed_seconds / recipe.duration_seconds, 0.0, 1.0)

func _on_inventory_changed() -> void:
	if is_crafting() and not can_craft(_active_recipe_id):
		cancel()
		return
	state_changed.emit()
