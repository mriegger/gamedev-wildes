extends RefCounted
class_name ItemProficiency

signal progress_changed(item_id: StringName)

var _item_catalog: ItemCatalog
var _progress_by_item_id: Dictionary = {}

func _init(item_catalog: ItemCatalog):
	assert(item_catalog != null)
	_item_catalog = item_catalog
	for item_definition in _item_catalog.definitions:
		if item_definition == null or item_definition.proficiency == null:
			continue
		assert(not item_definition.id.is_empty())
		assert(item_definition.proficiency.validate())

func has_proficiency(item_id: StringName) -> bool:
	return (
		not item_id.is_empty()
		and _item_catalog.has_definition(item_id)
		and _item_catalog.get_definition(item_id).proficiency != null
	)

func is_for_catalog(item_catalog: ItemCatalog) -> bool:
	return _item_catalog == item_catalog

func add_experience(item_id: StringName, amount: float) -> int:
	assert(has_proficiency(item_id))
	assert(is_finite(amount) and amount >= 0.0)
	var definition := _get_definition(item_id)
	var level := get_level(item_id)
	if amount == 0.0 or level == definition.maximum_level:
		return 0
	var experience := get_experience(item_id)
	var remaining := amount
	var levels_gained := 0
	while level < definition.maximum_level:
		var required := definition.get_experience_requirement(level)
		var needed := required - experience
		if remaining < needed:
			experience += remaining
			remaining = 0.0
			break
		remaining -= needed
		level += 1
		levels_gained += 1
		experience = 0.0
		if remaining == 0.0:
			break
	if level == definition.maximum_level:
		experience = 0.0
	_commit_progress(item_id, level, experience)
	return levels_gained

func get_level(item_id: StringName) -> int:
	assert(has_proficiency(item_id))
	return int(_get_progress(item_id).get("level", 0))

func get_experience(item_id: StringName) -> float:
	assert(has_proficiency(item_id))
	return float(_get_progress(item_id).get("experience", 0.0))

func get_experience_to_next_level(item_id: StringName) -> float:
	assert(has_proficiency(item_id))
	var definition := _get_definition(item_id)
	var level := get_level(item_id)
	if level == definition.maximum_level:
		return 0.0
	return definition.get_experience_requirement(level)

func is_at_maximum_level(item_id: StringName) -> bool:
	assert(has_proficiency(item_id))
	return get_level(item_id) == _get_definition(item_id).maximum_level

func get_unlocked_slot_count(item_id: StringName) -> int:
	assert(has_proficiency(item_id))
	return _get_definition(item_id).get_unlocked_slot_count(get_level(item_id))

func snapshot() -> Dictionary:
	var result: Dictionary = {}
	var item_ids: Array[String] = []
	for item_id in _progress_by_item_id:
		item_ids.append(String(item_id))
	item_ids.sort()
	for item_id in item_ids:
		var progress := _progress_by_item_id[StringName(item_id)] as Dictionary
		result[item_id] = {
			"level": int(progress["level"]),
			"experience": float(progress["experience"]),
		}
	return result

func restore(saved_progress: Dictionary) -> bool:
	var restored_progress: Dictionary = {}
	for raw_item_id in saved_progress:
		if typeof(raw_item_id) != TYPE_STRING and typeof(raw_item_id) != TYPE_STRING_NAME:
			return false
		var item_id := StringName(raw_item_id)
		if not has_proficiency(item_id) or restored_progress.has(item_id):
			return false
		var raw_progress = saved_progress[raw_item_id]
		if typeof(raw_progress) != TYPE_DICTIONARY:
			return false
		var progress := raw_progress as Dictionary
		if progress.size() != 2 or not progress.has("level") or not progress.has("experience"):
			return false
		var raw_level = progress["level"]
		if typeof(raw_level) != TYPE_INT and typeof(raw_level) != TYPE_FLOAT:
			return false
		var numeric_level := float(raw_level)
		var definition := _get_definition(item_id)
		if (
			not is_finite(numeric_level)
			or numeric_level != floor(numeric_level)
			or numeric_level < 0.0
			or numeric_level > definition.maximum_level
		):
			return false
		var level := int(numeric_level)
		var raw_experience = progress["experience"]
		if typeof(raw_experience) != TYPE_INT and typeof(raw_experience) != TYPE_FLOAT:
			return false
		var experience := float(raw_experience)
		if not _is_valid_progress(item_id, level, experience):
			return false
		if level > 0 or experience > 0.0:
			restored_progress[item_id] = {
				"level": level,
				"experience": experience,
			}
	_progress_by_item_id = restored_progress
	return true

func _get_definition(item_id: StringName) -> ProficiencyDefinition:
	return _item_catalog.get_definition(item_id).proficiency

func _get_progress(item_id: StringName) -> Dictionary:
	return _progress_by_item_id.get(item_id, {}) as Dictionary

func _commit_progress(item_id: StringName, level: int, experience: float) -> void:
	assert(_is_valid_progress(item_id, level, experience))
	if level == 0 and experience == 0.0:
		_progress_by_item_id.erase(item_id)
	else:
		_progress_by_item_id[item_id] = {
			"level": level,
			"experience": experience,
		}
	progress_changed.emit(item_id)

func _is_valid_progress(item_id: StringName, level: int, experience: float) -> bool:
	if not is_finite(experience) or experience < 0.0:
		return false
	var definition := _get_definition(item_id)
	if level < 0 or level > definition.maximum_level:
		return false
	if level == definition.maximum_level:
		return experience == 0.0
	return experience < definition.get_experience_requirement(level)
