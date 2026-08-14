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
const MAXIMUM_GIVE_XP_AMOUNT: int = 999_999_999

var inventory_model: InventoryModel
var actor_stats: ActorStats
var pumpkin_patch: PumpkinPatchCoordinator
var _new_structure: Callable
var _import_structure: Callable
var _export_structure: Callable
var _exit_structure: Callable

func setup(
	p_inventory_model: InventoryModel,
	p_actor_stats: ActorStats,
	p_pumpkin_patch: PumpkinPatchCoordinator,
	p_new_structure: Callable,
	p_import_structure: Callable,
	p_export_structure: Callable,
	p_exit_structure: Callable,
) -> void:
	assert(p_inventory_model != null and p_actor_stats != null and p_pumpkin_patch != null)
	assert(inventory_model == null and actor_stats == null and pumpkin_patch == null)
	assert(p_new_structure.is_valid())
	assert(p_import_structure.is_valid())
	assert(p_export_structure.is_valid())
	assert(p_exit_structure.is_valid())
	inventory_model = p_inventory_model
	actor_stats = p_actor_stats
	pumpkin_patch = p_pumpkin_patch
	_new_structure = p_new_structure
	_import_structure = p_import_structure
	_export_structure = p_export_structure
	_exit_structure = p_exit_structure

func execute(command_line: String) -> ExecutionResult:
	if inventory_model == null or actor_stats == null or pumpkin_patch == null:
		return ExecutionResult.REJECTED
	var tokens := command_line.strip_edges().split(" ", false)
	if tokens.is_empty():
		return ExecutionResult.REJECTED
	var command := tokens[0].to_lower()
	if command == "spawn":
		return _execute_spawn(tokens)
	if command == "give_xp":
		return _execute_give_xp(tokens)
	if command == "dev":
		return _execute_dev(tokens)
	return ExecutionResult.REJECTED

func _execute_spawn(tokens: PackedStringArray) -> ExecutionResult:
	if tokens.size() == 2 and _normalize_item_name(tokens[1]) == &"pumpkin_patch":
		return ExecutionResult.KEEP_OPEN if pumpkin_patch.spawn_patch() else ExecutionResult.REJECTED
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

func _execute_give_xp(tokens: PackedStringArray) -> ExecutionResult:
	if tokens.size() != 2:
		return ExecutionResult.REJECTED
	var amount := _parse_give_xp_amount(tokens[1])
	if amount < 1 or actor_stats.is_at_maximum_level():
		return ExecutionResult.REJECTED
	actor_stats.add_experience(amount)
	return ExecutionResult.KEEP_OPEN

func _execute_dev(tokens: PackedStringArray) -> ExecutionResult:
	if tokens.size() != 3 or tokens[1].to_lower() != "structure":
		return ExecutionResult.REJECTED
	var action := tokens[2].to_lower()
	if action == "new":
		return _execute_structure_action(_new_structure)
	if action == "import":
		return _execute_structure_action(_import_structure)
	if action == "export":
		return _execute_structure_action(_export_structure)
	if action == "exit":
		return _execute_structure_action(_exit_structure)
	return ExecutionResult.REJECTED

func _execute_structure_action(action: Callable) -> ExecutionResult:
	return ExecutionResult.CLOSE if bool(action.call()) else ExecutionResult.REJECTED

func _parse_give_xp_amount(token: String) -> int:
	if token.is_empty():
		return 0
	var first_digit := 1 if token.unicode_at(0) == 43 else 0
	if first_digit == token.length():
		return 0
	var amount := 0
	for index in range(first_digit, token.length()):
		var character := token.unicode_at(index)
		if character < 48 or character > 57:
			return 0
		amount = amount * 10 + character - 48
		if amount > MAXIMUM_GIVE_XP_AMOUNT:
			return 0
	return amount

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
