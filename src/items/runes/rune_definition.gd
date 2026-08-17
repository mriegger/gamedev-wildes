extends ItemDefinition
class_name RuneDefinition

enum CompatibleGear {
	WEAPON = 1,
	ARMOR = 2,
}

enum ArmorSlotMask {
	HEAD = 1,
	CHEST = 2,
	LEGS = 4,
	FEET = 8,
}

const ALL_COMPATIBLE_GEAR: int = CompatibleGear.WEAPON | CompatibleGear.ARMOR
const ALL_ARMOR_SLOTS: int = ArmorSlotMask.HEAD | ArmorSlotMask.CHEST | ArmorSlotMask.LEGS | ArmorSlotMask.FEET

@export_flags("Weapon:1", "Armor:2") var compatible_gear: int = 0
@export_flags("Head:1", "Chest:2", "Legs:4", "Feet:8") var compatible_armor_slots: int = 0
@export var socket_modifiers: Array[StatModifier]

func validate(source: String) -> bool:
	var valid := true
	if rarity == null:
		push_error("[RuneDefinition] Missing rarity for %s at %s" % [id, source])
		valid = false
	if proficiency != null:
		push_error("[RuneDefinition] Rune proficiency is not supported for %s at %s" % [id, source])
		valid = false
	if not stat_modifiers.is_empty():
		push_error("[RuneDefinition] Rune modifiers must be socket-only for %s at %s" % [id, source])
		valid = false
	if compatible_gear == 0 or (compatible_gear & ALL_COMPATIBLE_GEAR) != compatible_gear:
		push_error("[RuneDefinition] Invalid compatible gear for %s at %s" % [id, source])
		valid = false
	var supports_armor := (compatible_gear & CompatibleGear.ARMOR) != 0
	if compatible_armor_slots < 0 or (compatible_armor_slots & ALL_ARMOR_SLOTS) != compatible_armor_slots:
		push_error("[RuneDefinition] Invalid armor slots for %s at %s" % [id, source])
		valid = false
	elif supports_armor != (compatible_armor_slots != 0):
		push_error("[RuneDefinition] Armor compatibility mismatch for %s at %s" % [id, source])
		valid = false
	if socket_modifiers.is_empty():
		push_error("[RuneDefinition] Missing socket modifiers for %s at %s" % [id, source])
		valid = false
	var modifier_ids: Dictionary = {}
	for modifier_index in range(socket_modifiers.size()):
		var modifier := socket_modifiers[modifier_index]
		if modifier == null:
			push_error("[RuneDefinition] Missing socket modifier %d for %s at %s" % [modifier_index, id, source])
			valid = false
			continue
		if (
			modifier.id.is_empty()
			or modifier_ids.has(modifier.id)
			or modifier.source_id != id
			or not modifier.source_instance_id.is_empty()
			or modifier.stat_id.is_empty()
			or not is_finite(modifier.amount)
			or not is_zero_approx(modifier.duration_seconds)
			or (modifier.operation == StatModifier.Operation.MULTIPLY and modifier.amount < 0.0)
			or (modifier.operation != StatModifier.Operation.ADD and modifier.operation != StatModifier.Operation.MULTIPLY)
		):
			push_error("[RuneDefinition] Invalid socket modifier %d for %s at %s" % [modifier_index, id, source])
			valid = false
		modifier_ids[modifier.id] = true
	return valid

func is_compatible_with(item: ItemDefinition) -> bool:
	if item == null or item is RuneDefinition:
		return false
	var armor := item as ArmorDefinition
	if armor != null:
		return (
			(compatible_gear & CompatibleGear.ARMOR) != 0
			and (compatible_armor_slots & (1 << armor.armor_slot)) != 0
		)
	return (
		(compatible_gear & CompatibleGear.WEAPON) != 0
		and item.primary_action is MeleeAttackActionDefinition
	)
