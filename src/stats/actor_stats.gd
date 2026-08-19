extends RefCounted
class_name ActorStats

signal health_depleted
signal health_changed(current_hp: float, maximum_hp: float)

var level: int
var experience: int
var current_hp: float:
	get:
		return _current_hp

var _definition: ActorStatsDefinition
var _base_values: Dictionary
var _modifiers: Dictionary = {}
var _remaining_duration: Dictionary = {}
var _current_hp: float

func _init(definition: ActorStatsDefinition):
	_definition = definition
	_base_values = definition.get_base_stats().duplicate()
	level = definition.starting_level
	experience = definition.starting_experience
	_current_hp = get_value(&"hp") if definition.has_stat(&"hp") else 0.0

func has_stat(stat_id: StringName) -> bool:
	return _base_values.has(stat_id)

func get_stat_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for stat_id in _base_values:
		ids.append(stat_id)
	ids.sort()
	return ids

func get_base_value(stat_id: StringName) -> float:
	assert(has_stat(stat_id))
	return float(_base_values[stat_id])

func set_base_value(stat_id: StringName, value: float) -> bool:
	if not has_stat(stat_id) or not _is_valid_stat_value(stat_id, value):
		return false
	var previous: float = float(_base_values[stat_id])
	_base_values[stat_id] = value
	if not _has_valid_modifier_values(_modifiers):
		_base_values[stat_id] = previous
		return false
	_clamp_current_hp()
	return true

func set_current_hp(value: float) -> bool:
	if not has_stat(&"hp") or not is_finite(value) or value < 0.0 or value > get_value(&"hp"):
		return false
	_commit_current_hp(value)
	return true

func is_dead() -> bool:
	return has_stat(&"hp") and current_hp <= 0.0

func set_progression(p_level: int, p_experience: int) -> bool:
	return restore_progression({"level": p_level, "experience": p_experience, "current_hp": current_hp})

func get_value(stat_id: StringName) -> float:
	assert(has_stat(stat_id))
	return _get_value(stat_id)

func _get_value(stat_id: StringName) -> float:
	return _get_value_with_modifiers(stat_id, _modifiers)

func _get_value_with_modifiers(stat_id: StringName, modifiers: Dictionary) -> float:
	var additive := 0.0
	var multiplier := 1.0
	var modifier_ids := modifiers.keys()
	modifier_ids.sort()
	for modifier_id in modifier_ids:
		var modifier := modifiers[modifier_id] as StatModifier
		if modifier.stat_id != stat_id:
			continue
		if modifier.operation == StatModifier.Operation.ADD:
			additive += modifier.amount
		else:
			multiplier *= modifier.amount
	return (float(_base_values[stat_id]) + additive) * multiplier

func add_experience(amount: int) -> int:
	assert(amount >= 0)
	if is_at_maximum_level():
		return 0
	var remaining := amount
	var levels_gained := 0
	while remaining > 0 and not is_at_maximum_level():
		var required := get_experience_to_next_level()
		var needed := required - experience
		if remaining < needed:
			experience += remaining
			break
		remaining -= needed
		experience = 0
		level += 1
		levels_gained += 1
	if is_at_maximum_level():
		experience = 0
	return levels_gained

func get_total_experience() -> int:
	var total := experience
	for completed_level in range(1, level):
		total += _definition.get_experience_requirement(completed_level)
	return total

func get_experience_to_next_level() -> int:
	if is_at_maximum_level():
		return 0
	return _definition.get_experience_requirement(level)

func is_at_maximum_level() -> bool:
	return _definition.maximum_level > 0 and level >= _definition.maximum_level

func damage(amount: float) -> float:
	assert(is_finite(amount) and amount >= 0.0)
	assert(has_stat(&"hp"))
	var previous := current_hp
	var next := maxf(0.0, current_hp - amount)
	var applied := previous - next
	_commit_current_hp(next)
	return applied

func heal(amount: float) -> float:
	assert(is_finite(amount) and amount >= 0.0)
	assert(has_stat(&"hp"))
	var previous := current_hp
	var next := minf(get_value(&"hp"), current_hp + amount)
	var applied := next - previous
	_commit_current_hp(next)
	return applied

