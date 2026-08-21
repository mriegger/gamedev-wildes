extends RefCounted
class_name DamageAffinityTextFormatter

static func build_enemy_sentence(
	definition: EntityDefinition,
	prefix: String,
	repeat_damage_word: bool,
) -> String:
	assert(definition != null)
	var weak_types := get_damage_type_ids(definition, DamageAffinityDefinition.Response.WEAK)
	var resistant_types := get_damage_type_ids(definition, DamageAffinityDefinition.Response.RESISTANT)
	var details: Array[String] = []
	if not resistant_types.is_empty():
		var suffix := " damage" if repeat_damage_word or weak_types.is_empty() else ""
		details.append("resistant to %s%s" % [_colored_type_list(resistant_types, DamageAffinityDefinition.Response.RESISTANT), suffix])
	if not weak_types.is_empty():
		details.append("weak to %s damage" % _colored_type_list(weak_types, DamageAffinityDefinition.Response.WEAK))
	var description := ""
	if details.size() == 2:
		description = "%s, but %s" % [details[0], details[1]]
	elif not details.is_empty():
		description = details[0]
	assert(not description.is_empty())
	return "%s%s are %s." % [prefix, pluralize_name(String(definition.id).capitalize()), description]

static func get_damage_type_ids(definition: EntityDefinition, response: int) -> Array[StringName]:
	assert(definition != null and DamageAffinityDefinition.is_valid_response(response))
	var type_ids: Array[StringName] = []
	for affinity in definition.damage_affinities:
		if affinity.response == response:
			type_ids.append(affinity.damage_type.id)
	return type_ids

static func pluralize_name(name: String) -> String:
	if name.ends_with("y") and name.length() > 1 and name.substr(name.length() - 2, 1).to_lower() not in ["a", "e", "i", "o", "u"]:
		return name.substr(0, name.length() - 1) + "ies"
	if name.ends_with("s") or name.ends_with("x") or name.ends_with("z") or name.ends_with("ch") or name.ends_with("sh"):
		return name + "es"
	return name + "s"

static func _colored_type_list(type_ids: Array[StringName], response: int) -> String:
	var terms: Array[String] = []
	for type_id in type_ids:
		terms.append(_colored_damage_type(type_id, response))
	return _join_terms(terms)

static func _colored_damage_type(damage_type_id: StringName, response: int) -> String:
	var color := CombatPresentationPalette.WEAK_DAMAGE_COLOR
	if response == DamageAffinityDefinition.Response.RESISTANT:
		color = CombatPresentationPalette.RESISTANT_DAMAGE_COLOR
	return "[b][color=#%s]%s[/color][/b]" % [color.to_html(false), String(damage_type_id)]

static func _join_terms(terms: Array[String]) -> String:
	if terms.size() <= 1:
		return terms[0] if not terms.is_empty() else ""
	if terms.size() == 2:
		return "%s and %s" % [terms[0], terms[1]]
	return "%s, and %s" % [", ".join(terms.slice(0, terms.size() - 1)), terms.back()]
