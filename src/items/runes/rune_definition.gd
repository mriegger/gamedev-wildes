extends ItemDefinition
class_name RuneDefinition

enum ArmorSlotMask {
	HEAD = 1,
	CHEST = 2,
	LEGS = 4,
	FEET = 8,
}

const ALL_ARMOR_SLOTS: int = ArmorSlotMask.HEAD | ArmorSlotMask.CHEST | ArmorSlotMask.LEGS | ArmorSlotMask.FEET

@export var compatible_equipment_types: Array[EquipmentTypeDefinition] = []
@export_flags("Head:1", "Chest:2", "Legs:4", "Feet:8") var compatible_armor_slots: int = 0
@export var socket_modifiers: Array[StatModifier]

func validate(source: String, armor_type: EquipmentTypeDefinition) -> bool:
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
	if compatible_equipment_types.is_empty():
		push_error("[RuneDefinition] Missing compatible equipment types for %s at %s" % [id, source])
		valid = false
	var compatible_type_ids: Dictionary = {}
	for equipment_type in compatible_equipment_types:
		if equipment_type == null or equipment_type.id.is_empty() or compatible_type_ids.has(equipment_type.id):
			push_error("[RuneDefinition] Invalid compatible equipment type for %s at %s" % [id, source])
			valid = false
			continue
		compatible_type_ids[equipment_type.id] = true
	if compatible_armor_slots < 0 or (compatible_armor_slots & ALL_ARMOR_SLOTS) != compatible_armor_slots:
		push_error("[RuneDefinition] Invalid armor slots for %s at %s" % [id, source])
		valid = false
	elif armor_type != null and _targets_branch(armor_type) != (compatible_armor_slots != 0):
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
	if item == null or item is RuneDefinition or not is_equipment_type_compatible(item.equipment_type):
		return false
	var armor := item as ArmorDefinition
	if armor != null:
		return (compatible_armor_slots & (1 << armor.armor_slot)) != 0
	return true

func is_equipment_type_compatible(equipment_type: EquipmentTypeDefinition) -> bool:
	if equipment_type == null:
		return false
	for compatible_type in compatible_equipment_types:
		if compatible_type != null and equipment_type.is_or_inherits(compatible_type):
			return true
	return false

func _targets_branch(branch_root: EquipmentTypeDefinition) -> bool:
	for compatible_type in compatible_equipment_types:
		if compatible_type != null and compatible_type.overlaps_branch(branch_root):
			return true
	return false
