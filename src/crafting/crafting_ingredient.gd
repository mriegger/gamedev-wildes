extends Resource
class_name CraftingIngredient

@export var item: ItemDefinition
@export_range(1, 999) var count: int = 1

func validate(item_catalog: ItemCatalog, source: String) -> bool:
	if item == null:
		push_error("[CraftingIngredient] Missing item at %s" % source)
		return false
	if count < 1:
		push_error("[CraftingIngredient] Invalid count for %s at %s" % [item.id, source])
		return false
	if not item_catalog.has_definition(item.id) or item_catalog.get_definition(item.id) != item:
		push_error("[CraftingIngredient] Non-canonical item %s at %s" % [item.id, source])
		return false
	return true
