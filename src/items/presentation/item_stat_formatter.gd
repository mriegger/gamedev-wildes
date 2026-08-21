extends RefCounted
class_name ItemStatFormatter

static func get_item_stat_lines(item_definition: ItemDefinition) -> Array[String]:
	assert(item_definition != null)
	var lines: Array[String] = []
	var armor := item_definition as ArmorDefinition
	if armor != null:
		lines.append("Slot: %s" % ArmorDefinition.get_slot_label(armor.armor_slot))
	lines.append_array(get_melee_stat_lines(item_definition))
	lines.append_array(get_bow_stat_lines(item_definition))
	lines.append_array(get_arrow_stat_lines(item_definition))
	lines.append_array(get_pickaxe_stat_lines(item_definition))
	lines.append_array(get_consumable_stat_lines(item_definition))
	lines.append_array(get_modifier_stat_lines(item_definition.stat_modifiers))
	return lines

static func get_melee_stat_lines(item_definition: ItemDefinition) -> Array[String]:
	assert(item_definition != null)
	var lines: Array[String] = []
	var melee_action := item_definition.primary_action as MeleeAttackActionDefinition
	if melee_action == null:
		return lines
	var profile := melee_action.attack_profile
	var configured_damage := profile.base_damage * profile.damage_multiplier
	var damage_range := profile.get_authored_damage_range()
	var damage_value := format_number(configured_damage)
	if not is_equal_approx(damage_range.x, damage_range.y):
		damage_value += " (%s–%s)" % [format_number(damage_range.x), format_number(damage_range.y)]
	lines.append("%s: %s" % [String(profile.damage_type.id).capitalize(), highlight(damage_value)])
	lines.append("Reach: %s" % highlight(format_number(profile.reach)))
	lines.append("Cooldown: %s" % highlight("%ss" % format_number(profile.cooldown)))
	lines.append("Sweep: %s" % highlight("%s°" % format_number(profile.sweep_degrees)))
	lines.append("Knockback: %s" % highlight(format_number(profile.knockback_speed)))
	lines.append("Sneak Damage: %s" % highlight("%sx" % format_number(profile.sneak_damage_multiplier)))
	return lines

static func get_bow_stat_lines(item_definition: ItemDefinition) -> Array[String]:
	assert(item_definition != null)
	var bow_action := item_definition.primary_action as BowDrawActionDefinition
	if bow_action == null:
		return []
	var sneak_damage_multiplier := 1.0
	if not bow_action.ammunition.is_empty():
		sneak_damage_multiplier = bow_action.ammunition[0].projectile_profile.sneak_damage_multiplier
	return [
		"Draw Time: %s" % highlight("%ss" % format_number(bow_action.draw_seconds)),
		"Sneak Damage: %s" % highlight("%sx" % format_number(sneak_damage_multiplier)),
	]

static func get_arrow_stat_lines(item_definition: ItemDefinition) -> Array[String]:
	assert(item_definition != null)
	var arrow := item_definition as ArrowItemDefinition
	if arrow == null:
		return []
	var profile := arrow.projectile_profile
	return [
		"%s: %s" % [String(profile.damage_type.id).capitalize(), highlight(format_number(profile.base_damage))],
		"Knockback: %s" % highlight(format_number(profile.knockback_speed)),
	]

static func get_pickaxe_stat_lines(item_definition: ItemDefinition) -> Array[String]:
	assert(item_definition != null)
	var lines: Array[String] = []
	var mining_action := item_definition.primary_action as MiningActionDefinition
	if mining_action == null:
		return lines
	var pickaxe_stat := mining_action.get_tool_stat(&"pickaxe")
	if pickaxe_stat == null:
		return lines
	lines.append("Mining Power: %s" % highlight(format_number(pickaxe_stat.power)))
	lines.append("Speed Multiplier: %s" % highlight("%sx" % format_number(pickaxe_stat.speed_multiplier)))
	return lines

static func get_consumable_stat_lines(item_definition: ItemDefinition) -> Array[String]:
	assert(item_definition != null)
	var lines: Array[String] = []
	var consumable_action := item_definition.secondary_action as ConsumableActionDefinition
	if consumable_action == null:
		return lines
	var restored_health := consumable_action.health_restore_fraction * 100.0
	lines.append("Health: %s" % highlight("+%s" % format_number(restored_health)))
	return lines

static func get_modifier_stat_lines(modifiers: Array[StatModifier]) -> Array[String]:
	var lines: Array[String] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		var stat_name := "HP" if modifier.stat_id == &"hp" else String(modifier.stat_id).capitalize()
		if modifier.operation == StatModifier.Operation.ADD:
			var sign := "+" if modifier.amount >= 0.0 else ""
			lines.append("%s: %s" % [stat_name, highlight("%s%s" % [sign, format_number(modifier.amount)])])
		else:
			lines.append("%s: %s" % [stat_name, highlight("x%s" % format_number(modifier.amount))])
	return lines

static func highlight(value: String) -> String:
	return "[b][color=#%s]%s[/color][/b]" % [CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false), value]

static func format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.left(text.length() - 1)
	return text
