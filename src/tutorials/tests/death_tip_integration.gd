extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await _test_priority_and_recovery_tips()
	await _test_slime_attachment_tip()
	await _test_resistance_and_crowd_tips()
	if _failures == 0:
		print("DEATH_TIP PASS")
		quit(0)
	else:
		print("DEATH_TIP FAIL failures=%d" % _failures)
		quit(1)

func _test_priority_and_recovery_tips() -> void:
	var fixture := _create_fixture()
	var coordinator := fixture["coordinator"] as DeathTipCoordinator
	_expect(coordinator.choose_tip(5, true) == DeathTipCoordinator.NO_WEAPON_TIP, "weaponless death did not take priority over every other tip")
	_add_item(fixture, &"copper_sword")
	var tips := coordinator.get_applicable_tips(0, false)
	_expect(tips == [DeathTipCoordinator.HARVEST_FOOD_TIP, DeathTipCoordinator.EQUIP_ARMOR_TIP], "empty recovery inventory produced the wrong applicable tips")
	_add_item(fixture, &"apple", 2)
	tips = coordinator.get_applicable_tips(0, false)
	_expect(tips == [DeathTipCoordinator.CRAFT_CAULDRON_TIP, DeathTipCoordinator.EQUIP_ARMOR_TIP], "food without potions produced the wrong recovery tip")
	_add_item(fixture, &"health_potion")
	tips = coordinator.get_applicable_tips(0, false)
	_expect(tips == [DeathTipCoordinator.USE_RECOVERY_ITEM_TIP, DeathTipCoordinator.EQUIP_ARMOR_TIP], "health potion inventory produced the wrong recovery tip")
	(fixture["consumption"] as ItemConsumptionCoordinator).item_consumed.emit(&"copper_helmet")
	_expect(coordinator.get_applicable_tips(0, false) == tips, "consuming an unrelated item suppressed recovery guidance")
	(fixture["consumption"] as ItemConsumptionCoordinator).item_consumed.emit(&"apple")
	tips = coordinator.get_applicable_tips(0, false)
	_expect(tips == [DeathTipCoordinator.EQUIP_ARMOR_TIP], "consuming a recovery item did not remove the recovery tip")
	_equip_armor(fixture, &"copper_helmet")
	_expect(coordinator.get_applicable_tips(0, false) == [DeathTipCoordinator.PROGRESSION_TIP], "fully prepared death did not fall back to the progression tip")
	coordinator.shutdown()
	(fixture["combat"] as MeleeCombatCoordinator).free()

func _test_slime_attachment_tip() -> void:
	var fixture := _create_fixture(73)
	var coordinator := fixture["coordinator"] as DeathTipCoordinator
	_add_item(fixture, &"copper_sword")
	_equip_armor(fixture, &"copper_helmet")
	(fixture["consumption"] as ItemConsumptionCoordinator).item_consumed.emit(&"health_potion")
	_expect(coordinator.get_applicable_tips(0, true) == [DeathTipCoordinator.SLIME_ATTACHMENT_TIP], "attached slime did not add its death tip to the eligible pool")
	_expect(coordinator.choose_tip(0, true) == DeathTipCoordinator.SLIME_ATTACHMENT_TIP, "attached slime tip was not selectable")
	_expect(coordinator.get_applicable_tips(0, false) == [DeathTipCoordinator.PROGRESSION_TIP], "slime tip appeared without an attachment at death")
	coordinator.shutdown()
	(fixture["combat"] as MeleeCombatCoordinator).free()

