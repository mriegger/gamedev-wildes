extends Resource
class_name LootEquipmentRollDefinition

@export var fixed_affixes: Array[EquipmentAffixDefinition]
@export_range(0, 999, 1, "or_greater") var minimum_random_affix_count: int = 0
@export_range(0, 999, 1, "or_greater") var maximum_random_affix_count: int = 0
@export var random_affixes: Array[LootAffixChoiceDefinition]
@export var fixed_runes: Array[RuneDefinition]
@export_range(0, ProficiencyDefinition.MAXIMUM_SLOT_COUNT, 1) var random_rune_slot_count: int = 0
@export var random_runes: Array[LootRuneChoiceDefinition]

func validate(item: ItemDefinition, source: String) -> bool:
	if item == null or item.equipment_type == null:
		push_error("[LootEquipmentRollDefinition] Equipment roll requires equipment at %s" % source)
		return false
	var valid := true
	if not fixed_affixes.is_empty() and (
		minimum_random_affix_count != 0
		or maximum_random_affix_count != 0
		or not random_affixes.is_empty()
	):
		push_error("[LootEquipmentRollDefinition] Fixed and random affixes cannot be combined at %s" % source)
		valid = false
	if random_affixes.is_empty():
		if minimum_random_affix_count != 0 or maximum_random_affix_count != 0:
			push_error("[LootEquipmentRollDefinition] Random affix count requires choices at %s" % source)
			valid = false
	elif (
		minimum_random_affix_count < 0
		or maximum_random_affix_count < minimum_random_affix_count
		or maximum_random_affix_count < 1
		or maximum_random_affix_count > random_affixes.size()
	):
		push_error("[LootEquipmentRollDefinition] Invalid random affix count at %s" % source)
		valid = false
	var affix_ids: Dictionary = {}
	for affix_index in range(fixed_affixes.size()):
		var affix := fixed_affixes[affix_index]
		if affix == null or affix_ids.has(affix.id) or not affix.is_compatible_with(item):
			push_error("[LootEquipmentRollDefinition] Invalid fixed affix %d at %s" % [affix_index, source])
			valid = false
		elif not affix.id.is_empty():
			affix_ids[affix.id] = true
	var affix_choice_ids: Dictionary = {}
	var affix_weight_total := 0.0
	for choice_index in range(random_affixes.size()):
		var choice := random_affixes[choice_index]
		var choice_source := "%s random affix %d" % [source, choice_index]
		if choice == null:
			push_error("[LootEquipmentRollDefinition] Missing random affix choice %d at %s" % [choice_index, source])
			valid = false
			continue
		valid = choice.validate(item, choice_source) and valid
		affix_weight_total += choice.weight
		if affix_choice_ids.has(choice.id):
			push_error("[LootEquipmentRollDefinition] Duplicate random affix choice %s at %s" % [choice.id, source])
			valid = false
		if choice.affix != null and affix_ids.has(choice.affix.id):
			push_error("[LootEquipmentRollDefinition] Duplicate random affix %s at %s" % [choice.affix.id, source])
			valid = false
		affix_choice_ids[choice.id] = true
		if choice.affix != null:
			affix_ids[choice.affix.id] = true
	if not is_finite(affix_weight_total):
		push_error("[LootEquipmentRollDefinition] Random affix weight total is not finite at %s" % source)
		valid = false
	if not fixed_runes.is_empty() and (random_rune_slot_count != 0 or not random_runes.is_empty()):
		push_error("[LootEquipmentRollDefinition] Fixed and random runes cannot be combined at %s" % source)
		valid = false
	if (
		random_rune_slot_count < 0
		or random_rune_slot_count > ProficiencyDefinition.MAXIMUM_SLOT_COUNT
		or random_runes.is_empty() != (random_rune_slot_count == 0)
	):
		push_error("[LootEquipmentRollDefinition] Random rune slots and choices must be configured together at %s" % source)
		valid = false
	var slot_count := fixed_runes.size() if not fixed_runes.is_empty() else random_rune_slot_count
	if slot_count > ProficiencyDefinition.MAXIMUM_SLOT_COUNT or (
		slot_count > 0
		and (item.proficiency == null or slot_count > item.proficiency.slot_unlock_levels.size())
	):
		push_error("[LootEquipmentRollDefinition] Rune slots exceed equipment capacity at %s" % source)
		valid = false
	for rune_index in range(fixed_runes.size()):
		var rune := fixed_runes[rune_index]
		if rune == null or not rune.is_compatible_with(item):
			push_error("[LootEquipmentRollDefinition] Invalid fixed rune %d at %s" % [rune_index, source])
			valid = false
	var rune_choice_ids: Dictionary = {}
	var rune_ids: Dictionary = {}
	var rune_weight_total := 0.0
	for choice_index in range(random_runes.size()):
		var choice := random_runes[choice_index]
		var choice_source := "%s random rune %d" % [source, choice_index]
		if choice == null:
			push_error("[LootEquipmentRollDefinition] Missing random rune choice %d at %s" % [choice_index, source])
			valid = false
			continue
		valid = choice.validate(item, choice_source) and valid
		rune_weight_total += choice.weight
		if rune_choice_ids.has(choice.id):
			push_error("[LootEquipmentRollDefinition] Duplicate random rune choice %s at %s" % [choice.id, source])
			valid = false
		if choice.rune != null and rune_ids.has(choice.rune.id):
			push_error("[LootEquipmentRollDefinition] Duplicate random rune %s at %s" % [choice.rune.id, source])
			valid = false
		rune_choice_ids[choice.id] = true
		if choice.rune != null:
			rune_ids[choice.rune.id] = true
	if not is_finite(rune_weight_total):
		push_error("[LootEquipmentRollDefinition] Random rune weight total is not finite at %s" % source)
		valid = false
	return valid
