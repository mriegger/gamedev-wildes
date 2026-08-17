extends RefCounted
class_name DevConsoleCommandProcessor

enum ExecutionResult {
	REJECTED,
	KEEP_OPEN,
	CLOSE,
}

const ITEM_ALIASES: Dictionary[StringName, StringName] = {
	&"torches": &"torch",
}

var inventory_model: InventoryModel
var _new_structure: Callable
var _exit_structure: Callable

func setup(
	p_inventory_model: InventoryModel,
	p_new_structure: Callable,
	p_exit_structure: Callable,
) -> void:
	assert(p_inventory_model != null)
	assert(inventory_model == null)
	assert(p_new_structure.is_valid())
	assert(p_exit_structure.is_valid())
	inventory_model = p_inventory_model
	_new_structure = p_new_structure
	_exit_structure = p_exit_structure

func execute(command_line: String) -> ExecutionResult:
	if inventory_model == null:
		return ExecutionResult.REJECTED
	var tokens := command_line.strip_edges().split(" ", false)
	if tokens.is_empty():
		return ExecutionResult.REJECTED
	var command := tokens[0].to_lower()
	if command == "spawn":
		return _execute_spawn(tokens)
	if command == "dev":
		return _execute_dev(tokens)
	return ExecutionResult.REJECTED

func _execute_spawn(tokens: PackedStringArray) -> ExecutionResult:
	if tokens.size() < 3:
		return ExecutionResult.REJECTED
	var count_token := tokens[tokens.size() - 1]
	if not count_token.is_valid_int():
		return ExecutionResult.REJECTED
	var count := int(count_token)
	if count < 1:
		return ExecutionResult.REJECTED
	var item_name_parts := PackedStringArray()
	for index in range(1, tokens.size() - 1):
		item_name_parts.append(tokens[index])
	var item_id := _resolve_item_id(" ".join(item_name_parts))
	if item_id.is_empty():
		return ExecutionResult.REJECTED
	if not inventory_model.add_backpack_item(item_id, count):
		return ExecutionResult.REJECTED
	return ExecutionResult.KEEP_OPEN

func _execute_dev(tokens: PackedStringArray) -> ExecutionResult:
	if tokens.size() != 3 or tokens[1].to_lower() != "structure":
		return ExecutionResult.REJECTED
	var action := tokens[2].to_lower()
	if action == "new":
		return _execute_structure_action(_new_structure)
	if action == "exit":
		return _execute_structure_action(_exit_structure)
	return ExecutionResult.REJECTED

func _execute_structure_action(action: Callable) -> ExecutionResult:
	return ExecutionResult.CLOSE if bool(action.call()) else ExecutionResult.REJECTED

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