func _test_resistance_and_crowd_tips() -> void:
	var fixture := _create_fixture(77)
	var coordinator := fixture["coordinator"] as DeathTipCoordinator
	var combat := fixture["combat"] as MeleeCombatCoordinator
	_add_item(fixture, &"copper_sword")
	_equip_armor(fixture, &"copper_helmet")
	(fixture["consumption"] as ItemConsumptionCoordinator).item_consumed.emit(&"health_potion")
	combat.melee_outcome_committed.emit(_make_player_outcome(42, &"skeleton", DamageAffinityDefinition.Response.RESISTANT))
	combat.melee_outcome_committed.emit(_make_incoming_outcome(42, &"skeleton"))
	var tips := coordinator.get_applicable_tips(4, false)
	_expect(tips.size() == 2 and DeathTipCoordinator.CROWD_TIP in tips, "crowded resisted death did not include both applicable tips")
	var affinity_tip := ""
	for tip in tips:
		if tip.begins_with("Tip: Skeletons"):
			affinity_tip = tip
	var resistant_color := CombatPresentationPalette.RESISTANT_DAMAGE_COLOR.to_html(false)
	var weak_color := CombatPresentationPalette.WEAK_DAMAGE_COLOR.to_html(false)
	_expect("resistant to [b][color=#%s]slash[/color][/b]" % resistant_color in affinity_tip, "death tip did not color the killer's resistance")
	_expect("weak to [b][color=#%s]blunt[/color][/b] damage" % weak_color in affinity_tip, "death tip did not color the killer's weakness")
	_expect(affinity_tip.ends_with("Try hitting them with a Hammer."), "death tip did not recommend the killer's weak weapon type")
	combat.melee_outcome_committed.emit(_make_player_outcome(43, &"zombie", DamageAffinityDefinition.Response.NEUTRAL, &"copper_hammer"))
	tips = coordinator.get_applicable_tips(4, false)
	_expect(DeathTipCoordinator.CROWD_TIP in tips, "using a hammer against another enemy suppressed the crowd-management tip")
	combat.melee_outcome_committed.emit(_make_player_outcome(42, &"skeleton", DamageAffinityDefinition.Response.NEUTRAL, &"copper_hammer"))
	tips = coordinator.get_applicable_tips(4, false)
	_expect(tips.size() == 1 and tips[0] == affinity_tip, "using a hammer against the killing enemy did not suppress the crowd-management tip")
	coordinator.reset_entity_context()
	_expect(coordinator.get_applicable_tips(0, false) == [DeathTipCoordinator.PROGRESSION_TIP], "entity-context reset retained a stale killer tip")
	var actor_holder := Node3D.new()
	root.add_child(actor_holder)
	var entity_catalog := fixture["entity_catalog"] as EntityCatalog
	var nearby: Array[EntityActor] = []
	for index in range(4):
		nearby.append(_make_actor(actor_holder, entity_catalog.get_definition(&"zombie"), Vector3(float(index), 20.0, 0.0)))
	nearby.append(_make_actor(actor_holder, entity_catalog.get_definition(&"sheep"), Vector3.ZERO))
	nearby.append(_make_actor(actor_holder, entity_catalog.get_definition(&"zombie"), Vector3(4.1, 0.0, 0.0)))
	_expect(DeathTipCoordinator.count_nearby_hostiles(nearby, Vector3.ZERO) == 4, "crowd count did not use hostile horizontal distance")
	actor_holder.free()
	coordinator.shutdown()
	combat.free()

func _create_fixture(seed: int = 41) -> Dictionary:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_empty()
	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var loadout := InventoryTestFixture.create_loadout(inventory, stats)
	var consumption := ItemConsumptionCoordinator.new()
	consumption.setup(inventory, loadout, stats)
	var combat := MeleeCombatCoordinator.new()
	var coordinator := DeathTipCoordinator.new(seed)
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	coordinator.setup(inventory, consumption, combat, entity_catalog)
	return {
		"inventory": inventory,
		"loadout": loadout,
		"consumption": consumption,
		"combat": combat,
		"coordinator": coordinator,
		"entity_catalog": entity_catalog,
	}

func _add_item(fixture: Dictionary, item_id: StringName, count: int = 1) -> void:
	var inventory := fixture["inventory"] as InventoryModel
	var loadout := fixture["loadout"] as InventoryLoadoutCoordinator
	var instance := inventory.equipment_instance_factory.create(item_id)
	_expect(loadout.add_stack(InventoryStack.new(item_id, count, instance)), "death tip fixture could not add %s" % item_id)

func _equip_armor(fixture: Dictionary, item_id: StringName) -> void:
	_add_item(fixture, item_id)
	var inventory := fixture["inventory"] as InventoryModel
	var loadout := fixture["loadout"] as InventoryLoadoutCoordinator
	var source_index := -1
	for index in range(InventoryModel.FILLABLE_SIZE):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			source_index = index
			break
	_expect(source_index >= 0 and loadout.try_equip_armor(source_index), "death tip fixture could not equip %s" % item_id)

func _make_player_outcome(
	runtime_id: int,
	definition_id: StringName,
	response: int,
	item_id: StringName = &"copper_sword",
) -> MeleeOutcome:
	var contact := MeleeContact.new(
		MeleeCombatCoordinator.PLAYER_RUNTIME_ID,
		MeleeCombatCoordinator.PLAYER_DEFINITION_ID,
		runtime_id,
		definition_id,
		&"test_player_attack",
		Vector3.ZERO,
		Vector3.FORWARD,
	)
	return MeleeOutcome.new(contact, item_id, 5.0, false, response)

func _make_incoming_contact(runtime_id: int, definition_id: StringName) -> MeleeContact:
	return MeleeContact.new(
		runtime_id,
		definition_id,
		MeleeCombatCoordinator.PLAYER_RUNTIME_ID,
		MeleeCombatCoordinator.PLAYER_DEFINITION_ID,
		&"test_enemy_attack",
		Vector3.ZERO,
		Vector3.FORWARD,
	)

func _make_incoming_outcome(runtime_id: int, definition_id: StringName) -> MeleeOutcome:
	return MeleeOutcome.new(
		_make_incoming_contact(runtime_id, definition_id),
		&"",
		5.0,
		true,
		DamageAffinityDefinition.Response.NEUTRAL,
	)

func _make_actor(parent: Node3D, definition: EntityDefinition, position: Vector3) -> EntityActor:
	var actor := definition.actor_scene.instantiate() as EntityActor
	actor.definition = definition
	parent.add_child(actor)
	actor.position = position
	return actor

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[death_tip_integration] FAIL: %s" % message)
