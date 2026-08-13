extends RefCounted
class_name PlayerPerks

var _rules: PlayerPerkRules
var _allocations: Dictionary = {}

func _init(rules: PlayerPerkRules):
	assert(rules != null)
	_rules = rules

func get_rules() -> PlayerPerkRules:
	return _rules

func get_definitions() -> Array[PlayerPerkDefinition]:
	return _rules.get_definitions()

func get_perk_ids() -> Array[StringName]:
	return _rules.get_perk_ids()

func get_definition(perk_id: StringName) -> PlayerPerkDefinition:
	return _rules.get_definition(perk_id)

func get_rank(perk_id: StringName) -> int:
	assert(_rules.has_definition(perk_id))
	return int(_allocations.get(perk_id, 0))

func get_earned_point_count(player_level: int) -> int:
	return _rules.get_earned_point_count(player_level)

func get_spent_point_count() -> int:
	var spent := 0
	for rank in _allocations.values():
		spent += int(rank)
	return spent

func get_unspent_point_count(player_level: int) -> int:
	assert(player_level >= 1)
	return _rules.get_earned_point_count(player_level) - get_spent_point_count()

func can_allocate(perk_id: StringName, player_level: int) -> bool:
	return _can_allocate(perk_id, player_level)

func try_allocate(perk_id: StringName, player_level: int) -> bool:
	if not _can_allocate(perk_id, player_level):
		return false
	_allocations[perk_id] = get_rank(perk_id) + 1
	return true

func snapshot() -> Dictionary:
	var saved_allocations: Dictionary = {}
	for perk_id in _rules.get_perk_ids():
		var rank := int(_allocations.get(perk_id, 0))
		if rank > 0:
			saved_allocations[String(perk_id)] = rank
	return {"allocations": saved_allocations}

func restore(saved_state: Dictionary, player_level: int) -> bool:
	if player_level < 1 or saved_state.size() != 1 or not saved_state.has("allocations"):
		return false
	var raw_allocations = saved_state["allocations"]
	if typeof(raw_allocations) != TYPE_DICTIONARY:
		return false
	var restored_allocations: Dictionary = {}
	var spent := 0
	for raw_perk_id in raw_allocations:
		if typeof(raw_perk_id) != TYPE_STRING and typeof(raw_perk_id) != TYPE_STRING_NAME:
			return false
		var perk_id := StringName(raw_perk_id)
		if not _rules.has_definition(perk_id) or restored_allocations.has(perk_id):
			return false
		var rank := _parse_rank(raw_allocations[raw_perk_id], _rules.get_definition(perk_id).maximum_rank)
		if rank < 1:
			return false
		restored_allocations[perk_id] = rank
		spent += rank
	if spent > _rules.get_earned_point_count(player_level):
		return false
	_allocations = restored_allocations
	return true

func _can_allocate(perk_id: StringName, player_level: int) -> bool:
	if player_level < 1 or not _rules.has_definition(perk_id):
		return false
	return (
		get_rank(perk_id) < _rules.get_definition(perk_id).maximum_rank
		and get_unspent_point_count(player_level) > 0
	)

func _parse_rank(raw_rank: Variant, maximum_rank: int) -> int:
	if typeof(raw_rank) != TYPE_INT and typeof(raw_rank) != TYPE_FLOAT:
		return -1
	var numeric_rank := float(raw_rank)
	if (
		not is_finite(numeric_rank)
		or numeric_rank != floor(numeric_rank)
		or numeric_rank < 1.0
		or numeric_rank > maximum_rank
	):
		return -1
	return int(numeric_rank)