func add_modifier(modifier: StatModifier) -> bool:
	if modifier == null or _modifiers.has(modifier.id):
		return false
	var runtime_modifier := modifier.duplicate() as StatModifier
	if runtime_modifier == null or not runtime_modifier.is_valid(_definition):
		return false
	var projected := _modifiers.duplicate()
	projected[runtime_modifier.id] = runtime_modifier
	if not _has_valid_modifier_values(projected):
		return false
	_modifiers[runtime_modifier.id] = runtime_modifier
	if runtime_modifier.duration_seconds > 0.0:
		_remaining_duration[runtime_modifier.id] = runtime_modifier.duration_seconds
	_clamp_current_hp()
	return true

func can_replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	var runtime_modifiers: Array[StatModifier] = []
	return _prepare_source_modifiers(source_id, source_instance_id, modifiers, runtime_modifiers)

func replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	return _replace_source_modifiers(source_id, source_instance_id, modifiers, false)

func replace_source_modifiers_preserving_health_ratio(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	return _replace_source_modifiers(source_id, source_instance_id, modifiers, true)

func _replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier], preserve_health_ratio: bool) -> bool:
	var runtime_modifiers: Array[StatModifier] = []
	if not _prepare_source_modifiers(source_id, source_instance_id, modifiers, runtime_modifiers):
		return false
	var previous_maximum_hp := get_value(&"hp") if preserve_health_ratio and has_stat(&"hp") else 0.0
	var previous_health_ratio := current_hp / previous_maximum_hp if previous_maximum_hp > 0.0 else 0.0
	_erase_modifiers_from_source_instance(source_instance_id)
	for modifier in runtime_modifiers:
		_modifiers[modifier.id] = modifier
		if modifier.duration_seconds > 0.0:
			_remaining_duration[modifier.id] = modifier.duration_seconds
	var next_maximum_hp := get_value(&"hp") if preserve_health_ratio and has_stat(&"hp") else 0.0
	if preserve_health_ratio and previous_maximum_hp != next_maximum_hp:
		_commit_current_hp(clampf(previous_health_ratio * next_maximum_hp, 0.0, next_maximum_hp))
	else:
		_clamp_current_hp()
	return true

func _prepare_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier], runtime_modifiers: Array[StatModifier]) -> bool:
	if source_id.is_empty() or source_instance_id.is_empty():
		return false
	for index in range(modifiers.size()):
		if modifiers[index] == null:
			return false
		var modifier := modifiers[index].duplicate() as StatModifier
		modifier.id = StringName("%s_%d" % [source_instance_id, index])
		modifier.source_id = source_id
		modifier.source_instance_id = source_instance_id
		if not modifier.is_valid(_definition):
			return false
		runtime_modifiers.append(modifier)
	var projected := _modifiers.duplicate()
	for modifier_id in projected.keys():
		var existing := projected[modifier_id] as StatModifier
		if existing.source_instance_id == source_instance_id:
			projected.erase(modifier_id)
	for modifier in runtime_modifiers:
		projected[modifier.id] = modifier
	return _has_valid_modifier_values(projected)

func remove_modifier(modifier_id: StringName) -> bool:
	if not _modifiers.has(modifier_id):
		return false
	var projected := _modifiers.duplicate()
	projected.erase(modifier_id)
	if not _has_valid_modifier_values(projected):
		return false
	_modifiers.erase(modifier_id)
	_remaining_duration.erase(modifier_id)
	_clamp_current_hp()
	return true

func remove_modifiers_from_source_instance(source_instance_id: StringName) -> int:
	if source_instance_id.is_empty():
		return 0
	var projected := _modifiers.duplicate()
	for modifier_id in projected.keys():
		var modifier := projected[modifier_id] as StatModifier
		if modifier.source_instance_id == source_instance_id:
			projected.erase(modifier_id)
	if not _has_valid_modifier_values(projected):
		return 0
	var removed := _erase_modifiers_from_source_instance(source_instance_id)
	if removed > 0:
		_clamp_current_hp()
	return removed

