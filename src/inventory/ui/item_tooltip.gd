extends PanelContainer
class_name ItemTooltip

const RUNE_BONUS_COLOR: Color = Color(0.96, 0.28, 0.26, 1.0)

var _item_definition: ItemDefinition
var _item_proficiency: ItemProficiency
var _item_catalog: ItemCatalog
var _socketed_rune_ids: Array[StringName] = []
var _displayed_level: int = -1
var _displayed_experience: float = -1.0

@onready var icon: TextureRect = $Margin/Content/Header/Icon
@onready var item_name_label: Label = $Margin/Content/Header/Identity/ItemName
@onready var rarity_label: Label = $Margin/Content/Header/Identity/Rarity
@onready var proficiency_level_label: Label = $Margin/Content/ProficiencyLevel
@onready var proficiency_experience_label: Label = $Margin/Content/ProficiencyExperience
@onready var stats_label: Label = $Margin/Content/Stats
@onready var rune_stats_label: Label = $Margin/Content/RuneStats

func setup(
	item_definition: ItemDefinition,
	item_proficiency: ItemProficiency,
	item_catalog: ItemCatalog,
	socketed_rune_ids: Array[StringName] = [],
) -> void:
	assert(item_definition != null)
	assert(item_definition.rarity != null)
	assert(item_proficiency != null)
	assert(item_catalog != null)
	assert(item_definition is RuneDefinition or item_definition.proficiency != null)
	assert(item_definition is RuneDefinition or item_proficiency.has_proficiency(item_definition.id))
	_item_definition = item_definition
	_item_proficiency = item_proficiency
	_item_catalog = item_catalog
	_socketed_rune_ids = socketed_rune_ids.duplicate()
	if is_node_ready():
		_refresh()
		set_process(_has_proficiency())

func _ready() -> void:
	rune_stats_label.add_theme_color_override(&"font_color", RUNE_BONUS_COLOR)
	_refresh()
	set_process(_has_proficiency())

func _process(_delta: float) -> void:
	if not _has_proficiency():
		set_process(false)
		return
	var level := _item_proficiency.get_level(_item_definition.id)
	var experience := _item_proficiency.get_experience(_item_definition.id)
	if level != _displayed_level or not is_equal_approx(experience, _displayed_experience):
		_refresh()

func _refresh() -> void:
	if _item_definition == null or _item_proficiency == null or _item_catalog == null:
		return
	icon.texture = _item_definition.icon
	item_name_label.text = _item_definition.display_name
	rarity_label.text = _item_definition.rarity.display_name
	rarity_label.add_theme_color_override("font_color", _item_definition.rarity.display_color)
	var has_proficiency := _has_proficiency()
	proficiency_level_label.visible = has_proficiency
	proficiency_experience_label.visible = has_proficiency
	if has_proficiency:
		_refresh_proficiency()
	stats_label.text = "\n".join(_get_stat_lines())
	var rune_stat_lines := _get_socketed_rune_stat_lines()
	rune_stats_label.text = "\n".join(rune_stat_lines)
	rune_stats_label.visible = not rune_stat_lines.is_empty()

func _refresh_proficiency() -> void:
	var level := _item_proficiency.get_level(_item_definition.id)
	var experience := _item_proficiency.get_experience(_item_definition.id)
	_displayed_level = level
	_displayed_experience = experience
	var maximum_level := _item_definition.proficiency.maximum_level
	proficiency_level_label.text = "Proficiency Level %d / %d" % [level, maximum_level]
	if _item_proficiency.is_at_maximum_level(_item_definition.id):
		proficiency_experience_label.text = "Proficiency XP: Max"
	else:
		proficiency_experience_label.text = "Proficiency XP: %s / %s" % [
			_format_number(experience),
			_format_number(_item_proficiency.get_experience_to_next_level(_item_definition.id)),
		]

func _has_proficiency() -> bool:
	return (
		_item_definition != null
		and _item_definition.proficiency != null
		and _item_proficiency != null
		and _item_proficiency.has_proficiency(_item_definition.id)
	)

