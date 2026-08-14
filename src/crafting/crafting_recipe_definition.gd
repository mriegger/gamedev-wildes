extends Resource
class_name CraftingRecipeDefinition

@export var id: StringName
@export var output_item: ItemDefinition
@export_range(1, 99) var output_count: int = 1
@export var ingredients: Array[CraftingIngredient]

func validate(item_catalog: ItemCatalog, source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[CraftingRecipeDefinition] Empty recipe ID at %s" % source)
		valid = false
	if output_item == null:
		push_error("[CraftingRecipeDefinition] Missing output at %s" % source)
		valid = false
	elif not item_catalog.has_definition(output_item.id) or item_catalog.get_definition(output_item.id) != output_item:
		push_error("[CraftingRecipeDefinition] Non-canonical output %s at %s" % [output_item.id, source])
		valid = false
	if output_count < 1:
		push_error("[CraftingRecipeDefinition] Invalid output count at %s" % source)
		valid = false
	if ingredients.is_empty():
		push_error("[CraftingRecipeDefinition] Missing ingredients at %s" % source)
		valid = false
	var ingredient_ids: Dictionary = {}
	for ingredient_index in range(ingredients.size()):
		var ingredient := ingredients[ingredient_index]
		if ingredient == null:
			push_error("[CraftingRecipeDefinition] Missing ingredient %d at %s" % [ingredient_index, source])
			valid = false
			continue
		valid = ingredient.validate(item_catalog, "%s ingredient %d" % [source, ingredient_index]) and valid
		if ingredient.item == null:
			continue
		if ingredient_ids.has(ingredient.item.id):
			push_error("[CraftingRecipeDefinition] Duplicate ingredient %s at %s" % [ingredient.item.id, source])
			valid = false
		ingredient_ids[ingredient.item.id] = true
	return valid

func get_ingredient_counts() -> Dictionary[StringName, int]:
	var counts: Dictionary[StringName, int] = {}
	for ingredient in ingredients:
		counts[ingredient.item.id] = ingredient.count
	return counts

func get_output_counts() -> Dictionary[StringName, int]:
	return {output_item.id: output_count}
