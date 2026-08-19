extends RefCounted
class_name ActorStats

const StatModifierReplacementType = preload("res://stats/stat_modifier_replacement.gd")
const PreparedStatModifierChangeType = preload("res://stats/prepared_stat_modifier_change.gd")

signal health_depleted
signal health_changed(current_hp: float, maximum_hp: float)

var current_hp: float:
	get:
		return _current_hp

var _definition: ActorStatsDefinition
var _base_values: Dictionary
var _modifiers: Dictionary = {}
var _remaining_duration: Dictionary = {}
var _current_hp: float
var _level: int
var _experience: int
var _revision: int = 0
var _loadout_bound: bool = false
var _loadout_source_instance_ids: Dictionary = {}

func _init(definition: ActorStatsDefinition):
	_definition = definition
	_base_values = definition.get_base_stats().duplicate()
	_level = definition.starting_level
	_experience = definition.starting_experience
	_current_hp = get_value(&"hp") if definition.has_stat(&"hp") else 0.0

func has_stat(stat_id: StringName) -> bool:
	return _base_values.has(stat_id)

func get_revision() -> int:
	return _revision

func get_level() -> int:
	return _level

func get_experience() -> int:
	return _experience

func _can_bind_loadout(source_instance_ids: Array[StringName]) -> bool:
	return not _loadout_bound and _are_valid_source_instance_ids(source_instance_ids)

func _bind_loadout(source_instance_ids: Array[StringName]) -> bool:
	if not _can_bind_loadout(source_instance_ids):
		return false
	for source_instance_id in source_instance_ids:
		_loadout_source_instance_ids[source_instance_id] = true
	_loadout_bound = true
	return true

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
	var previous_current_hp := _current_hp
	var previous_maximum_hp := get_value(&"hp") if has_stat(&"hp") else 0.0
	var previous: float = float(_base_values[stat_id])
	_base_values[stat_id] = value
	if not _has_valid_modifier_values(_modifiers):
		_base_values[stat_id] = previous
		return false
	if previous != value:
		_revision += 1
	_clamp_current_hp()
	_emit_maximum_hp_change(previous_current_hp, previous_maximum_hp)
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
	var previous_level := _level
	var previous_experience := _experience
	_experience += amount
	var levels_gained := 0
	while not is_at_maximum_level():
		var required := get_experience_to_next_level()
		if _experience < required:
			break
		_experience -= required
		_level += 1
		levels_gained += 1
	if is_at_maximum_level():
		_experience = 0
	if _level != previous_level or _experience != previous_experience:
		_revision += 1
	return levels_gained

func get_total_experience() -> int:
	var total := _experience
	for completed_level in range(1, _level):
		total += _definition.get_experience_requirement(completed_level)
	return total

func get_experience_to_next_level() -> int:
	if is_at_maximum_level():
		return 0
	return _definition.get_experience_requirement(_level)

func is_at_maximum_level() -> bool:
	return _definition.maximum_level > 0 and _level >= _definition.maximum_level

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
	if (
		modifier == null
		or _is_loadout_source_instance(modifier.source_instance_id)
		or _modifiers.has(modifier.id)
	):
		return false
	var runtime_modifier := modifier.duplicate() as StatModifier
	if runtime_modifier == null or not runtime_modifier.is_valid(_definition):
		return false
	var projected := _modifiers.duplicate()
	projected[runtime_modifier.id] = runtime_modifier
	if not _has_valid_modifier_values(projected):
		return false
	var previous_current_hp := _current_hp
	var previous_maximum_hp := get_value(&"hp") if has_stat(&"hp") else 0.0
	_modifiers[runtime_modifier.id] = runtime_modifier
	if runtime_modifier.duration_seconds > 0.0:
		_remaining_duration[runtime_modifier.id] = runtime_modifier.duration_seconds
	_revision += 1
	_clamp_current_hp()
	_emit_maximum_hp_change(previous_current_hp, previous_maximum_hp)
	return true

func can_replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	var replacements: Array[StatModifierReplacementType] = [
		StatModifierReplacementType.new(source_id, source_instance_id, modifiers),
	]
	return can_replace_modifier_sources(replacements)

func can_restore_progression_with_replaced_source_modifiers(
	snapshot: Dictionary,
	source_id: StringName,
	source_instance_id: StringName,
	modifiers: Array[StatModifier],
) -> bool:
	var replacements: Array[StatModifierReplacementType] = [
		StatModifierReplacementType.new(source_id, source_instance_id, modifiers),
	]
	var prepared := prepare_modifier_sources(replacements)
	if prepared == null:
		return false
	return not _validated_progression(snapshot, prepared._copy_modifiers()).is_empty()

