extends SceneTree

class TestStatsDefinition extends ActorStatsDefinition:
	var base_stats: Dictionary

	func get_base_stats() -> Dictionary:
		return base_stats

var _errors: Array[String] = []

func _init():
	var player_definition := load("res://player/player_stats.tres") as ActorStatsDefinition
	_expect(player_definition.validate(), "player stats definition is invalid")
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
	_expect(stats.remove_modifiers_from_item_instance(&"armor_instance_1") == 2, "item modifiers were not removed by instance")
	var leveled_definition := _definition({&"strength": 10.0}, 1, 100, 2.0, 4)
	_expect(leveled_definition.validate(), "leveled definition is invalid")
	var leveled_stats := ActorStats.new(leveled_definition)
	_expect(leveled_stats.add_experience(350) == 2, "experience did not support multiple level-ups")
	_expect(leveled_stats.level == 3 and leveled_stats.experience == 50, "level or carried experience is incorrect")
	_expect(is_equal_approx(leveled_stats.get_value(&"strength"), 10.0), "level unexpectedly changed stats")
	var progression := leveled_stats.snapshot_progression()
	var restored_stats := ActorStats.new(leveled_definition)
	_expect(restored_stats.restore_progression(progression), "valid progression did not restore")
	_expect(restored_stats.level == 3 and restored_stats.experience == 50, "restored progression changed")
	var hp_stats := ActorStats.new(player_definition)
	_expect(is_equal_approx(hp_stats.damage(30.0), 30.0), "damage did not change runtime HP")
	_expect(is_equal_approx(hp_stats.current_hp, 70.0), "runtime HP is incorrect after damage")
	_expect(is_equal_approx(hp_stats.heal(100.0), 30.0), "healing did not clamp to maximum HP")
	var enemy_definition := _definition({&"fire_power": 25.0})
	_expect(enemy_definition.validate(), "enemy-specific definition is invalid")
	var enemy_stats := ActorStats.new(enemy_definition)
	_expect(enemy_stats.has_stat(&"fire_power") and not enemy_stats.has_stat(&"recovery"), "enemy-specific stat set was not preserved")
	_expect(is_equal_approx(enemy_stats.get_value(&"fire_power"), 25.0), "enemy-specific stat value is incorrect")
	var invalid_modifier := _modifier(&"invalid_recovery", &"recovery_potion", &"recovery", StatModifier.Operation.ADD, 5.0)
	_expect(not enemy_stats.add_modifier(invalid_modifier), "modifier created a stat absent from the actor definition")
	if _errors.is_empty():
		print("Stats system tests passed")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _definition(base_stats: Dictionary, starting_level: int = 1, base_experience: int = 100, growth: float = 1.25, maximum_level: int = 0) -> ActorStatsDefinition:
	var definition := TestStatsDefinition.new()
	definition.base_stats = base_stats
	definition.starting_level = starting_level
	definition.base_experience_to_level = base_experience
	definition.experience_growth = growth
	definition.maximum_level = maximum_level
	return definition

func _modifier(id: StringName, source_item_id: StringName, stat_id: StringName, operation: StatModifier.Operation, amount: float, duration_seconds: float = 0.0, source_item_instance_id: StringName = &"") -> StatModifier:
	var modifier := StatModifier.new()
	modifier.id = id
	modifier.source_item_id = source_item_id
	modifier.source_item_instance_id = source_item_instance_id
	modifier.stat_id = stat_id
	modifier.operation = operation
	modifier.amount = amount
	modifier.duration_seconds = duration_seconds
	return modifier

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
