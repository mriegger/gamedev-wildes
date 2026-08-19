extends RefCounted
class_name EquipmentInstanceFactory

const MAXIMUM_NEXT_INSTANCE_ID: int = EquipmentInstance.MAXIMUM_INSTANCE_ID + 1

var item_catalog: ItemCatalog
var _next_instance_id: int

func _init(p_item_catalog: ItemCatalog, p_next_instance_id: int = 1):
	assert(p_item_catalog != null)
	assert(p_next_instance_id > 0 and p_next_instance_id <= MAXIMUM_NEXT_INSTANCE_ID)
	item_catalog = p_item_catalog
	_next_instance_id = p_next_instance_id

func get_next_instance_id() -> int:
	return _next_instance_id

func copy() -> EquipmentInstanceFactory:
	return EquipmentInstanceFactory.new(item_catalog, _next_instance_id)

func can_advance_next_instance_id(expected_next_instance_id: int, pending_next_instance_id: int) -> bool:
	return not (
		expected_next_instance_id != _next_instance_id
		or pending_next_instance_id < expected_next_instance_id
		or pending_next_instance_id > MAXIMUM_NEXT_INSTANCE_ID
	)

func try_advance_next_instance_id(expected_next_instance_id: int, pending_next_instance_id: int) -> bool:
	if not can_advance_next_instance_id(expected_next_instance_id, pending_next_instance_id):
		return false
	_next_instance_id = pending_next_instance_id
	return true

func create(
	item_id: StringName,
	affix_definitions: Array[EquipmentAffixDefinition] = [],
	socketed_rune_ids: Array[StringName] = [],
	amount_resolver: Callable = Callable(),
) -> EquipmentInstance:
	if _next_instance_id > EquipmentInstance.MAXIMUM_INSTANCE_ID:
		return null
	var instance := _build(
		item_id,
		_next_instance_id,
		affix_definitions,
		socketed_rune_ids,
		amount_resolver,
	)
	if instance == null:
		return null
	_next_instance_id += 1
	return instance

func _build(
	item_id: StringName,
	instance_id: int,
	affix_definitions: Array[EquipmentAffixDefinition] = [],
	socketed_rune_ids: Array[StringName] = [],
	amount_resolver: Callable = Callable(),
) -> EquipmentInstance:
	if instance_id < 1 or not item_catalog.has_definition(item_id):
		return null
	var item := item_catalog.get_definition(item_id)
	if item.equipment_type == null:
		return null
	if not item_catalog.is_valid_socket_loadout(item_id, socketed_rune_ids):
		return null
	var sorted_affix_definitions: Array[EquipmentAffixDefinition] = affix_definitions.duplicate()
	sorted_affix_definitions.sort_custom(_affix_definition_id_less)
	var affixes: Array[EquipmentAffixInstance] = []
	var used_affix_ids: Dictionary = {}
	for definition in sorted_affix_definitions:
		if (
			definition == null
			or used_affix_ids.has(definition.id)
			or not item_catalog.has_equipment_affix(definition.id)
			or item_catalog.get_equipment_affix(definition.id) != definition
			or not definition.is_compatible_with(item)
		):
			return null
		used_affix_ids[definition.id] = true
		var sorted_roll_definitions: Array[EquipmentAffixStatDefinition] = definition.stat_rolls.duplicate()
		sorted_roll_definitions.sort_custom(_stat_definition_id_less)
		var rolls: Array[EquipmentAffixStatRoll] = []
		for roll_definition in sorted_roll_definitions:
			if roll_definition == null:
				return null
			var amount := roll_definition.minimum_amount
			if not is_equal_approx(roll_definition.minimum_amount, roll_definition.maximum_amount):
				if not amount_resolver.is_valid():
					return null
				var resolved_amount: Variant = amount_resolver.call(
					definition.id,
					roll_definition.stat_id,
					roll_definition.minimum_amount,
					roll_definition.maximum_amount,
				)
				if typeof(resolved_amount) != TYPE_FLOAT and typeof(resolved_amount) != TYPE_INT:
					return null
				amount = float(resolved_amount)
				if (
					not is_finite(amount)
					or amount < roll_definition.minimum_amount
					or amount > roll_definition.maximum_amount
				):
					return null
			rolls.append(EquipmentAffixStatRoll.new(
				roll_definition.stat_id,
				roll_definition.operation,
				amount,
			))
		affixes.append(EquipmentAffixInstance.new(definition.id, rolls))
	return EquipmentInstance.new(
		instance_id,
		affixes,
		socketed_rune_ids,
	)

static func _affix_definition_id_less(
	left: EquipmentAffixDefinition,
	right: EquipmentAffixDefinition,
) -> bool:
	if left == null:
		return right != null
	if right == null:
		return false
	return String(left.id) < String(right.id)

static func _stat_definition_id_less(
	left: EquipmentAffixStatDefinition,
	right: EquipmentAffixStatDefinition,
) -> bool:
	if left == null:
		return right != null
	if right == null:
		return false
	return String(left.stat_id) < String(right.stat_id)

func is_valid_instance(item_id: StringName, instance: EquipmentInstance) -> bool:
	if (
		instance == null
		or instance.instance_id < 1
		or instance.instance_id > EquipmentInstance.MAXIMUM_INSTANCE_ID
		or instance.instance_id >= _next_instance_id
		or not item_catalog.has_definition(item_id)
	):
		return false
	var item := item_catalog.get_definition(item_id)
	if (
		item.equipment_type == null
		or not item_catalog.is_valid_persisted_socket_loadout(instance.socketed_rune_ids)
	):
		return false
	var used_affix_ids: Dictionary = {}
	for affix in instance.affixes:
		if (
			affix == null
			or affix.affix_id.is_empty()
			or used_affix_ids.has(affix.affix_id)
			or not item_catalog.has_equipment_affix(affix.affix_id)
		):
			return false
		used_affix_ids[affix.affix_id] = true
		var affix_definition := item_catalog.get_equipment_affix(affix.affix_id)
		if affix.stat_rolls.is_empty():
			return false
		var used_stat_ids: Dictionary = {}
		for roll in affix.stat_rolls:
			if (
				roll == null
				or roll.stat_id.is_empty()
				or used_stat_ids.has(roll.stat_id)
				or (roll.operation != StatModifier.Operation.ADD and roll.operation != StatModifier.Operation.MULTIPLY)
				or not is_finite(roll.amount)
				or (roll.operation == StatModifier.Operation.MULTIPLY and roll.amount < 0.0)
			):
				return false
			var has_schema := false
			for stat_definition in affix_definition.stat_rolls:
				if stat_definition.stat_id == roll.stat_id:
					has_schema = true
					break
			if not has_schema:
				return false
			used_stat_ids[roll.stat_id] = true
	return true

func can_restore_state(next_instance_id: int, instance_ids: Array[int]) -> bool:
	if next_instance_id < 1 or next_instance_id > MAXIMUM_NEXT_INSTANCE_ID:
		return false
	var used_ids: Dictionary = {}
	for instance_id in instance_ids:
		if instance_id < 1 or instance_id >= next_instance_id or used_ids.has(instance_id):
			return false
		used_ids[instance_id] = true
	return true
