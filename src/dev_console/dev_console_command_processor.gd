extends RefCounted
class_name DevConsoleCommandProcessor

const ITEM_ALIASES: Dictionary[StringName, StringName] = {
	&"torches": &"torch",
}

var inventory_model: InventoryModel
var pumpkin_patch_preview: PumpkinPatchPreview

func setup(p_inventory_model: InventoryModel, p_pumpkin_patch_preview: PumpkinPatchPreview) -> void:
	assert(p_inventory_model != null and p_pumpkin_patch_preview != null)
	assert(inventory_model == null and pumpkin_patch_preview == null)
	inventory_model = p_inventory_model
	pumpkin_patch_preview = p_pumpkin_patch_preview

func execute(command_line: String) -> bool:
	if inventory_model == null or pumpkin_patch_preview == null:
		return false
	var tokens := command_line.strip_edges().split(" ", false)
	if tokens.size() < 2 or tokens[0].to_lower() != "spawn":
		return false
	if tokens.size() == 2 and _normalize_item_name(tokens[1]) == &"pumpkin_patch":
		return pumpkin_patch_preview.spawn_patch()
	if tokens.size() < 3:
		return false
	var count_token := tokens[tokens.size() - 1]
	if not count_token.is_valid_int():
		return false
	var count := int(count_token)
	if count < 1:
		return false
	var item_name_parts := PackedStringArray()
	for index in range(1, tokens.size() - 1):
		item_name_parts.append(tokens[index])
	var item_id := _resolve_item_id(" ".join(item_name_parts))
	if item_id.is_empty():
		return false
	return inventory_model.add_backpack_item(item_id, count)

func _resolve_item_id(item_name: String) -> StringName:
	var normalized_name := _normalize_item_name(item_name)
	if ITEM_ALIASES.has(normalized_name):
		return ITEM_ALIASES[normalized_name]
	if inventory_model.item_catalog.has_definition(normalized_name):
		return normalized_name
	for definition in inventory_model.item_catalog.definitions:
		if _normalize_item_name(definition.display_name) == normalized_name:
			return definition.id
	return &""

func _normalize_item_name(item_name: String) -> StringName:
	return StringName(item_name.strip_edges().to_lower().replace("-", "_").replace(" ", "_"))
