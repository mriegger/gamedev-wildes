extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var common := _definition([10.0, 20.0, 30.0], [2])
	var rare := _definition([5.5, 10.0, 25.0], [0, 2])
	var epic := _definition([8.0, 16.0, 24.0, 32.0], [0, 2, 4])
	_expect(common.validate(), "common proficiency definition is invalid")
	_expect(rare.validate(), "rare proficiency definition is invalid")
	_expect(epic.validate(), "epic proficiency definition is invalid")
	_expect(common.maximum_level == 3, "maximum level does not follow the configured requirements")
	_expect(common.slot_unlock_levels.size() == 1, "common slot count is incorrect")
	_expect(common.get_unlocked_slot_count(0) == 0, "common slot started unlocked")
	_expect(common.get_unlocked_slot_count(2) == 1, "common slot did not unlock at its configured level")
	_expect(rare.get_unlocked_slot_count(0) == 1, "rare free slot is locked")
	_expect(rare.get_unlocked_slot_count(1) == 1, "locked rare slot unlocked too early")
	_expect(rare.get_unlocked_slot_count(2) == 2, "locked rare slot did not unlock")
	_expect(epic.get_unlocked_slot_count(4) == 3, "epic slots did not follow their configured levels")
	_expect(not _definition([], [0]).validate(), "empty experience requirements passed validation")
	_expect(not _definition([10.0], []).validate(), "empty slot unlock levels passed validation")
	_expect(not _definition([0.0], [0]).validate(), "zero experience requirement passed validation")
	_expect(not _definition([-1.0], [0]).validate(), "negative experience requirement passed validation")
	_expect(not _definition([NAN], [0]).validate(), "non-finite experience requirement passed validation")
	_expect(not _definition([10.0], [-1]).validate(), "negative slot unlock level passed validation")
	_expect(not _definition([10.0, 20.0], [2, 1]).validate(), "descending slot unlock levels passed validation")
	_expect(not _definition([10.0], [2]).validate(), "unreachable slot unlock level passed validation")
	_expect(not _definition([10.0], [0, 0, 0, 0]).validate(), "more than three rune slots passed validation")

	var common_sword := _item(&"common_sword", common)
	var rare_sword := _item(&"rare_sword", rare)
	var rare_helmet := _item(&"rare_helmet", rare)
	var epic_sword := _item(&"epic_sword", epic)
	var untracked_item := _item(&"untracked_item", null)
	var catalog := ItemCatalog.new()
	catalog.definitions = [common_sword, rare_sword, rare_helmet, epic_sword, untracked_item]
	_expect(rare_sword.proficiency == rare_helmet.proficiency, "shared proficiency definition was not preserved")

	var proficiency := ItemProficiency.new(catalog)
	_expect(proficiency.has_proficiency(&"common_sword"), "configured item has no proficiency")
	_expect(not proficiency.has_proficiency(&"untracked_item"), "unconfigured item gained proficiency")
	_expect(not proficiency.has_proficiency(&"missing_item"), "unknown item gained proficiency")
	_expect(proficiency.get_level(&"rare_sword") == 0, "item proficiency did not start at level zero")
	_expect(is_zero_approx(proficiency.get_experience(&"rare_sword")), "item proficiency did not start at zero experience")
	_expect(proficiency.get_unlocked_slot_count(&"rare_sword") == 1, "initially free item slot is locked")

	_expect(proficiency.add_experience(&"rare_sword", 5.25) == 0, "partial damage gained a level")
	_expect(is_equal_approx(proficiency.get_experience(&"rare_sword"), 5.25), "fractional damage was rounded")
	_expect(is_equal_approx(proficiency.get_experience_to_next_level(&"rare_sword"), 5.5), "configured level requirement changed")
	_expect(proficiency.add_experience(&"rare_sword", 0.25) == 1, "exact threshold did not gain a level")
	_expect(proficiency.get_level(&"rare_sword") == 1, "exact threshold produced the wrong level")
	_expect(is_zero_approx(proficiency.get_experience(&"rare_sword")), "exact threshold left an experience remainder")
	_expect(proficiency.add_experience(&"rare_sword", 12.75) == 1, "damage did not carry across a level")
	_expect(proficiency.get_level(&"rare_sword") == 2, "carried damage produced the wrong level")
	_expect(is_equal_approx(proficiency.get_experience(&"rare_sword"), 2.75), "carried damage produced the wrong remainder")
	_expect(proficiency.get_unlocked_slot_count(&"rare_sword") == 2, "item slot did not unlock with proficiency")

	_expect(proficiency.get_level(&"rare_helmet") == 0, "items sharing a definition shared mutable progress")
	_expect(proficiency.add_experience(&"rare_helmet", 5.5) == 1, "shared definition item used different thresholds")
	_expect(proficiency.get_level(&"rare_helmet") == 1, "shared definition item did not own independent progress")

	_expect(proficiency.add_experience(&"common_sword", 35.0) == 2, "multiple proficiency levels were not gained")
	_expect(proficiency.get_level(&"common_sword") == 2, "multiple level gain produced the wrong level")
	_expect(is_equal_approx(proficiency.get_experience(&"common_sword"), 5.0), "multiple level gain produced the wrong remainder")
	_expect(proficiency.get_unlocked_slot_count(&"common_sword") == 1, "common slot did not unlock at its configured threshold")
	_expect(proficiency.add_experience(&"common_sword", 100.0) == 1, "maximum proficiency level gain is incorrect")
	_expect(proficiency.is_at_maximum_level(&"common_sword"), "item did not reach maximum proficiency")
	_expect(is_zero_approx(proficiency.get_experience(&"common_sword")), "maximum proficiency retained an experience remainder")
	_expect(is_zero_approx(proficiency.get_experience_to_next_level(&"common_sword")), "maximum proficiency has a next requirement")
	var maximum_snapshot := proficiency.snapshot()
	_expect(proficiency.add_experience(&"common_sword", 1000.0) == 0, "maximum proficiency gained another level")
	_expect(proficiency.snapshot() == maximum_snapshot, "maximum proficiency changed after more damage")

	var saved := proficiency.snapshot()
	var saved_keys := saved.keys()
	_expect(saved_keys == ["common_sword", "rare_helmet", "rare_sword"], "snapshot item IDs are not deterministic: %s" % [saved_keys])
	(saved["rare_sword"] as Dictionary)["experience"] = 999.0
	_expect(is_equal_approx(proficiency.get_experience(&"rare_sword"), 2.75), "snapshot exposed mutable proficiency state")
	saved = proficiency.snapshot()
	var encoded := JSON.stringify(saved)
	var decoded = JSON.parse_string(encoded)
	_expect(typeof(decoded) == TYPE_DICTIONARY, "proficiency snapshot did not encode as plain values")
	var restored := ItemProficiency.new(catalog)
	_expect(restored.restore(decoded as Dictionary), "valid JSON proficiency snapshot did not restore")
	_expect(restored.snapshot() == saved, "restored proficiency snapshot changed")
	_expect(restored.get_level(&"rare_sword") == 2, "restored item level changed")
	_expect(is_equal_approx(restored.get_experience(&"rare_sword"), 2.75), "restored item experience changed")
	_expect(restored.get_level(&"epic_sword") == 0, "absent snapshot item did not retain default progress")

	var replacement := {
		"epic_sword": {
			"level": 1,
			"experience": 3.5,
		},
	}
	_expect(restored.restore(replacement), "valid replacement snapshot was rejected")
	_expect(restored.get_level(&"common_sword") == 0, "restore did not replace omitted item progress")
	_expect(restored.get_level(&"epic_sword") == 1, "replacement snapshot did not restore item progress")
	_expect(is_equal_approx(restored.get_experience(&"epic_sword"), 3.5), "replacement snapshot changed fractional experience")

	_expect_rejected_unchanged(restored, {"missing_item": {"level": 0, "experience": 0.0}}, "unknown item ID")
	_expect_rejected_unchanged(restored, {"untracked_item": {"level": 0, "experience": 0.0}}, "item without proficiency")
	_expect_rejected_unchanged(restored, {1: {"level": 0, "experience": 0.0}}, "non-string item ID")
	_expect_rejected_unchanged(restored, {"epic_sword": 1}, "non-dictionary progress")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 1}}, "missing experience")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 1, "experience": 0.0, "extra": 1}}, "extra progress field")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": "1", "experience": 0.0}}, "non-numeric level")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 1.5, "experience": 0.0}}, "fractional level")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": -1, "experience": 0.0}}, "negative level")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 5, "experience": 0.0}}, "level above maximum")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 1, "experience": NAN}}, "non-finite experience")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 1, "experience": -0.5}}, "negative experience")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 1, "experience": 16.0}}, "experience at next threshold")
	_expect_rejected_unchanged(restored, {"epic_sword": {"level": 4, "experience": 0.5}}, "maximum-level experience")
	_expect_rejected_unchanged(restored, {
		"common_sword": {"level": 1, "experience": 0.0},
		"epic_sword": {"level": 1, "experience": 16.0},
	}, "partially valid snapshot")

	var version_four_save := {"version": 4, "player_stats": {"level": 3, "experience": 5, "current_hp": 37.5}}
	_expect(SaveManager._migrate_save_data(version_four_save), "version-four save did not migrate")
	_expect(version_four_save["version"] == SaveManager.CURRENT_SAVE_VERSION, "migration did not update the save version")
	_expect(version_four_save["item_proficiency"] == {}, "migration did not initialize proficiency")
	_expect(version_four_save["pumpkin_patch"] == {"present": false}, "migration did not preserve older worlds without pumpkin patches")
	_expect(version_four_save["apple_trees"] == AppleTreeState.new().snapshot(), "migration did not preserve older worlds without picked apples")
	_expect((version_four_save["player_stats"] as Dictionary)["level"] == 3, "migration changed existing progression")
	_expect(is_equal_approx(float((version_four_save["player_stats"] as Dictionary)["current_hp"]), 37.5), "migration changed current HP")
	_expect(version_four_save["player_perks"] == {"allocations": {}}, "migration did not initialize perk allocations")
	var version_seven_save := {"version": 7, "player_stats": {"level": 4, "experience": 194, "current_hp": 42.5}, "pumpkin_patch": {"present": false}}
	_expect(SaveManager._migrate_save_data(version_seven_save), "version-seven save did not migrate")
	_expect((version_seven_save["player_stats"] as Dictionary)["level"] == 4, "version-seven migration changed the player level")
	_expect((version_seven_save["player_stats"] as Dictionary)["experience"] == 174, "maximum old experience did not map to maximum new experience")
	_expect(is_equal_approx(float((version_seven_save["player_stats"] as Dictionary)["current_hp"]), 42.5), "version-seven migration changed current HP")
	_expect(version_seven_save["player_perks"] == {"allocations": {}}, "version-seven migration did not initialize perk allocations")
	var partial_experience_save := {"version": 7, "player_stats": {"level": 3, "experience": 80}, "pumpkin_patch": {"present": false}}
	_expect(SaveManager._migrate_save_data(partial_experience_save), "partial current-level experience did not migrate")
	_expect((partial_experience_save["player_stats"] as Dictionary)["experience"] == 76, "migration did not round proportional experience down")
	var null_stats_save := {"version": 7, "player_stats": null, "pumpkin_patch": {"present": false}}
	_expect(SaveManager._migrate_save_data(null_stats_save), "null player stats did not migrate")
	_expect(null_stats_save["player_stats"] == null and null_stats_save["player_perks"] == {"allocations": {}}, "null player stats migration changed the save shape")
	var missing_stats_save := {"version": 7, "pumpkin_patch": {"present": false}}
	_expect(SaveManager._migrate_save_data(missing_stats_save), "missing player stats did not migrate")
	_expect(not missing_stats_save.has("player_stats") and missing_stats_save["player_perks"] == {"allocations": {}}, "missing player stats migration changed the save shape")
	_expect_failed_migration_unchanged({"version": 7, "player_stats": {"level": 3, "experience": 156}, "pumpkin_patch": {"present": false}}, "experience at the old threshold")
	_expect_failed_migration_unchanged({"version": 7, "player_stats": {"level": 3.5, "experience": 1}, "pumpkin_patch": {"present": false}}, "fractional player level")
	_expect_failed_migration_unchanged({"version": 7, "player_stats": {"level": 3, "experience": 1}, "player_perks": {"allocations": {}}, "pumpkin_patch": {"present": false}}, "preexisting perk data")
	var version_three_save := {"version": 3}
	_expect(not SaveManager._migrate_save_data(version_three_save), "unsupported save version migrated")
	_expect(version_three_save == {"version": 3}, "failed migration changed an unsupported save")

	if _errors.is_empty():
		print("ITEM_PROFICIENCY PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _definition(requirements: Array, unlock_levels: Array) -> ProficiencyDefinition:
	var definition := ProficiencyDefinition.new()
	definition.experience_requirements = PackedFloat64Array(requirements)
	definition.slot_unlock_levels = PackedInt32Array(unlock_levels)
	return definition

func _item(id: StringName, definition: ProficiencyDefinition) -> ItemDefinition:
	var item := ItemDefinition.new()
	item.id = id
	item.display_name = String(id)
	item.icon = GradientTexture1D.new()
	item.proficiency = definition
	return item

func _expect_rejected_unchanged(proficiency: ItemProficiency, saved_progress: Dictionary, context: String) -> void:
	var before := proficiency.snapshot()
	_expect(not proficiency.restore(saved_progress), "%s passed restore validation" % context)
	_expect(proficiency.snapshot() == before, "%s changed state after failed restore" % context)

func _expect_failed_migration_unchanged(save_data: Dictionary, context: String) -> void:
	var before := save_data.duplicate(true)
	_expect(not SaveManager._migrate_save_data(save_data), "%s passed save migration" % context)
	_expect(save_data == before, "%s changed save data after failed migration" % context)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
