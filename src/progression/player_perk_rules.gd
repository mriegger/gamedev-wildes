extends Resource
class_name PlayerPerkRules

@export_range(1, 999, 1, "or_greater") var first_award_level: int = 2
@export_range(1, 999, 1, "or_greater") var levels_per_award: int = 1
@export_range(1, 999, 1, "or_greater") var points_per_award: int = 1
@export var definitions: Array[PlayerPerkDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary = {}
var _catalog_is_valid: bool = false

func validate(stats_definition: ActorStatsDefinition) -> bool:
	_ensure_lookup()
	if (
		not _catalog_is_valid
		or first_award_level < 1
		or levels_per_award < 1
		or points_per_award < 1
	):
		return false
	var maximum_amount_by_stat: Dictionary = {}
	for definition in definitions:
		if not definition.validate(stats_definition):
			return false
		var maximum_amount := float(maximum_amount_by_stat.get(definition.stat_id, 0.0)) + definition.get_amount(definition.maximum_rank)
		if not is_finite(maximum_amount):
			return false
		maximum_amount_by_stat[definition.stat_id] = maximum_amount
	return true

func has_definition(perk_id: StringName) -> bool:
	_ensure_lookup()
	return not perk_id.is_empty() and _definitions_by_id.has(perk_id)

func get_definition(perk_id: StringName) -> PlayerPerkDefinition:
	_ensure_lookup()
	assert(_definitions_by_id.has(perk_id))
	return _definitions_by_id[perk_id] as PlayerPerkDefinition

func get_definitions() -> Array[PlayerPerkDefinition]:
	return definitions.duplicate()

func get_perk_ids() -> Array[StringName]:
	_ensure_lookup()
	var sorted_ids: Array[String] = []
	for perk_id in _definitions_by_id:
		sorted_ids.append(String(perk_id))
	sorted_ids.sort()
	var perk_ids: Array[StringName] = []
	for perk_id in sorted_ids:
		perk_ids.append(StringName(perk_id))
	return perk_ids

func get_earned_point_count(player_level: int) -> int:
	assert(player_level >= 1)
	if player_level < first_award_level:
		return 0
	var award_count := floori(float(player_level - first_award_level) / levels_per_award) + 1
	return award_count * points_per_award

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_catalog_is_valid = not definitions.is_empty()
	for definition in definitions:
		if definition == null or definition.id.is_empty() or _definitions_by_id.has(definition.id):
			_catalog_is_valid = false
			continue
		_definitions_by_id[definition.id] = definition

func _ensure_lookup() -> void:
	if _definitions_by_id.size() != definitions.size():
		_rebuild_lookup()
