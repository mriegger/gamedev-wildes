extends Resource
class_name LootBundleDefinition

@export var id: StringName
@export_range(1, 999, 1, "or_greater") var max_rewards: int = 1
@export var fixed_entries: Array[LootBundleEntryDefinition]
@export var weighted_candidates: Array[LootWeightedChoiceDefinition]

func validate() -> bool:
	var valid := true
	var source := resource_path
	if source.is_empty():
		source = String(id)
	if id.is_empty():
		push_error("[LootBundleDefinition] Empty bundle ID at %s" % source)
		valid = false
	if max_rewards < 1:
		push_error("[LootBundleDefinition] Invalid maximum reward count for %s at %s" % [id, source])
		valid = false
	if fixed_entries.is_empty() and weighted_candidates.is_empty():
		push_error("[LootBundleDefinition] Missing entries for %s at %s" % [id, source])
		valid = false
	if fixed_entries.size() > max_rewards:
		push_error("[LootBundleDefinition] Fixed entries exceed maximum rewards for %s at %s" % [id, source])
		valid = false
	if max_rewards > fixed_entries.size() + weighted_candidates.size():
		push_error("[LootBundleDefinition] Maximum rewards are unreachable for %s at %s" % [id, source])
		valid = false
	if fixed_entries.size() == max_rewards and not weighted_candidates.is_empty():
		push_error("[LootBundleDefinition] Unreachable weighted candidates for %s at %s" % [id, source])
		valid = false
	var entry_ids: Dictionary = {}
	for entry_index in range(fixed_entries.size()):
		var entry := fixed_entries[entry_index]
		var entry_source := "%s fixed entry %d" % [source, entry_index]
		if entry == null:
			push_error("[LootBundleDefinition] Missing fixed entry %d for %s at %s" % [entry_index, id, source])
			valid = false
			continue
		valid = entry.validate(entry_source) and valid
		valid = _record_entry_id(entry.id, entry_ids, source) and valid
	var weight_total := 0.0
	for candidate_index in range(weighted_candidates.size()):
		var candidate := weighted_candidates[candidate_index]
		var candidate_source := "%s weighted candidate %d" % [source, candidate_index]
		if candidate == null:
			push_error("[LootBundleDefinition] Missing weighted candidate %d for %s at %s" % [candidate_index, id, source])
			valid = false
			continue
		valid = candidate.validate(candidate_source) and valid
		valid = _record_entry_id(candidate.id, entry_ids, source) and valid
		weight_total += candidate.weight
	if not is_finite(weight_total):
		push_error("[LootBundleDefinition] Candidate weight total is not finite for %s at %s" % [id, source])
		valid = false
	return valid

func _record_entry_id(entry_id: StringName, entry_ids: Dictionary, source: String) -> bool:
	if entry_ids.has(entry_id):
		push_error("[LootBundleDefinition] Duplicate entry ID %s for %s at %s" % [entry_id, id, source])
		return false
	entry_ids[entry_id] = true
	return true
