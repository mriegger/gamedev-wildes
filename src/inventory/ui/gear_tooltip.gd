extends PanelContainer
class_name GearTooltip

var _item_definition: ItemDefinition
var _item_proficiency: ItemProficiency
var _displayed_level: int = -1
var _displayed_experience: float = -1.0

@onready var icon: TextureRect = $Margin/Content/Header/Icon
@onready var item_name_label: Label = $Margin/Content/Header/Identity/ItemName
@onready var rarity_label: Label = $Margin/Content/Header/Identity/Rarity
@onready var proficiency_level_label: Label = $Margin/Content/ProficiencyLevel
@onready var proficiency_experience_label: Label = $Margin/Content/ProficiencyExperience
@onready var stats_label: Label = $Margin/Content/Stats

func setup(item_definition: ItemDefinition, item_proficiency: ItemProficiency) -> void:
	assert(item_definition != null)
	assert(item_definition.rarity != null)
	assert(item_definition.proficiency != null)
	assert(item_proficiency != null)
	assert(item_proficiency.has_proficiency(item_definition.id))
	_item_definition = item_definition
	_item_proficiency = item_proficiency
	if is_node_ready():
		_refresh()
		set_process(true)

func _ready() -> void:
	_refresh()
	set_process(_item_definition != null and _item_proficiency != null)

func _process(_delta: float) -> void:
	if _item_definition == null or _item_proficiency == null:
		set_process(false)
		return
	var level := _item_proficiency.get_level(_item_definition.id)
	var experience := _item_proficiency.get_experience(_item_definition.id)
	if level != _displayed_level or not is_equal_approx(experience, _displayed_experience):
		_refresh()

func _refresh() -> void:
	if _item_definition == null or _item_proficiency == null:
		return
	icon.texture = _item_definition.icon
	item_name_label.text = _item_definition.display_name
	rarity_label.text = _item_definition.rarity.display_name
	rarity_label.add_theme_color_override("font_color", _item_definition.rarity.display_color)
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
	stats_label.text = "\n".join(_get_stat_lines())

func _get_stat_lines() -> Array[String]:
	var lines: Array[String] = []
	var armor := _item_definition as ArmorDefinition
	if armor != null:
		lines.append("Slot: %s" % ArmorDefinition.get_slot_label(armor.armor_slot))
	var melee_action := _item_definition.primary_action as MeleeAttackActionDefinition
	if melee_action != null:
		var profile := melee_action.attack_profile
		lines.append("Base Damage: %s" % _format_number(profile.base_damage))
		lines.append("Reach: %s" % _format_number(profile.reach))
		lines.append("Cooldown: %ss" % _format_number(profile.cooldown))
		lines.append("Sweep: %s°" % _format_number(profile.sweep_degrees))
	for modifier in _item_definition.stat_modifiers:
		if modifier == null:
			continue
		var stat_name := String(modifier.stat_id).capitalize()
		if modifier.operation == StatModifier.Operation.ADD:
			var sign := "+" if modifier.amount >= 0.0 else ""
			lines.append("%s: %s%s" % [stat_name, sign, _format_number(modifier.amount)])
		else:
			lines.append("%s: x%s" % [stat_name, _format_number(modifier.amount)])
	return lines

func _format_number(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	var text := "%.2f" % value
	while text.ends_with("0"):
		text = text.left(text.length() - 1)
	return text
