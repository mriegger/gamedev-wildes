extends Resource
class_name EquipmentAffixDefinition

enum ArmorSlotMask {
	HEAD = 1,
	CHEST = 2,
	LEGS = 4,
	FEET = 8,
}

const ALL_ARMOR_SLOTS: int = ArmorSlotMask.HEAD | ArmorSlotMask.CHEST | ArmorSlotMask.LEGS | ArmorSlotMask.FEET

@export var id: StringName
@export var display_name_suffix: String
@export var compatible_equipment_types: Array[EquipmentTypeDefinition] = []
@export_flags("Head:1", "Chest:2", "Legs:4", "Feet:8") var compatible_armor_slots: int = 0
@export var stat_rolls: Array[EquipmentAffixStatDefinition] = []

func validate(source: String, armor_type: EquipmentTypeDefinition = null) -> bool:
	var valid := true
	if id.is_empty() or display_name_suffix.is_empty():
		push_error("[EquipmentAffixDefinition] Missing identity at %s" % source)
		valid = false
	if compatible_equipment_types.is_empty():
		push_error("[EquipmentAffixDefinition] Missing compatible equipment types for %s at %s" % [id, source])
		valid = false
	var compatible_type_ids: Dictionary = {}
	for equipment_type in compatible_equipment_types:
		if equipment_type == null or equipment_type.id.is_empty() or compatible_type_ids.has(equipment_type.id):
			push_error("[EquipmentAffixDefinition] Invalid compatible equipment type for %s at %s" % [id, source])
			valid = false
			continue
		compatible_type_ids[equipment_type.id] = true
	if compatible_armor_slots < 0 or (compatible_armor_slots & ALL_ARMOR_SLOTS) != compatible_armor_slots:
		push_error("[EquipmentAffixDefinition] Invalid armor slots for %s at %s" % [id, source])
		valid = false
	elif armor_type != null and _targets_branch(armor_type) != (compatible_armor_slots != 0):
		push_error("[EquipmentAffixDefinition] Armor compatibility mismatch for %s at %s" % [id, source])
		valid = false
	if stat_rolls.is_empty():
		push_error("[EquipmentAffixDefinition] Missing stat rolls for %s at %s" % [id, source])
		valid = false
	var stat_ids: Dictionary = {}
	for stat_index in range(stat_rolls.size()):
		var stat_roll := stat_rolls[stat_index]
		if stat_roll == null or stat_ids.has(stat_roll.stat_id):
			push_error("[EquipmentAffixDefinition] Invalid stat roll %d for %s at %s" % [stat_index, id, source])
			valid = false
			continue
		stat_ids[stat_roll.stat_id] = true
		valid = stat_roll.validate("%s stat roll %d" % [source, stat_index]) and valid
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
