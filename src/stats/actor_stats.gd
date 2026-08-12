extends RefCounted
class_name ActorStats

var level: int
var experience: int
var current_hp: float

var _definition: ActorStatsDefinition
var _base_values: Dictionary
var _modifiers: Dictionary = {}
var _remaining_duration: Dictionary = {}

func _init(definition: ActorStatsDefinition):
	_definition = definition
	_base_values = definition.get_base_stats().duplicate()
	level = definition.starting_level
	experience = definition.starting_experience
	current_hp = get_value(&"hp") if definition.has_stat(&"hp") else 0.0

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
	if not has_stat(stat_id) or value < 0.0:
		return false
	_base_values[stat_id] = value
	_clamp_current_hp()
	return true

func set_current_hp(value: float) -> bool:
	if not has_stat(&"hp") or value < 0.0 or value > get_value(&"hp"):
		return false
	current_hp = value
	return true

func is_dead() -> bool:
	return has_stat(&"hp") and current_hp <= 0.0

func set_progression(p_level: int, p_experience: int) -> bool:
	return restore_progression({"level": p_level, "experience": p_experience, "current_hp": current_hp})

func get_value(stat_id: StringName) -> float:
	assert(has_stat(stat_id))
	return _get_value(stat_id)

func _get_value(stat_id: StringName) -> float:
	var additive := 0.0
	var multiplier := 1.0
	var modifier_ids := _modifiers.keys()
	modifier_ids.sort()
	for modifier_id in modifier_ids:
		var modifier := _modifiers[modifier_id] as StatModifier
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
	experience += amount
	var levels_gained := 0
	while not is_at_maximum_level():
		var required := get_experience_to_next_level()
		if experience < required:
			break
		experience -= required
		level += 1
		levels_gained += 1
	if is_at_maximum_level():
		experience = 0
	return levels_gained

func get_experience_to_next_level() -> int:
	if is_at_maximum_level():
		return 0
	# Revisit the experience curve when progression design is finalized.
	return _definition.get_experience_requirement(level)

func is_at_maximum_level() -> bool:
	return _definition.maximum_level > 0 and level >= _definition.maximum_level

func damage(amount: float) -> float:
	assert(amount >= 0.0)
	assert(has_stat(&"hp"))
	var previous := current_hp
	current_hp = maxf(0.0, current_hp - amount)
	return previous - current_hp

func heal(amount: float) -> float:
	assert(amount >= 0.0)
	assert(has_stat(&"hp"))
	var previous := current_hp
	current_hp = minf(get_value(&"hp"), current_hp + amount)
	return current_hp - previous

func add_modifier(modifier: StatModifier) -> bool:
	if modifier == null or not modifier.is_valid(_definition) or _modifiers.has(modifier.id):
		return false
	_modifiers[modifier.id] = modifier
	if modifier.duration_seconds > 0.0:
		_remaining_duration[modifier.id] = modifier.duration_seconds
	_clamp_current_hp()
	return true

func can_replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	var runtime_modifiers: Array[StatModifier] = []
	return _prepare_source_modifiers(source_id, source_instance_id, modifiers, runtime_modifiers)

func replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	var runtime_modifiers: Array[StatModifier] = []
	if not _prepare_source_modifiers(source_id, source_instance_id, modifiers, runtime_modifiers):
		return false
	_erase_modifiers_from_source_instance(source_instance_id)
	for modifier in runtime_modifiers:
		_modifiers[modifier.id] = modifier
		if modifier.duration_seconds > 0.0:
			_remaining_duration[modifier.id] = modifier.duration_seconds
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
	return true

func remove_modifier(modifier_id: StringName) -> bool:
	if not _modifiers.erase(modifier_id):
		return false
	_remaining_duration.erase(modifier_id)
	_clamp_current_hp()
	return true

func remove_modifiers_from_source_instance(source_instance_id: StringName) -> int:
	if source_instance_id.is_empty():
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
	if restored_hp < 0.0:
		return false
	level = restored_level
	experience = restored_experience
	current_hp = minf(restored_hp, maximum_hp)
	return true

func _clamp_current_hp():
	if has_stat(&"hp"):
		current_hp = minf(current_hp, get_value(&"hp"))
