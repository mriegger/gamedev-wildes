extends SceneTree

var _errors: Array[String] = []

func _init():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	_expect(item_catalog.validate(block_catalog), "item catalog is invalid")
	_expect(entity_catalog.validate(), "entity catalog is invalid")
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_starter()
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var item_proficiency := ItemProficiency.new(item_catalog)
	var inventory_stats := InventoryLoadoutCoordinator.new()
	_expect(inventory_stats.setup(inventory, player_stats, item_proficiency), "inventory stat coordinator setup failed")
	for armor_id in [&"copper_helmet", &"copper_chest_plate", &"copper_pants", &"copper_shoes"]:
		var source_index := _find_item(inventory, armor_id)
		_expect(source_index >= 0 and inventory_stats.try_equip_armor(source_index), "failed to equip %s" % armor_id)
	var progression := CombatProgressionCoordinator.new()
	progression.setup(player_stats, inventory, entity_catalog, item_proficiency)

	progression.record_melee_outcome(_outcome(0, &"player", 1, &"zombie", &"copper_sword", 40.0, false))
	_expect(is_equal_approx(item_proficiency.get_experience(&"copper_sword"), 40.0), "weapon proficiency did not use applied damage")
	_expect(player_stats.get_total_experience() == 0, "nonlethal damage awarded player experience")
	progression.record_melee_outcome(_outcome(0, &"player", 2, &"sheep", &"copper_sword", 30.0, true))
	_expect(is_equal_approx(item_proficiency.get_experience(&"copper_sword"), 70.0), "separate target damage did not accumulate")
	_expect(player_stats.get_total_experience() == 10, "configured kill reward was not awarded")

	progression.record_melee_outcome(_outcome(3, &"zombie", 0, &"player", &"", 25.0, false))
	for armor_id in [&"copper_helmet", &"copper_chest_plate", &"copper_pants", &"copper_shoes"]:
		_expect(is_equal_approx(item_proficiency.get_experience(armor_id), 25.0), "%s did not receive full incoming damage proficiency" % armor_id)

	if _errors.is_empty():
		print("COMBAT_PROGRESSION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _outcome(
	source_runtime_id: int,
	source_definition_id: StringName,
	target_runtime_id: int,
	target_definition_id: StringName,
	source_item_id: StringName,
	damage: float,
	defeated: bool,
) -> MeleeOutcome:
	var contact := MeleeContact.new(
		source_runtime_id,
		source_definition_id,
		target_runtime_id,
		target_definition_id,
		&"test_attack",
		Vector3.ONE,
		Vector3.RIGHT,
	)
	return MeleeOutcome.new(contact, source_item_id, damage, defeated)

func _find_item(inventory: InventoryModel, item_id: StringName) -> int:
	for index in range(InventoryModel.FILLABLE_SIZE):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
