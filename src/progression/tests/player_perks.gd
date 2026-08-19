extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var stats_definition := load("res://player/player_stats.tres") as ActorStatsDefinition
	var rules := load("res://progression/player_perk_rules.tres") as PlayerPerkRules
	_expect(rules != null and rules.validate(stats_definition), "authored perk rules are invalid")
	var authored_definitions := rules.get_definitions()
	_expect(authored_definitions.map(func(definition: PlayerPerkDefinition): return definition.id) == [&"health", &"strength", &"defense"], "authored perk order changed")
	var perk_ids := rules.get_perk_ids()
	_expect(Array(perk_ids) == [&"defense", &"health", &"strength"], "authored perk IDs changed: %s" % [perk_ids])
	_expect(rules.first_award_level == 2, "first perk award level changed")
	_expect(rules.levels_per_award == 1, "perk award interval changed")
	_expect(rules.points_per_award == 1, "perk points per award changed")
	_expect(rules.get_earned_point_count(1) == 0, "level one earned a perk point")
	_expect(rules.get_earned_point_count(2) == 1, "level two did not earn the first perk point")
	_expect(rules.get_earned_point_count(5) == 4, "one-point-per-level cadence changed")
	_expect_definition(rules.get_definition(&"health"), &"hp", 10.0)
	_expect_definition(rules.get_definition(&"strength"), &"strength", 1.0)
	_expect_definition(rules.get_definition(&"defense"), &"defense", 1.0)

	var configurable_rules := PlayerPerkRules.new()
	configurable_rules.definitions = rules.definitions.duplicate()
	configurable_rules.first_award_level = 3
	configurable_rules.levels_per_award = 2
	configurable_rules.points_per_award = 2
	_expect(configurable_rules.validate(stats_definition), "configurable perk cadence is invalid")
	_expect(configurable_rules.get_earned_point_count(2) == 0, "points were awarded before the configured first level")
	_expect(configurable_rules.get_earned_point_count(3) == 2, "configured first award is incorrect")
	_expect(configurable_rules.get_earned_point_count(4) == 2, "points were awarded between configured intervals")
	_expect(configurable_rules.get_earned_point_count(5) == 4, "configured recurring award is incorrect")

	var duplicate_rules := PlayerPerkRules.new()
	duplicate_rules.definitions = [rules.get_definition(&"health"), rules.get_definition(&"health")]
	_expect(not duplicate_rules.validate(stats_definition), "duplicate perk IDs passed validation")
	var empty_rules := PlayerPerkRules.new()
	_expect(not empty_rules.validate(stats_definition), "empty perk catalog passed validation")

	var perks := PlayerPerks.new(rules)
	_expect(perks.snapshot() == {"allocations": {}}, "perks did not start with a sparse empty snapshot")
	_expect(perks.get_earned_point_count(1) == 0, "level-one entitlement changed")
	_expect(perks.get_unspent_point_count(1) == 0, "level one started with an unspent point")
	_expect(not perks.can_allocate(&"health", 1), "level one can allocate a perk")
	_expect(not perks.try_allocate(&"health", 1), "level-one perk allocation succeeded")
	_expect(not perks.try_allocate(&"missing", 5), "unknown perk allocation succeeded")
	_expect(perks.try_allocate(&"health", 5), "first health rank was rejected")
	_expect(perks.try_allocate(&"strength", 5), "first strength rank was rejected")
	_expect(perks.try_allocate(&"defense", 5), "first defense rank was rejected")
	_expect(perks.try_allocate(&"health", 5), "second health rank was rejected")
	_expect(perks.get_rank(&"health") == 2, "health rank changed after allocation")
	_expect(perks.get_spent_point_count() == 4, "spent point count is incorrect")
	_expect(perks.get_unspent_point_count(5) == 0, "spent points remained available")
	_expect(not perks.try_allocate(&"health", 5), "allocation succeeded without an unspent point")

	var saved := perks.snapshot()
	var saved_allocations := saved["allocations"] as Dictionary
	var saved_keys := saved_allocations.keys()
	_expect(saved_keys == ["defense", "health", "strength"], "snapshot perk IDs are not deterministic: %s" % [saved_keys])
	saved_allocations["health"] = 10
	_expect(perks.get_rank(&"health") == 2, "snapshot exposed mutable allocation state")
	saved = perks.snapshot()
	var decoded = JSON.parse_string(JSON.stringify(saved))
	_expect(typeof(decoded) == TYPE_DICTIONARY, "perk snapshot did not encode as plain values")
	var restored := PlayerPerks.new(rules)
	_expect(restored.restore(decoded as Dictionary, 5), "valid JSON perk snapshot did not restore")
	_expect(restored.snapshot() == saved, "restored perk snapshot changed")

	var replacement := {"allocations": {"health": 10, "strength": 1}}
	_expect(restored.restore(replacement, 12), "valid replacement perk snapshot was rejected")
	_expect(restored.get_rank(&"health") == 10, "maximum perk rank did not restore")
	_expect(restored.get_rank(&"strength") == 1, "replacement perk rank did not restore")
	_expect(restored.get_rank(&"defense") == 0, "omitted perk allocation was not cleared")
	_expect(not restored.can_allocate(&"health", 31), "maximum-rank perk can be allocated")

	_expect_rejected_unchanged(restored, {}, 12, "missing allocations field")
	_expect_rejected_unchanged(restored, {"allocations": {}, "extra": 1}, 12, "extra root field")
	_expect_rejected_unchanged(restored, {"allocations": []}, 12, "non-dictionary allocations")
	_expect_rejected_unchanged(restored, {"allocations": {1: 1}}, 12, "non-string perk ID")
	_expect_rejected_unchanged(restored, {"allocations": {"missing": 1}}, 12, "unknown perk ID")
	_expect_rejected_unchanged(restored, {"allocations": {"health": "1"}}, 12, "non-numeric rank")
	_expect_rejected_unchanged(restored, {"allocations": {"health": 1.5}}, 12, "fractional rank")
	_expect_rejected_unchanged(restored, {"allocations": {"health": NAN}}, 12, "non-finite rank")
	_expect_rejected_unchanged(restored, {"allocations": {"health": 0}}, 12, "zero rank")
	_expect_rejected_unchanged(restored, {"allocations": {"health": -1}}, 12, "negative rank")
	_expect_rejected_unchanged(restored, {"allocations": {"health": 11}}, 12, "rank above cap")
	_expect_rejected_unchanged(restored, {"allocations": {"health": 1, "strength": 1}}, 2, "overspent allocations")
	_expect_rejected_unchanged(restored, {"allocations": {"health": 1, "missing": 1}}, 12, "partially valid allocations")

	var actor_stats := ActorStats.new(stats_definition)
	_expect(actor_stats.set_progression(31, 0), "test player level was rejected")
	_expect(actor_stats.set_current_hp(50.0), "test health setup failed")
	var coordinated_perks := PlayerPerks.new(rules)
	var coordinator := PlayerPerkCoordinator.new()
	_expect(coordinator.setup(coordinated_perks, actor_stats), "perk coordinator setup failed")
	_expect(coordinator.get_earned_point_count() == 30, "coordinator did not derive points from player level")
	_expect(coordinator.get_unspent_point_count() == 30, "coordinator unspent point count is incorrect")
	_expect(coordinator.try_allocate(&"health"), "coordinated health allocation failed")
	_expect(is_equal_approx(actor_stats.get_value(&"hp"), 110.0), "health perk did not increase maximum HP")
	_expect(is_equal_approx(actor_stats.current_hp, 55.0), "health perk did not preserve current HP ratio")
	_expect(coordinator.try_allocate(&"strength"), "coordinated strength allocation failed")
	_expect(coordinator.try_allocate(&"defense"), "coordinated defense allocation failed")
	_expect(is_equal_approx(actor_stats.get_value(&"strength"), 11.0), "strength perk modifier is incorrect")
	_expect(is_equal_approx(actor_stats.get_value(&"defense"), 1.0), "defense perk modifier is incorrect")
	_expect(actor_stats.has_modifier(&"player_perks_0"), "perk modifiers did not use the bounded source instance")

	var before_restore_ratio := actor_stats.current_hp / actor_stats.get_value(&"hp")
	_expect(coordinator.restore({"allocations": {"health": 5, "strength": 2}}), "coordinated replacement restore failed")
	_expect(coordinator.get_rank(&"health") == 5 and coordinator.get_rank(&"strength") == 2, "coordinated restore changed ranks")
	_expect(coordinator.get_rank(&"defense") == 0, "coordinated restore retained an omitted rank")
	_expect(is_equal_approx(actor_stats.get_value(&"hp"), 150.0), "restored health ranks have the wrong effect")
	_expect(is_equal_approx(actor_stats.current_hp / actor_stats.get_value(&"hp"), before_restore_ratio), "coordinated restore changed current HP ratio")
	_expect(is_equal_approx(actor_stats.get_value(&"strength"), 12.0), "restored strength ranks have the wrong effect")
	_expect(is_zero_approx(actor_stats.get_value(&"defense")), "removed defense rank retained its modifier")
	var coordinated_before := coordinator.snapshot()
	var stats_before := _stat_snapshot(actor_stats)
	_expect(not coordinator.restore({"allocations": {"health": 11}}), "invalid coordinated restore succeeded")
	_expect(coordinator.snapshot() == coordinated_before, "invalid coordinated restore changed allocations")
	_expect(_stat_snapshot(actor_stats) == stats_before, "invalid coordinated restore changed stats")

	var invalid_definition := PlayerPerkDefinition.new()
	invalid_definition.id = &"invalid"
	invalid_definition.display_name = "Invalid"
	invalid_definition.stat_id = &"missing_stat"
	invalid_definition.amount_per_rank = 1.0
	invalid_definition.maximum_rank = 1
	var invalid_rules := PlayerPerkRules.new()
	invalid_rules.definitions = [invalid_definition]
	var invalid_perks := PlayerPerks.new(invalid_rules)
	var invalid_stats := ActorStats.new(stats_definition)
	_expect(invalid_stats.set_progression(2, 0), "invalid transaction test level was rejected")
	var invalid_coordinator := PlayerPerkCoordinator.new()
	_expect(invalid_coordinator.setup(invalid_perks, invalid_stats), "empty invalid-rule coordinator setup failed")
	_expect(not invalid_coordinator.try_allocate(&"invalid"), "invalid stat modifier allocation succeeded")
	_expect(invalid_perks.snapshot() == {"allocations": {}}, "failed modifier transaction retained an allocation")
	_expect(is_equal_approx(invalid_stats.get_value(&"hp"), 100.0), "failed modifier transaction changed actor stats")

	var rejected_stats := ActorStats.new(stats_definition)
	var rejected_perks := PlayerPerks.new(rules)
	var rejected_coordinator := PlayerPerkCoordinator.new()
	_expect(rejected_coordinator.setup(rejected_perks, rejected_stats), "rejected restore coordinator setup failed")
	var rejected_stats_before := _stat_snapshot(rejected_stats)
	var rejected_perks_before := rejected_perks.snapshot()
	_expect(not rejected_coordinator.restore_progression(
		{"level": 6, "experience": 10, "current_hp": 151.0},
		{"allocations": {"health": 5}},
	), "progression above perk-enhanced maximum HP restored")
	_expect(_stat_snapshot(rejected_stats) == rejected_stats_before, "rejected progression restore changed stats")
	_expect(rejected_perks.snapshot() == rejected_perks_before, "rejected progression restore changed perks")

	var restored_game := Game.new()
	restored_game.player_stats = ActorStats.new(stats_definition)
	restored_game.player_perks = PlayerPerks.new(rules)
	restored_game._save_data = {
		"player_stats": {"level": 6, "experience": 10, "current_hp": 125.0},
		"player_perks": {"allocations": {"health": 5}},
	}
	_expect(restored_game._restore_player_progression(), "game progression restore failed")
	_expect(restored_game.player_stats.level == 6 and restored_game.player_stats.experience == 10, "game restore changed saved level progress")
	_expect(restored_game.player_perk_coordinator.get_rank(&"health") == 5, "game restore lost health ranks")
	_expect(is_equal_approx(restored_game.player_stats.get_value(&"hp"), 150.0), "game restore did not apply perk maximum HP")
	_expect(is_equal_approx(restored_game.player_stats.current_hp, 125.0), "game restore did not preserve saved current HP")
	restored_game.free()

	if _errors.is_empty():
		print("PLAYER_PERKS PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect_definition(definition: PlayerPerkDefinition, stat_id: StringName, amount: float) -> void:
	_expect(definition.stat_id == stat_id, "%s targets the wrong stat" % definition.id)
	_expect(is_equal_approx(definition.amount_per_rank, amount), "%s has the wrong amount per rank" % definition.id)
	_expect(definition.maximum_rank == 10, "%s has the wrong maximum rank" % definition.id)

func _expect_rejected_unchanged(perks: PlayerPerks, saved_state: Dictionary, player_level: int, context: String) -> void:
	var before := perks.snapshot()
	_expect(not perks.restore(saved_state, player_level), "%s passed restore validation" % context)
	_expect(perks.snapshot() == before, "%s changed state after failed restore" % context)

func _stat_snapshot(stats: ActorStats) -> Dictionary:
	return {
		"hp": stats.get_value(&"hp"),
		"current_hp": stats.current_hp,
		"strength": stats.get_value(&"strength"),
		"defense": stats.get_value(&"defense"),
	}

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