func replace_source_modifiers(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	var replacements: Array[StatModifierReplacementType] = [
		StatModifierReplacementType.new(source_id, source_instance_id, modifiers),
	]
	return _replace_modifier_sources(replacements, [])

func replace_source_modifiers_preserving_health_ratio(source_id: StringName, source_instance_id: StringName, modifiers: Array[StatModifier]) -> bool:
	var replacements: Array[StatModifierReplacementType] = [
		StatModifierReplacementType.new(source_id, source_instance_id, modifiers),
	]
	return _replace_modifier_sources(replacements, [source_instance_id])

func can_replace_modifier_sources(replacements: Array[StatModifierReplacementType]) -> bool:
	return prepare_modifier_sources(replacements) != null

func prepare_noop_change() -> PreparedStatModifierChange:
	var target_source_instance_ids: Array[StringName] = []
	return PreparedStatModifierChangeType.new(
		self,
		_revision,
		_modifiers,
		_remaining_duration,
		_current_hp,
		false,
		target_source_instance_ids,
		false,
	)

func _prepare_health_restore_on_loadout_change(
	prepared: PreparedStatModifierChange,
	health_restore_fraction: float,
) -> PreparedStatModifierChange:
	if (
		not has_stat(&"hp")
		or not is_finite(health_restore_fraction)
		or health_restore_fraction <= 0.0
		or not _can_commit_prepared_loadout_modifier_change(prepared)
	):
		return null
	var projected_modifiers := prepared._copy_modifiers()
	var projected_maximum_hp := _get_value_with_modifiers(&"hp", projected_modifiers)
	var projected_current_hp := prepared._get_current_hp()
	var restored_hp := minf(
		projected_maximum_hp,
		projected_current_hp + projected_maximum_hp * health_restore_fraction,
	)
	if not is_finite(restored_hp) or restored_hp <= projected_current_hp:
		return null
	return PreparedStatModifierChangeType.new(
		self,
		_revision,
		projected_modifiers,
		prepared._copy_remaining_duration(),
		restored_hp,
		true,
		prepared._get_target_source_instance_ids(),
		prepared._is_loadout_authorized(),
	)

func prepare_modifier_sources(
	replacements: Array[StatModifierReplacementType],
	preserve_health_ratio_source_instances: Array[StringName] = [],
) -> PreparedStatModifierChange:
	return _prepare_modifier_sources(
		replacements,
		preserve_health_ratio_source_instances,
		false,
	)

func _prepare_loadout_modifier_sources(
	replacements: Array[StatModifierReplacementType],
	preserve_health_ratio_source_instances: Array[StringName] = [],
) -> PreparedStatModifierChange:
	if not _loadout_bound:
		return null
	return _prepare_modifier_sources(
		replacements,
		preserve_health_ratio_source_instances,
		true,
	)

func _prepare_modifier_sources(
	replacements: Array[StatModifierReplacementType],
	preserve_health_ratio_source_instances: Array[StringName],
	loadout_authorized: bool,
) -> PreparedStatModifierChange:
	if replacements.is_empty():
		return null
	var preserved_lookup: Dictionary = {}
	for source_instance_id in preserve_health_ratio_source_instances:
		if source_instance_id.is_empty() or preserved_lookup.has(source_instance_id):
			return null
		preserved_lookup[source_instance_id] = true
	var ordinary: Array[StatModifierReplacementType] = []
	var preserved: Array[StatModifierReplacementType] = []
	var replacement_ids: Dictionary = {}
	var target_source_instance_ids: Array[StringName] = []
	for replacement in replacements:
		if replacement == null or replacement_ids.has(replacement.source_instance_id):
			return null
		if loadout_authorized != _is_loadout_source_instance(replacement.source_instance_id):
			return null
		replacement_ids[replacement.source_instance_id] = true
		target_source_instance_ids.append(replacement.source_instance_id)
		if preserved_lookup.has(replacement.source_instance_id):
			preserved.append(replacement)
		else:
			ordinary.append(replacement)
	for source_instance_id in preserved_lookup:
		if not replacement_ids.has(source_instance_id):
			return null
	var intermediate := {
		"modifiers": _modifiers.duplicate(),
		"remaining_duration": _remaining_duration.duplicate(),
	}
	if not ordinary.is_empty():
		intermediate = _prepare_modifier_sources_from(
			intermediate["modifiers"],
			intermediate["remaining_duration"],
			ordinary,
		)
		if intermediate.is_empty():
			return null
	var projected_hp := _current_hp
	var prepared := intermediate
	if not preserved.is_empty():
		prepared = _prepare_modifier_sources_from(
			intermediate["modifiers"],
			intermediate["remaining_duration"],
			preserved,
		)
		if prepared.is_empty():
			return null
	if not _has_valid_modifier_values(prepared["modifiers"]):
		return null
	if has_stat(&"hp"):
		var intermediate_maximum_hp := _get_value_with_modifiers(&"hp", intermediate["modifiers"])
		var final_maximum_hp := _get_value_with_modifiers(&"hp", prepared["modifiers"])
		if is_finite(intermediate_maximum_hp) and intermediate_maximum_hp > 0.0:
			projected_hp = minf(projected_hp, intermediate_maximum_hp)
			if not preserved.is_empty() and intermediate_maximum_hp != final_maximum_hp:
				var health_ratio := projected_hp / intermediate_maximum_hp
				projected_hp = clampf(health_ratio * final_maximum_hp, 0.0, final_maximum_hp)
		else:
			projected_hp = clampf(projected_hp, 0.0, final_maximum_hp)
	return PreparedStatModifierChangeType.new(
		self,
		_revision,
		prepared["modifiers"],
		prepared["remaining_duration"],
		projected_hp,
		not _modifier_states_match(
			_modifiers,
			_remaining_duration,
			_current_hp,
			prepared["modifiers"],
			prepared["remaining_duration"],
			projected_hp,
		),
		target_source_instance_ids,
		loadout_authorized,
	)

func can_commit_prepared_modifier_change(prepared: PreparedStatModifierChange) -> bool:
	return (
		_can_commit_prepared_modifier_change(prepared)
		and not prepared._targets_any_source_instance(_loadout_source_instance_ids)
	)

func _can_commit_prepared_loadout_modifier_change(prepared: PreparedStatModifierChange) -> bool:
	return (
		_can_commit_prepared_modifier_change(prepared)
		and (
			prepared._get_target_source_instance_ids().is_empty()
			or (
				prepared._is_loadout_authorized()
				and prepared._targets_only_source_instances(_loadout_source_instance_ids)
			)
		)
	)

func _can_commit_prepared_modifier_change(prepared: PreparedStatModifierChange) -> bool:
	return prepared != null and prepared._is_for(self) and prepared.get_expected_revision() == _revision

func _commit_prepared_modifier_change(
	prepared: PreparedStatModifierChange,
	emit_health_signals: bool = true,
) -> bool:
	assert(can_commit_prepared_modifier_change(prepared))
	return _apply_prepared_modifier_change(prepared, emit_health_signals)

func _commit_prepared_loadout_modifier_change(
	prepared: PreparedStatModifierChange,
	emit_health_signals: bool = true,
) -> bool:
	assert(_can_commit_prepared_loadout_modifier_change(prepared))
	return _apply_prepared_modifier_change(prepared, emit_health_signals)

func _apply_prepared_modifier_change(
	prepared: PreparedStatModifierChange,
	emit_health_signals: bool,
) -> bool:
	if not prepared._has_state_change():
		return false
	var was_alive := has_stat(&"hp") and _current_hp > 0.0
	var health_state_changed := _prepared_modifier_change_changes_health(prepared)
	_modifiers = prepared._copy_modifiers()
	_remaining_duration = prepared._copy_remaining_duration()
	_current_hp = prepared._get_current_hp()
	_revision += 1
	var depleted := was_alive and has_stat(&"hp") and _current_hp <= 0.0
	if emit_health_signals:
		if health_state_changed:
			_emit_health_changed()
		if depleted:
			_emit_health_depleted()
	return depleted

func _prepared_modifier_change_changes_health(prepared: PreparedStatModifierChange) -> bool:
	assert(_can_commit_prepared_modifier_change(prepared))
	if not has_stat(&"hp") or not prepared._has_state_change():
		return false
	return (
		_current_hp != prepared._get_current_hp()
		or get_value(&"hp") != _get_value_with_modifiers(&"hp", prepared._copy_modifiers())
	)

func _emit_health_changed() -> void:
	health_changed.emit(_current_hp, get_value(&"hp"))

func _emit_health_depleted() -> void:
	health_depleted.emit()

func _replace_modifier_sources(
	replacements: Array[StatModifierReplacementType],
	preserve_health_ratio_source_instances: Array[StringName],
) -> bool:
	var prepared := prepare_modifier_sources(replacements, preserve_health_ratio_source_instances)
	if prepared == null:
		return false
	_commit_prepared_modifier_change(prepared)
	return true

func _prepare_modifier_sources_from(
	base_modifiers: Dictionary,
	base_remaining_duration: Dictionary,
	replacements: Array[StatModifierReplacementType],
) -> Dictionary:
	if replacements.is_empty():
		return {}
	var projected := base_modifiers.duplicate()
	var projected_remaining_duration := base_remaining_duration.duplicate()
	var replaced_source_instances: Dictionary = {}
	var previous_modifiers: Dictionary = {}
	var previous_remaining_duration: Dictionary = {}
	for replacement in replacements:
		if (
			replacement == null
			or replacement.source_id.is_empty()
			or replacement.source_instance_id.is_empty()
			or replaced_source_instances.has(replacement.source_instance_id)
		):
			return {}
		replaced_source_instances[replacement.source_instance_id] = true
		for modifier_id in projected.keys():
			var existing := projected[modifier_id] as StatModifier
			if existing.source_instance_id == replacement.source_instance_id:
				previous_modifiers[modifier_id] = existing
				if projected_remaining_duration.has(modifier_id):
					previous_remaining_duration[modifier_id] = projected_remaining_duration[modifier_id]
				projected.erase(modifier_id)
				projected_remaining_duration.erase(modifier_id)
	for replacement in replacements:
		for index in range(replacement.modifiers.size()):
			if replacement.modifiers[index] == null:
				return {}
			var modifier := replacement.modifiers[index].duplicate() as StatModifier
			modifier.id = StringName("%s_%d" % [replacement.source_instance_id, index])
			modifier.source_id = replacement.source_id
			modifier.source_instance_id = replacement.source_instance_id
			if projected.has(modifier.id) or not modifier.is_valid(_definition):
				return {}
			projected[modifier.id] = modifier
			if modifier.duration_seconds > 0.0:
				if (
					previous_modifiers.has(modifier.id)
					and previous_remaining_duration.has(modifier.id)
					and _stat_modifiers_match(previous_modifiers[modifier.id], modifier)
				):
					projected_remaining_duration[modifier.id] = previous_remaining_duration[modifier.id]
				else:
					projected_remaining_duration[modifier.id] = modifier.duration_seconds
	return {
		"modifiers": projected,
		"remaining_duration": projected_remaining_duration,
	}

func remove_modifier(modifier_id: StringName) -> bool:
	return _remove_modifier(modifier_id, false)

func _remove_modifier(modifier_id: StringName, loadout_authorized: bool) -> bool:
	if not _modifiers.has(modifier_id):
		return false
	var existing := _modifiers[modifier_id] as StatModifier
	if existing == null or (_is_loadout_source_instance(existing.source_instance_id) and not loadout_authorized):
		return false
	var projected := _modifiers.duplicate()
	projected.erase(modifier_id)
	if not _has_valid_modifier_values(projected):
		return false
	var previous_current_hp := _current_hp
	var previous_maximum_hp := get_value(&"hp") if has_stat(&"hp") else 0.0
	_modifiers.erase(modifier_id)
	_remaining_duration.erase(modifier_id)
	_revision += 1
	_clamp_current_hp()
	_emit_maximum_hp_change(previous_current_hp, previous_maximum_hp)
	return true

func remove_modifiers_from_source_instance(source_instance_id: StringName) -> int:
	if source_instance_id.is_empty() or _is_loadout_source_instance(source_instance_id):
		return 0
	var projected := _modifiers.duplicate()
	for modifier_id in projected.keys():
		var modifier := projected[modifier_id] as StatModifier
		if modifier.source_instance_id == source_instance_id:
			projected.erase(modifier_id)
	if not _has_valid_modifier_values(projected):
		return 0
	var previous_current_hp := _current_hp
	var previous_maximum_hp := get_value(&"hp") if has_stat(&"hp") else 0.0
	var removed := _erase_modifiers_from_source_instance(source_instance_id)
	if removed > 0:
		_revision += 1
		_clamp_current_hp()
		_emit_maximum_hp_change(previous_current_hp, previous_maximum_hp)
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
	var duration_changed := false
	for modifier_id in _remaining_duration:
		var remaining := float(_remaining_duration[modifier_id]) - delta
		if remaining <= 0.0:
			expired.append(modifier_id)
		else:
			if remaining != _remaining_duration[modifier_id]:
				duration_changed = true
			_remaining_duration[modifier_id] = remaining
	if duration_changed:
		_revision += 1
	for modifier_id in expired:
		_remove_modifier(modifier_id, true)

func _are_valid_source_instance_ids(source_instance_ids: Array[StringName]) -> bool:
	if source_instance_ids.is_empty():
		return false
	var unique_ids: Dictionary = {}
	for source_instance_id in source_instance_ids:
		if source_instance_id.is_empty() or unique_ids.has(source_instance_id):
			return false
		unique_ids[source_instance_id] = true
	return true

func _is_loadout_source_instance(source_instance_id: StringName) -> bool:
	return _loadout_bound and _loadout_source_instance_ids.has(source_instance_id)

func snapshot_progression() -> Dictionary:
	return {
		"level": _level,
		"experience": _experience,
		"current_hp": current_hp,
	}

func restore_progression(snapshot: Dictionary) -> bool:
	var restored := _validated_progression(snapshot, _modifiers)
	if restored.is_empty():
		return false
	var restored_level := int(restored["level"])
	var restored_experience := int(restored["experience"])
	var restored_hp := float(restored["current_hp"])
	if _level == restored_level and _experience == restored_experience and _current_hp == restored_hp:
		return true
	var was_alive := has_stat(&"hp") and _current_hp > 0.0
	var health_state_changed := _current_hp != restored_hp
	_level = restored_level
	_experience = restored_experience
	_current_hp = restored_hp
	_revision += 1
	if health_state_changed:
		_emit_health_changed()
	if was_alive and has_stat(&"hp") and _current_hp <= 0.0:
		health_depleted.emit()
	return true

func _validated_progression(snapshot: Dictionary, modifiers: Dictionary) -> Dictionary:
	var restored_level := int(snapshot.get("level", 0))
	var restored_experience := int(snapshot.get("experience", -1))
	if restored_level < 1 or restored_experience < 0:
		return {}
	if _definition.maximum_level > 0 and restored_level > _definition.maximum_level:
		return {}
	if _definition.maximum_level > 0 and restored_level == _definition.maximum_level and restored_experience != 0:
		return {}
	if (_definition.maximum_level == 0 or restored_level < _definition.maximum_level) and restored_experience >= _definition.get_experience_requirement(restored_level):
		return {}
	var maximum_hp := _get_value_with_modifiers(&"hp", modifiers) if has_stat(&"hp") else 0.0
	var restored_hp := float(snapshot.get("current_hp", maximum_hp))
	if not is_finite(restored_hp) or restored_hp < 0.0 or restored_hp > maximum_hp:
		return {}
	return {
		"level": restored_level,
		"experience": restored_experience,
		"current_hp": restored_hp,
	}

func _clamp_current_hp():
	if has_stat(&"hp"):
		_commit_current_hp(minf(current_hp, get_value(&"hp")))

func _commit_current_hp(value: float):
	assert(is_finite(value) and value >= 0.0)
	var was_alive := has_stat(&"hp") and _current_hp > 0.0
	var changed := _current_hp != value
	_current_hp = value
	if changed:
		_revision += 1
		_emit_health_changed()
	if was_alive and _current_hp <= 0.0:
		health_depleted.emit()

func _emit_maximum_hp_change(previous_current_hp: float, previous_maximum_hp: float) -> void:
	if has_stat(&"hp") and _current_hp == previous_current_hp and get_value(&"hp") != previous_maximum_hp:
		_emit_health_changed()

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

func _modifier_states_match(
	first_modifiers: Dictionary,
	first_remaining_duration: Dictionary,
	first_hp: float,
	second_modifiers: Dictionary,
	second_remaining_duration: Dictionary,
	second_hp: float,
) -> bool:
	if first_hp != second_hp or first_modifiers.size() != second_modifiers.size():
		return false
	if first_remaining_duration != second_remaining_duration:
		return false
	for modifier_id in first_modifiers:
		if not second_modifiers.has(modifier_id):
			return false
		if not _stat_modifiers_match(first_modifiers[modifier_id], second_modifiers[modifier_id]):
			return false
	return true

func _stat_modifiers_match(first: StatModifier, second: StatModifier) -> bool:
	return (
		first != null
		and second != null
		and first.id == second.id
		and first.source_id == second.source_id
		and first.source_instance_id == second.source_instance_id
		and first.stat_id == second.stat_id
		and first.operation == second.operation
		and first.amount == second.amount
		and first.duration_seconds == second.duration_seconds
	)
