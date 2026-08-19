extends RefCounted
class_name LootResolver

const InventoryStackType := preload("res://inventory/inventory_stack.gd")

static func prepare(
	pool: LootPoolDefinition,
	seed: int,
	equipment_instance_factory: EquipmentInstanceFactory,
) -> PreparedLootResolution:
	assert(pool != null)
	assert(equipment_instance_factory != null)
	var expected_next_instance_id := equipment_instance_factory.get_next_instance_id()
	var pending_factory := equipment_instance_factory.copy()
	var drops: Array[InventoryStack] = []
	var independent_rolls: Array[LootIndependentRollDefinition] = pool.independent_rolls.duplicate()
	independent_rolls.sort_custom(_definition_id_less)
	for roll in independent_rolls:
		var roll_path := _path([&"independent", roll.id])
		if LootKeyedRandom.unit(seed, pool.id, _child_path(roll_path, &"chance")) >= roll.chance:
			continue
		var stack := _resolve_drop(pool.id, seed, roll_path, roll.drop, pending_factory)
		if stack == null:
			return null
		drops.append(stack)
	var exclusive_groups: Array[LootExclusiveGroupDefinition] = pool.exclusive_groups.duplicate()
	exclusive_groups.sort_custom(_definition_id_less)
	for group in exclusive_groups:
		var group_path := _path([&"exclusive", group.id])
		if LootKeyedRandom.unit(seed, pool.id, _child_path(group_path, &"chance")) >= group.chance:
			continue
		var choices: Array[LootWeightedChoiceDefinition] = group.choices.duplicate()
		choices.sort_custom(_definition_id_less)
		var choice_index := _weighted_index(
			seed,
			pool.id,
			_child_path(group_path, &"choice"),
			_choice_weights(choices),
		)
		var choice := choices[choice_index]
		var stack := _resolve_drop(
			pool.id,
			seed,
			_child_path(group_path, choice.id),
			choice.drop,
			pending_factory,
		)
		if stack == null:
			return null
		drops.append(stack)
	return PreparedLootResolution.new(
		equipment_instance_factory,
		expected_next_instance_id,
		pending_factory.get_next_instance_id(),
		drops,
	)

static func _can_commit(
	prepared: PreparedLootResolution,
	equipment_instance_factory: EquipmentInstanceFactory,
) -> bool:
	return (
		prepared != null
		and equipment_instance_factory != null
		and prepared._is_for(equipment_instance_factory)
		and prepared._is_prepared()
		and equipment_instance_factory.can_advance_next_instance_id(
			prepared._get_expected_next_instance_id(),
			prepared._get_pending_next_instance_id(),
		)
	)

static func _commit(
	prepared: PreparedLootResolution,
	equipment_instance_factory: EquipmentInstanceFactory,
) -> bool:
	if not _can_commit(prepared, equipment_instance_factory):
		return false
	if not equipment_instance_factory.try_advance_next_instance_id(
		prepared._get_expected_next_instance_id(),
		prepared._get_pending_next_instance_id(),
	):
		return false
	var marked := prepared._mark_committed(equipment_instance_factory)
	assert(marked)
	return marked

static func _resolve_drop(
	pool_id: StringName,
	seed: int,
	path: Array[StringName],
	drop: LootDropDefinition,
	factory: EquipmentInstanceFactory,
) -> InventoryStack:
	var count := LootKeyedRandom.integer_inclusive(
		seed,
		pool_id,
		_child_path(path, &"count"),
		drop.minimum_count,
		drop.maximum_count,
	)
	var equipment_instance: EquipmentInstance
	if drop.item.equipment_type != null:
		var affixes: Array[EquipmentAffixDefinition] = []
		var rune_ids: Array[StringName] = []
		if drop.equipment_roll != null:
			affixes = _resolve_affixes(pool_id, seed, path, drop.equipment_roll)
			rune_ids = _resolve_runes(pool_id, seed, path, drop.equipment_roll)
		var amount_path := _child_path(path, &"affix_amount")
		var amount_resolver := func(
			affix_id: StringName,
			stat_id: StringName,
			minimum_amount: float,
			maximum_amount: float,
		) -> float:
			var stat_path := amount_path.duplicate()
			stat_path.append(affix_id)
			stat_path.append(stat_id)
			return lerpf(
				minimum_amount,
				maximum_amount,
				LootKeyedRandom.unit(seed, pool_id, stat_path),
			)
		equipment_instance = factory.create(drop.item.id, affixes, rune_ids, amount_resolver)
		if equipment_instance == null:
			return null
	return InventoryStackType.new(drop.item.id, count, equipment_instance)

