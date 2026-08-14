extends SceneTree

class TestStatsDefinition extends ActorStatsDefinition:
	var base_stats: Dictionary

	func get_base_stats() -> Dictionary:
		return base_stats

var _errors: Array[String] = []

func _init():
	var player_definition := load("res://player/player_stats.tres") as ActorStatsDefinition
	_expect(player_definition.validate(), "player stats definition is invalid")
	_expect(player_definition is CombatStatsDefinition, "player stats do not extend the shared combat definition")
	var combat_definition := CombatStatsDefinition.new()
	_expect(combat_definition.validate(), "default combat stats definition is invalid")
	_expect(is_equal_approx(combat_definition.get_base_stats()[&"hp"], 100.0), "combat HP is missing")
	_expect(is_equal_approx(combat_definition.get_base_stats()[&"defense"], 0.0), "combat defense is missing")
	_expect(is_equal_approx(combat_definition.get_base_stats()[&"strength"], 10.0), "combat strength is missing")
	var player_validation := PlayerStatsDefinition.new()
	player_validation.mobility = NAN
	_expect(not player_validation.validate(), "non-finite player-only stat passed definition validation")
	player_validation.mobility = 10.0
	player_validation.resilience = -1.0
	_expect(not player_validation.validate(), "negative player-only stat passed definition validation")
	combat_definition.maximum_hp = 0.0
	_expect(not combat_definition.validate(), "zero maximum HP passed combat stats validation")
	combat_definition.maximum_hp = 100.0
	combat_definition.defense = -1.0
	_expect(not combat_definition.validate(), "negative defense passed combat stats validation")
	combat_definition.defense = 0.0
	combat_definition.strength = -1.0
	_expect(not combat_definition.validate(), "negative strength passed combat stats validation")
	var stats := ActorStats.new(player_definition)
	_expect(stats.has_stat(&"strength"), "player strength is missing")
	_expect(not stats.has_stat(&"fire_power"), "player unexpectedly has an enemy-specific stat")
	var sword_add := _modifier(&"sword_strength", &"copper_sword", &"strength", StatModifier.Operation.ADD, 5.0)
	var potion_multiply := _modifier(&"strength_potion", &"strength_potion", &"strength", StatModifier.Operation.MULTIPLY, 1.5, 2.0)
	_expect(stats.add_modifier(sword_add), "permanent modifier was rejected")
	_expect(stats.add_modifier(potion_multiply), "timed modifier was rejected")
	_expect(not stats.add_modifier(sword_add), "duplicate modifier ID was accepted")
	_expect(is_equal_approx(stats.get_value(&"strength"), 22.5), "additive and multiplicative modifiers were not combined")
	stats.advance_time(2.0)
	_expect(not stats.has_modifier(&"strength_potion"), "timed modifier did not expire")
	_expect(is_equal_approx(stats.get_value(&"strength"), 15.0), "expired modifier still affects stats")
	var armor_add := _modifier(&"armor_strength", &"copper_armor", &"strength", StatModifier.Operation.ADD, 2.0, 0.0, &"armor_instance_1")
	var armor_multiply := _modifier(&"armor_strength_scale", &"copper_armor", &"strength", StatModifier.Operation.MULTIPLY, 1.1, 0.0, &"armor_instance_1")
	_expect(stats.add_modifier(armor_add) and stats.add_modifier(armor_multiply), "item modifiers were rejected")
	_expect(stats.remove_modifiers_from_source_instance(&"armor_instance_1") == 2, "item modifiers were not removed by instance")
	var equipment_stats := ActorStats.new(player_definition)
	var equipment_defense := _modifier(&"template_defense", &"copper_helmet", &"defense", StatModifier.Operation.ADD, 2.0)
	var equipment_modifiers: Array[StatModifier] = [equipment_defense]
	_expect(equipment_stats.can_replace_source_modifiers(&"copper_helmet", &"equipment_slot_0", equipment_modifiers), "valid equipment modifiers failed preflight")
	_expect(equipment_stats.replace_source_modifiers(&"copper_helmet", &"equipment_slot_0", equipment_modifiers), "valid equipment modifiers failed replacement")
	_expect(is_equal_approx(equipment_stats.get_value(&"defense"), 2.0), "equipment modifier was not applied")
	var invalid_equipment := _modifier(&"invalid_template", &"broken_helmet", &"unknown_stat", StatModifier.Operation.ADD, 5.0)
	var invalid_equipment_modifiers: Array[StatModifier] = [invalid_equipment]
	_expect(not equipment_stats.can_replace_source_modifiers(&"broken_helmet", &"equipment_slot_0", invalid_equipment_modifiers), "invalid equipment modifiers passed preflight")
	_expect(not equipment_stats.replace_source_modifiers(&"broken_helmet", &"equipment_slot_0", invalid_equipment_modifiers), "invalid equipment modifiers replaced valid state")
	_expect(is_equal_approx(equipment_stats.get_value(&"defense"), 2.0), "failed equipment replacement changed stats")
	_expect(equipment_stats.remove_modifiers_from_source_instance(&"equipment_slot_0") == 1, "equipment modifier removal count changed")
	_expect(is_equal_approx(equipment_stats.get_value(&"defense"), 0.0), "equipment modifier removal did not restore base defense")
	var replacement_hp_stats := ActorStats.new(player_definition)
	var maximum_hp_modifier := _modifier(&"template_hp", &"health_armor", &"hp", StatModifier.Operation.MULTIPLY, 2.0)
	var maximum_hp_modifiers: Array[StatModifier] = [maximum_hp_modifier]
	_expect(replacement_hp_stats.replace_source_modifiers(&"health_armor", &"equipment_slot_0", maximum_hp_modifiers), "maximum HP modifier failed replacement")
	_expect(replacement_hp_stats.set_current_hp(150.0), "modified current HP setup failed")
	_expect(replacement_hp_stats.replace_source_modifiers(&"health_armor", &"equipment_slot_0", maximum_hp_modifiers), "maximum HP modifier refresh failed")
	_expect(is_equal_approx(replacement_hp_stats.current_hp, 150.0), "equivalent modifier replacement clamped current HP")
	var ratio_hp_stats := ActorStats.new(player_definition)
	var additive_hp_modifier := _modifier(&"ratio_hp", &"health_rune", &"hp", StatModifier.Operation.ADD, 100.0)
	var additive_hp_modifiers: Array[StatModifier] = [additive_hp_modifier]
	var no_hp_modifiers: Array[StatModifier] = []
	_expect(ratio_hp_stats.set_current_hp(37.0), "health-ratio current HP setup failed")
	_expect(ratio_hp_stats.replace_source_modifiers_preserving_health_ratio(&"health_rune", &"socketed_runes", additive_hp_modifiers), "health-ratio modifier failed replacement")
	_expect(is_equal_approx(ratio_hp_stats.get_value(&"hp"), 200.0), "health-ratio maximum HP did not increase")
	_expect(is_equal_approx(ratio_hp_stats.current_hp, 74.0), "health percentage was not preserved when maximum HP increased")
	_expect(ratio_hp_stats.replace_source_modifiers_preserving_health_ratio(&"health_rune", &"socketed_runes", no_hp_modifiers), "health-ratio modifier failed removal")
	_expect(is_equal_approx(ratio_hp_stats.get_value(&"hp"), 100.0), "health-ratio maximum HP did not restore")
	_expect(is_equal_approx(ratio_hp_stats.current_hp, 37.0), "health percentage was not preserved when maximum HP decreased")
	_expect(player_definition.get_experience_requirement(1) == 100, "level-one experience requirement changed")
	_expect(player_definition.get_experience_requirement(2) == 125, "level-two experience requirement is not linear")
	_expect(player_definition.get_experience_requirement(3) == 150, "level-three experience requirement is not linear")
	var invalid_experience_increase := _definition({&"strength": 10.0})
	invalid_experience_increase.experience_increase_per_level = -1
	_expect(not invalid_experience_increase.validate(), "negative experience increase passed definition validation")
	var leveled_definition := _definition({&"strength": 10.0}, 1, 100, 100, 4)
	_expect(leveled_definition.validate(), "leveled definition is invalid")
	var leveled_stats := ActorStats.new(leveled_definition)
	_expect(leveled_stats.add_experience(350) == 2, "experience did not support multiple level-ups")
	_expect(leveled_stats.level == 3 and leveled_stats.experience == 50, "level or carried experience is incorrect")
	_expect(leveled_stats.get_total_experience() == 350, "total experience did not include completed levels")
	_expect(is_equal_approx(leveled_stats.get_value(&"strength"), 10.0), "level unexpectedly changed stats")
	var overflow_safe_definition := _definition({&"strength": 10.0}, 1, 100, 0, 2)
	_expect(overflow_safe_definition.validate(), "overflow-safe definition is invalid")
	var overflow_safe_stats := ActorStats.new(overflow_safe_definition)
	_expect(overflow_safe_stats.add_experience(9_223_372_036_854_775_807) == 1, "maximum integer experience overflowed")
	_expect(overflow_safe_stats.level == 2 and overflow_safe_stats.experience == 0, "maximum integer experience corrupted progression")
	var progression := leveled_stats.snapshot_progression()
	var restored_stats := ActorStats.new(leveled_definition)
	_expect(restored_stats.restore_progression(progression), "valid progression did not restore")
	_expect(restored_stats.level == 3 and restored_stats.experience == 50, "restored progression changed")
	var hp_stats := ActorStats.new(player_definition)
	var depletion_count: Array[int] = [0]
	hp_stats.health_depleted.connect(func(): depletion_count[0] += 1)
	_expect(not hp_stats.is_dead(), "new actor stats started dead")
	_expect(is_equal_approx(hp_stats.damage(30.0), 30.0), "damage did not change runtime HP")
	_expect(is_equal_approx(hp_stats.current_hp, 70.0), "runtime HP is incorrect after damage")
	_expect(is_equal_approx(hp_stats.heal(100.0), 30.0), "healing did not clamp to maximum HP")
	_expect(is_equal_approx(hp_stats.damage(100.0), 100.0), "exact lethal damage was not applied")
	_expect(hp_stats.is_dead() and depletion_count[0] == 1, "lethal damage did not emit one health depletion")
	_expect(is_equal_approx(hp_stats.damage(50.0), 0.0), "damage changed HP below zero")
	_expect(hp_stats.is_dead() and depletion_count[0] == 1, "dead actor emitted repeated health depletion")
	_expect(is_equal_approx(hp_stats.heal(1.0), 1.0), "dead actor could not be healed")
	_expect(not hp_stats.is_dead(), "positive HP actor remained dead")
	_expect(hp_stats.set_current_hp(0.0) and depletion_count[0] == 2, "direct lethal HP did not emit health depletion")
	_expect(hp_stats.set_current_hp(0.0) and depletion_count[0] == 2, "repeated zero HP emitted health depletion")
	_expect(hp_stats.heal(1.0), "direct-death actor could not be healed")
	_expect(hp_stats.restore_progression({"level": 1, "experience": 0, "current_hp": 0.0}) and depletion_count[0] == 3, "restored lethal HP did not emit health depletion")
	_expect(not hp_stats.set_current_hp(NAN), "non-finite current HP was accepted")
	_expect(not hp_stats.set_base_value(&"strength", INF), "non-finite base stat was accepted")
	var invalid_amount := _modifier(&"invalid_amount", &"invalid_item", &"strength", StatModifier.Operation.ADD, NAN)
	var invalid_duration := _modifier(&"invalid_duration", &"invalid_item", &"strength", StatModifier.Operation.ADD, 1.0, INF)
	_expect(not hp_stats.add_modifier(invalid_amount), "non-finite modifier amount was accepted")
	_expect(not hp_stats.add_modifier(invalid_duration), "non-finite modifier duration was accepted")
	var invalid_strength := _modifier(&"invalid_strength", &"invalid_item", &"strength", StatModifier.Operation.ADD, -11.0)
	var invalid_hp := _modifier(&"invalid_hp", &"invalid_item", &"hp", StatModifier.Operation.ADD, -100.0)
	_expect(not hp_stats.add_modifier(invalid_strength), "negative effective strength was accepted")
	_expect(not hp_stats.add_modifier(invalid_hp), "zero effective maximum HP was accepted")
	var masked_stats := ActorStats.new(player_definition)
	var zero_strength := _modifier(&"zero_strength", &"zero_potion", &"strength", StatModifier.Operation.MULTIPLY, 0.0, 1.0)
	var masked_negative_strength := _modifier(&"masked_negative_strength", &"broken_item", &"strength", StatModifier.Operation.ADD, -11.0)
	var masked_overflow_strength := _modifier(&"masked_overflow_strength", &"broken_item", &"strength", StatModifier.Operation.MULTIPLY, 1.0e308)
	_expect(masked_stats.add_modifier(zero_strength), "valid timed zero multiplier was rejected")
	_expect(not masked_stats.add_modifier(masked_negative_strength), "zero multiplier masked an invalid additive subset")
	_expect(not masked_stats.add_modifier(masked_overflow_strength), "zero multiplier masked a non-finite multiplicative subset")
	masked_stats.advance_time(1.0)
	_expect(not masked_stats.has_modifier(&"zero_strength"), "independent timed multiplier did not expire")
	_expect(is_equal_approx(masked_stats.get_value(&"strength"), 10.0), "timed multiplier expiration did not restore base strength")
	var isolated_stats := ActorStats.new(player_definition)
	var copied_modifier := _modifier(&"copied_strength", &"copied_item", &"strength", StatModifier.Operation.ADD, 1.0)
	_expect(isolated_stats.add_modifier(copied_modifier), "valid copied modifier was rejected")
	copied_modifier.amount = 1000.0
	_expect(is_equal_approx(isolated_stats.get_value(&"strength"), 11.0), "external modifier mutation changed runtime stats")
	var first_large_modifier := _modifier(&"large_strength_1", &"large_item", &"strength", StatModifier.Operation.ADD, 1.0e308)
	var overflowing_modifier := _modifier(&"large_strength_2", &"large_item", &"strength", StatModifier.Operation.ADD, 1.0e308)
	_expect(isolated_stats.add_modifier(first_large_modifier), "finite large modifier was rejected")
	_expect(not isolated_stats.add_modifier(overflowing_modifier), "overflowing aggregate modifier was accepted")
	_expect(not isolated_stats.has_modifier(&"large_strength_2") and is_finite(isolated_stats.get_value(&"strength")), "failed modifier transaction changed runtime stats")
	var enemy_definition := _definition({&"fire_power": 25.0})
	_expect(enemy_definition.validate(), "enemy-specific definition is invalid")
	var enemy_stats := ActorStats.new(enemy_definition)
	_expect(enemy_stats.has_stat(&"fire_power") and not enemy_stats.has_stat(&"recovery"), "enemy-specific stat set was not preserved")
	_expect(is_equal_approx(enemy_stats.get_value(&"fire_power"), 25.0), "enemy-specific stat value is incorrect")
	var invalid_modifier := _modifier(&"invalid_recovery", &"recovery_potion", &"recovery", StatModifier.Operation.ADD, 5.0)
	_expect(not enemy_stats.add_modifier(invalid_modifier), "modifier created a stat absent from the actor definition")
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var test_totem := item_catalog.get_definition(&"test_totem")
	_expect(test_totem.stat_modifiers.size() == 3, "test totem modifiers are missing")
	var equipped_stats := ActorStats.new(player_definition)
	_expect(equipped_stats.replace_source_modifiers(test_totem.id, &"test_totem_instance", test_totem.stat_modifiers), "test totem modifiers were rejected")
	_expect(is_equal_approx(equipped_stats.get_value(&"strength"), 20.0), "test totem strength modifier is incorrect")
	_expect(is_equal_approx(equipped_stats.get_value(&"mobility"), 5.0), "test totem mobility modifier is incorrect")
	_expect(is_equal_approx(equipped_stats.get_value(&"hp"), 200.0), "test totem health multiplier is incorrect")
	_expect(is_equal_approx(equipped_stats.current_hp, 100.0), "maximum health modifier unexpectedly healed the actor")
	if _errors.is_empty():
		print("Stats system tests passed")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _definition(base_stats: Dictionary, starting_level: int = 1, base_experience: int = 100, experience_increase: int = 25, maximum_level: int = 0) -> ActorStatsDefinition:
	var definition := TestStatsDefinition.new()
	definition.base_stats = base_stats
	definition.starting_level = starting_level
	definition.base_experience_to_level = base_experience
	definition.experience_increase_per_level = experience_increase
	definition.maximum_level = maximum_level
	return definition

func _modifier(id: StringName, source_id: StringName, stat_id: StringName, operation: StatModifier.Operation, amount: float, duration_seconds: float = 0.0, source_instance_id: StringName = &"") -> StatModifier:
	var modifier := StatModifier.new()
	modifier.id = id
	modifier.source_id = source_id
	modifier.source_instance_id = source_instance_id
	modifier.stat_id = stat_id
	modifier.operation = operation
	modifier.amount = amount
	modifier.duration_seconds = duration_seconds
	return modifier

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
