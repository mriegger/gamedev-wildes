extends ItemDefinition
class_name ArmorDefinition

enum Slot {
	HEAD,
	CHEST,
	LEGS,
	FEET,
	COUNT,
}

const SLOT_LABELS: Dictionary[int, String] = {
	Slot.HEAD: "Head",
	Slot.CHEST: "Chest",
	Slot.LEGS: "Legs",
	Slot.FEET: "Feet",
}
const SLOT_COUNT: int = Slot.COUNT

@export var armor_slot: Slot = Slot.HEAD
@export var armor_set: ArmorSetDefinition
@export var visual_parts: Array[ArmorVisualPart] = []

static func is_valid_slot(value: int) -> bool:
	return SLOT_LABELS.has(value)

static func get_slot_label(value: int) -> String:
	assert(is_valid_slot(value))
	return SLOT_LABELS[value]

func validate(source: String) -> bool:
	var valid := true
	if not is_valid_slot(armor_slot):
		push_error("[ArmorDefinition] Invalid armor slot at %s" % source)
		valid = false
	if max_stack != 1:
		push_error("[ArmorDefinition] Armor must have max stack 1 at %s" % source)
		valid = false
	if stat_modifier_activation != ItemDefinition.StatModifierActivation.EQUIPPED:
		push_error("[ArmorDefinition] Armor modifiers must activate while equipped at %s" % source)
		valid = false
	if visual_parts.is_empty():
		push_error("[ArmorDefinition] Armor visual parts are missing at %s" % source)
		valid = false
	for part_index in range(visual_parts.size()):
		var part := visual_parts[part_index]
		if part == null:
			push_error("[ArmorDefinition] Missing visual part %d at %s" % [part_index, source])
			valid = false
		elif not part.validate("%s visual part %d" % [source, part_index]):
			valid = false
	return valid