static func _resolve_affixes(
	pool_id: StringName,
	seed: int,
	path: Array[StringName],
	roll: LootEquipmentRollDefinition,
) -> Array[EquipmentAffixDefinition]:
	if not roll.fixed_affixes.is_empty():
		var fixed: Array[EquipmentAffixDefinition] = roll.fixed_affixes.duplicate()
		fixed.sort_custom(_definition_id_less)
		return fixed
	var resolved: Array[EquipmentAffixDefinition] = []
	if roll.random_affixes.is_empty():
		return resolved
	var affix_path := _child_path(path, &"affix")
	var count := LootKeyedRandom.integer_inclusive(
		seed,
		pool_id,
		_child_path(affix_path, &"count"),
		roll.minimum_random_affix_count,
		roll.maximum_random_affix_count,
	)
	var remaining: Array[LootAffixChoiceDefinition] = roll.random_affixes.duplicate()
	remaining.sort_custom(_definition_id_less)
	for affix_index in range(count):
		var choice_index := _weighted_index(
			seed,
			pool_id,
			_child_path(affix_path, StringName(str(affix_index))),
			_affix_weights(remaining),
		)
		resolved.append(remaining[choice_index].affix)
		remaining.remove_at(choice_index)
	return resolved

static func _resolve_runes(
	pool_id: StringName,
	seed: int,
	path: Array[StringName],
	roll: LootEquipmentRollDefinition,
) -> Array[StringName]:
	if not roll.fixed_runes.is_empty():
		var fixed_ids: Array[StringName] = []
		for rune in roll.fixed_runes:
			fixed_ids.append(rune.id)
		return fixed_ids
	var resolved: Array[StringName] = []
	if roll.random_runes.is_empty():
		return resolved
	var choices: Array[LootRuneChoiceDefinition] = roll.random_runes.duplicate()
	choices.sort_custom(_definition_id_less)
	var weights := _rune_weights(choices)
	var rune_path := _child_path(path, &"rune")
	for slot_index in range(roll.random_rune_slot_count):
		var choice_index := _weighted_index(
			seed,
			pool_id,
			_child_path(rune_path, StringName(str(slot_index))),
			weights,
		)
		resolved.append(choices[choice_index].rune.id)
	return resolved

static func _weighted_index(
	seed: int,
	pool_id: StringName,
	path: Array[StringName],
	weights: Array[float],
) -> int:
	var total := 0.0
	for weight in weights:
		total += weight
	var target := LootKeyedRandom.unit(seed, pool_id, path) * total
	var cumulative := 0.0
	for index in range(weights.size()):
		cumulative += weights[index]
		if target < cumulative:
			return index
	return weights.size() - 1

static func _choice_weights(choices: Array[LootWeightedChoiceDefinition]) -> Array[float]:
	var weights: Array[float] = []
	for choice in choices:
		weights.append(choice.weight)
	return weights

static func _affix_weights(choices: Array[LootAffixChoiceDefinition]) -> Array[float]:
	var weights: Array[float] = []
	for choice in choices:
		weights.append(choice.weight)
	return weights

static func _rune_weights(choices: Array[LootRuneChoiceDefinition]) -> Array[float]:
	var weights: Array[float] = []
	for choice in choices:
		weights.append(choice.weight)
	return weights

static func _definition_id_less(left: Resource, right: Resource) -> bool:
	return String(left.get("id")) < String(right.get("id"))

static func _child_path(path: Array[StringName], child: StringName) -> Array[StringName]:
	var result := path.duplicate()
	result.append(child)
	return result

static func _path(values: Array[StringName]) -> Array[StringName]:
	return values