func _get_stat_lines() -> Array[String]:
	var lines: Array[String] = []
	var rune := _item_definition as RuneDefinition
	if rune != null:
		lines.append(_get_rune_compatibility_line(rune))
		lines.append_array(_get_modifier_stat_lines(rune.socket_modifiers))
		return lines
	var armor := _item_definition as ArmorDefinition
	if armor != null:
		lines.append("Slot: %s" % ArmorDefinition.get_slot_label(armor.armor_slot))
	var melee_action := _item_definition.primary_action as MeleeAttackActionDefinition
	if melee_action != null:
		var profile := melee_action.attack_profile
		lines.append("Base Damage: %s" % _format_number(profile.base_damage * profile.damage_multiplier))
		lines.append("Reach: %s" % _format_number(profile.reach))
		lines.append("Cooldown: %ss" % _format_number(profile.cooldown))
		lines.append("Sweep: %s°" % _format_number(profile.sweep_degrees))
	lines.append_array(_get_modifier_stat_lines(_item_definition.stat_modifiers))
	return lines

func _get_modifier_stat_lines(modifiers: Array[StatModifier]) -> Array[String]:
	var lines: Array[String] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		var stat_name := _get_stat_display_name(modifier.stat_id)
		if modifier.operation == StatModifier.Operation.ADD:
			var sign := "+" if modifier.amount >= 0.0 else ""
			lines.append("%s: %s%s" % [stat_name, sign, _format_number(modifier.amount)])
		else:
			lines.append("%s: x%s" % [stat_name, _format_number(modifier.amount)])
	return lines

func _get_socketed_rune_stat_lines() -> Array[String]:
	var additive_by_stat: Dictionary = {}
	var multiplier_by_stat: Dictionary = {}
	for rune_id in _socketed_rune_ids:
		if rune_id.is_empty():
			continue
		var rune := _item_catalog.get_definition(rune_id) as RuneDefinition
		for modifier in rune.socket_modifiers:
			if modifier.operation == StatModifier.Operation.ADD:
				additive_by_stat[modifier.stat_id] = float(additive_by_stat.get(modifier.stat_id, 0.0)) + modifier.amount
			else:
				multiplier_by_stat[modifier.stat_id] = float(multiplier_by_stat.get(modifier.stat_id, 1.0)) * modifier.amount
	var stat_ids: Array[StringName] = []
	for stat_id in additive_by_stat:
		stat_ids.append(stat_id)
	for stat_id in multiplier_by_stat:
		if not stat_ids.has(stat_id):
			stat_ids.append(stat_id)
	stat_ids.sort()
	var lines: Array[String] = []
	for stat_id in stat_ids:
		var stat_name := _get_stat_display_name(stat_id)
		if additive_by_stat.has(stat_id):
			var amount := float(additive_by_stat[stat_id])
			var sign := "+" if amount >= 0.0 else ""
			lines.append("(%s%s %s)" % [sign, _format_number(amount), stat_name])
		if multiplier_by_stat.has(stat_id):
			lines.append("(x%s %s)" % [_format_number(float(multiplier_by_stat[stat_id])), stat_name])
	return lines

func _get_rune_compatibility_line(rune: RuneDefinition) -> String:
	var targets: Array[String] = []
	var armor_type := _item_catalog.get_equipment_type(&"armor")
	for compatible_type in rune.compatible_equipment_types:
		if not compatible_type.overlaps_branch(armor_type):
			targets.append(compatible_type.display_name)
			continue
		var armor_slots: Array[String] = []
		for armor_slot in range(ArmorDefinition.SLOT_COUNT):
			if (rune.compatible_armor_slots & (1 << armor_slot)) != 0:
				armor_slots.append(ArmorDefinition.get_slot_label(armor_slot))
		if compatible_type == armor_type:
			if rune.compatible_armor_slots == RuneDefinition.ALL_ARMOR_SLOTS:
				targets.append("All Armor")
			else:
				for armor_slot in armor_slots:
					targets.append("%s Armor" % armor_slot)
		elif compatible_type.is_or_inherits(armor_type):
			if rune.compatible_armor_slots == RuneDefinition.ALL_ARMOR_SLOTS:
				targets.append("All %s" % compatible_type.display_name)
			else:
				targets.append("%s (%s)" % [compatible_type.display_name, ", ".join(armor_slots)])
		elif rune.compatible_armor_slots == RuneDefinition.ALL_ARMOR_SLOTS:
			targets.append(compatible_type.display_name)
		else:
			targets.append("%s (Armor: %s)" % [compatible_type.display_name, ", ".join(armor_slots)])
	return "Compatible: %s" % ", ".join(targets)

func _get_stat_display_name(stat_id: StringName) -> String:
	return "HP" if stat_id == &"hp" else String(stat_id).capitalize()

func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.left(text.length() - 1)
	return text
