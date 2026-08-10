extends ItemDefinition
class_name ArmorDefinition

enum Slot {
	HELMET,
	CHEST_PLATE,
	PANTS,
	SHOES,
	COUNT,
}

const SLOT_LABELS: Dictionary[int, String] = {
	Slot.HELMET: "Helmet",
	Slot.CHEST_PLATE: "Chest Plate",
	Slot.PANTS: "Pants",
	Slot.SHOES: "Shoes",
}
const SLOT_COUNT: int = Slot.COUNT

@export var armor_slot: Slot = Slot.HELMET

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
	return valid