func _erase_modifiers_from_source_instance(source_instance_id: StringName) -> int:
	var removed := 0
	for modifier_id in _modifiers.keys():
		var modifier := _modifiers[modifier_id] as StatModifier
		if modifier.source_instance_id != source_instance_id:
			continue
		_modifiers.erase(modifier_id)
		_remaining_duration.erase(modifier_id)
		removed += 1
	return removed

func has_modifier(modifier_id: StringName) -> bool:
	return _modifiers.has(modifier_id)

func advance_time(delta: float) -> void:
	assert(delta >= 0.0)
	var expired: Array[StringName] = []
	for modifier_id in _remaining_duration:
		var remaining := float(_remaining_duration[modifier_id]) - delta
		if remaining <= 0.0:
			expired.append(modifier_id)
		else:
			_remaining_duration[modifier_id] = remaining
	for modifier_id in expired:
		remove_modifier(modifier_id)

func snapshot_progression() -> Dictionary:
	return {
		"level": level,
		"experience": experience,
		"current_hp": current_hp,
	}

func restore_progression(snapshot: Dictionary) -> bool:
	var restored_level := int(snapshot.get("level", 0))
	var restored_experience := int(snapshot.get("experience", -1))
	if restored_level < 1 or restored_experience < 0:
		return false
	if _definition.maximum_level > 0 and restored_level > _definition.maximum_level:
		return false
	if _definition.maximum_level > 0 and restored_level == _definition.maximum_level and restored_experience != 0:
		return false
	if (_definition.maximum_level == 0 or restored_level < _definition.maximum_level) and restored_experience >= _definition.get_experience_requirement(restored_level):
		return false
	var maximum_hp := get_value(&"hp") if has_stat(&"hp") else 0.0
	var restored_hp := float(snapshot.get("current_hp", maximum_hp))
	if not is_finite(restored_hp) or restored_hp < 0.0:
		return false
	level = restored_level
	experience = restored_experience
	_commit_current_hp(minf(restored_hp, maximum_hp))
	return true

func _clamp_current_hp():
	if has_stat(&"hp"):
		_commit_current_hp(minf(current_hp, get_value(&"hp")))

func _commit_current_hp(value: float):
	assert(is_finite(value) and value >= 0.0)
	var was_alive := has_stat(&"hp") and _current_hp > 0.0
	_current_hp = value
	if has_stat(&"hp"):
		health_changed.emit(_current_hp, get_value(&"hp"))
	if was_alive and _current_hp <= 0.0:
		health_depleted.emit()

func _has_valid_modifier_values(modifiers: Dictionary) -> bool:
	for stat_id in _base_values:
		if not _is_valid_stat_value(stat_id, _get_value_with_modifiers(stat_id, modifiers)):
			return false
		var minimum_additive_value := float(_base_values[stat_id])
		var maximum_additive_value := float(_base_values[stat_id])
		var minimum_multiplier := 1.0
		var maximum_multiplier := 1.0
		for modifier in modifiers.values():
			var stat_modifier := modifier as StatModifier
			if stat_modifier.stat_id != stat_id:
				continue
			if stat_modifier.operation == StatModifier.Operation.ADD:
				minimum_additive_value += minf(stat_modifier.amount, 0.0)
				maximum_additive_value += maxf(stat_modifier.amount, 0.0)
			else:
				minimum_multiplier *= minf(stat_modifier.amount, 1.0)
				maximum_multiplier *= maxf(stat_modifier.amount, 1.0)
		if not _is_valid_stat_value(stat_id, minimum_additive_value):
			return false
		if not _is_valid_stat_value(stat_id, minimum_additive_value * minimum_multiplier):
			return false
		if not _is_valid_stat_value(stat_id, maximum_additive_value * maximum_multiplier):
			return false
	return true

func _is_valid_stat_value(stat_id: StringName, value: float) -> bool:
	return is_finite(value) and value >= 0.0 and (stat_id != &"hp" or value > 0.0)
