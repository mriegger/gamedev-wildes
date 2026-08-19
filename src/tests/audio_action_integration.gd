extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[audio_action] starting")
	call_deferred("_run")

func _expect(cond: bool, msg: String):
	if not cond:
		_errors.append(msg)
		print("[audio_action] FAIL: %s" % msg)

func _finish(marker: String):
	var orphan_after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d" % orphan_after)
	if _errors.is_empty():
		print("%s PASS orphan=%d" % [marker, orphan_after])
		quit(0)
	else:
		print("%s FAIL %s" % [marker, str(_errors)])
		quit(1)

func _run():
	var packed = load("res://player/player.tscn") as PackedScene
	_expect(packed != null, "player.tscn load failed")
	var player = packed.instantiate() as PlayerMotor
	root.add_child(player)
	await process_frame

	var interactor = player.interactor as PlayerInteractor
	var animation_driver = player.animation_driver as PlayerAnimationDriver
	var action_audio = player.get_node_or_null("ActionAudio")
	_expect(action_audio != null, "ActionAudio node missing")
	var clunk = action_audio.get_node_or_null("ClunkPlayer") as AudioStreamPlayer
	var melee_impact = action_audio.get_node_or_null("MeleeImpactPlayer") as AudioStreamPlayer
	var creature_hit = action_audio.get_node_or_null("CreatureHitPlayer") as AudioStreamPlayer
	var player_hit = action_audio.get_node_or_null("PlayerHitPlayer") as AudioStreamPlayer
	var equip = action_audio.get_node_or_null("EquipPlayer") as AudioStreamPlayer
	var till = action_audio.get_node_or_null("TillPlayer") as AudioStreamPlayer
	var harvest_player = action_audio.get_node_or_null("HarvestPlayer") as AudioStreamPlayer
	var consume_player = action_audio.get_node_or_null("ConsumePlayer") as AudioStreamPlayer
	_expect(clunk != null, "ClunkPlayer missing")
	_expect(melee_impact != null, "MeleeImpactPlayer missing")
	_expect(action_audio.get_node_or_null("SwingPlayer") == null, "SwingPlayer still present")
	_expect(creature_hit != null, "CreatureHitPlayer missing")
	_expect(player_hit != null, "PlayerHitPlayer missing")
	_expect(equip != null, "EquipPlayer missing")
	_expect(till != null, "TillPlayer missing")
	_expect(harvest_player != null, "HarvestPlayer missing")
	_expect(consume_player != null, "ConsumePlayer missing")
	_expect(action_audio.get_node_or_null("DrawPlayer") == null, "legacy DrawPlayer still present")
	_expect(clunk.bus == &"SFX", "clunk bus not SFX is %s" % clunk.bus)
	_expect(melee_impact.bus == &"SFX", "melee impact bus not SFX is %s" % melee_impact.bus)
	_expect(creature_hit.bus == &"SFX", "creature hit bus not SFX is %s" % creature_hit.bus)
	_expect(player_hit.bus == &"SFX", "player hit bus not SFX is %s" % player_hit.bus)
	_expect(equip.bus == &"SFX", "equip bus not SFX is %s" % equip.bus)
	_expect(till.bus == &"SFX", "till bus not SFX is %s" % till.bus)
	_expect(harvest_player.bus == &"SFX", "harvest bus not SFX is %s" % harvest_player.bus)
	_expect(consume_player.bus == &"SFX", "consume bus not SFX is %s" % consume_player.bus)
	_expect(action_audio._clunk_streams.size() == 4, "clunk streams expected 4 got %d" % action_audio._clunk_streams.size())
	_expect(action_audio._creature_hit_streams.size() == 3, "creature hit streams expected 3 got %d" % action_audio._creature_hit_streams.size())
	_expect(action_audio._player_hit_streams.size() == 1, "player hit streams expected 1 got %d" % action_audio._player_hit_streams.size())
	_expect(action_audio._till_streams.size() == 3, "till streams expected 3 got %d" % action_audio._till_streams.size())
	_expect(action_audio._harvest_streams.size() == 3, "harvest streams expected 3 got %d" % action_audio._harvest_streams.size())
	for stream in action_audio._clunk_streams + action_audio._creature_hit_streams + action_audio._player_hit_streams + action_audio._till_streams + action_audio._harvest_streams:
		_expect(stream != null, "action audio stream is null")

	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var sword_equip_profile := item_catalog.get_definition(&"copper_sword").equip_audio
	var pickaxe_equip_profile := item_catalog.get_definition(&"copper_pickaxe").equip_audio
	var hoe_equip_profile := item_catalog.get_definition(&"copper_hoe").equip_audio
	var pumpkin_consume_profile := item_catalog.get_definition(&"pumpkin").consume_audio
	_expect(sword_equip_profile != null and sword_equip_profile.streams.size() == 3, "sword equip profile lost its three draw sounds")
	_expect(pickaxe_equip_profile != null and pickaxe_equip_profile.streams.size() == 3, "copper pickaxe equip profile lost its three draw sounds")
	_expect(hoe_equip_profile != null and hoe_equip_profile.streams.size() == 3, "copper hoe equip profile lost its three draw sounds")
	_expect(pumpkin_consume_profile != null and pumpkin_consume_profile.streams.size() == 1, "pumpkin consume profile lost its munch sound")
	_expect(item_catalog.get_definition(&"stone_pickaxe").equip_audio == null, "stone pickaxe unexpectedly has equip audio")
	for stream in sword_equip_profile.streams + pickaxe_equip_profile.streams + hoe_equip_profile.streams:
		_expect(stream != null, "equip audio stream is null")
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_starter()
	inventory.slots[0] = InventoryStack.new(&"stone_pickaxe", 1)
	inventory.slots[1] = InventoryStack.new(&"copper_pickaxe", 1)
	inventory.slots[2] = InventoryStack.new(&"copper_hoe", 1)
	var combat := MeleeCombatCoordinator.new()
	root.add_child(combat)

	animation_driver.setup(player, interactor)
	animation_driver.set_process(false)
	action_audio.setup(animation_driver, interactor, inventory, combat)
	var harvest := HarvestCoordinator.new()
	action_audio.setup_harvesting(harvest)
	var consumption := ItemConsumptionCoordinator.new()
	consumption.setup(inventory, ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition))
	action_audio.setup_consumption(consumption)
	await process_frame

	var has_mining = false
	var has_terrain_hit = false
	var has_melee_impact = false
	var has_swing = false
	var has_creature_hit = false
	var has_inventory = false
	var has_till = false
	var has_harvest = false
	var has_consumption = false
	for c in animation_driver.mining_impact.get_connections():
		if c["callable"].get_object() == action_audio:
			has_mining = true
	for c in interactor.melee_terrain_hit.get_connections():
		if c["callable"].get_object() == action_audio:
			has_terrain_hit = true
	for c in interactor.melee_attack_impacted.get_connections():
		if c["callable"].get_object() == action_audio:
			has_melee_impact = true
	for c in interactor.melee_attack_started.get_connections():
		if c["callable"].get_object() == action_audio:
			has_swing = true
	for c in combat.melee_outcome_committed.get_connections():
		if c["callable"].get_object() == action_audio:
			has_creature_hit = true
	for c in inventory.inventory_changed.get_connections():
		if c["callable"].get_object() == action_audio:
			has_inventory = true
	for c in interactor.soil_tilled.get_connections():
		if c["callable"].get_object() == action_audio:
			has_till = true
	for c in harvest.harvest_completed.get_connections():
		if c["callable"].get_object() == action_audio:
			has_harvest = true
	for c in consumption.item_consumed.get_connections():
		if c["callable"].get_object() == action_audio:
			has_consumption = true
	_expect(has_mining, "mining impact not connected to action audio")
	_expect(has_terrain_hit, "melee_terrain_hit not connected")
	_expect(has_melee_impact, "melee_attack_impacted not connected")
	_expect(not has_swing, "melee_attack_started still connected to action audio")
	_expect(has_creature_hit, "melee_outcome_committed not connected")
	_expect(has_inventory, "inventory_changed not connected")
	_expect(has_till, "soil_tilled not connected")
	_expect(has_harvest, "harvest_completed not connected")
	_expect(has_consumption, "item_consumed not connected")
	_expect(equip.stream == null, "initial selected item played an equip sound")

	animation_driver._update_mining_impact(0.0, true)
	await process_frame
	_expect(clunk.stream != null, "clunk stream null after mining impact")
	_expect(abs(clunk.volume_db - (-6.0)) < 0.1, "mining clunk vol expected -6 got %f" % clunk.volume_db)
	_expect(clunk.pitch_scale >= 0.95 and clunk.pitch_scale <= 1.07, "mining pitch out of range %f" % clunk.pitch_scale)
	clunk.stop()
	clunk.stream = null
	animation_driver._update_mining_impact(animation_driver.animator.profile.mine_cycle_seconds - 0.01, true)
	_expect(clunk.stream == null, "mining impact ignored profile cadence")
	animation_driver._update_mining_impact(0.02, true)
	_expect(clunk.stream != null, "mining impact did not follow profile cadence")
	animation_driver._update_mining_impact(0.0, false)

	interactor.melee_terrain_hit.emit(Vector3i(1, 2, 3))
	await process_frame
	_expect(abs(clunk.volume_db - (-4.0)) < 0.1, "melee clunk vol expected -4 got %f" % clunk.volume_db)
	var hammer_action := item_catalog.get_definition(&"copper_hammer").primary_action as MeleeAttackActionDefinition
	interactor.melee_attack_impacted.emit(hammer_action, Vector3.ZERO)
	await process_frame
	_expect(hammer_action.impact_audio != null and hammer_action.impact_audio.resource_path == "res://assets/audio/combat/weapons/hammer/impacts/low_thump_332670_CC0.ogg", "hammer action uses the wrong impact sound asset")
	_expect(melee_impact.stream == hammer_action.impact_audio, "hammer impact did not use its configured low thump")
	_expect(is_equal_approx(melee_impact.volume_db, hammer_action.impact_audio_volume_db), "hammer impact did not use its configured volume")
	melee_impact.stop()
	melee_impact.stream = null

	interactor.soil_tilled.emit()
	await process_frame
	_expect(action_audio._till_streams.has(till.stream), "tilling did not select a till sound")
	_expect(till.pitch_scale >= 0.96 and till.pitch_scale <= 1.04, "till pitch out of range %f" % till.pitch_scale)
	_expect(abs(till.volume_db - (-8.0)) < 0.1, "till volume expected -8 got %f" % till.volume_db)
	var first_till_stream: AudioStream = till.stream
	interactor.soil_tilled.emit()
	_expect(till.stream != first_till_stream, "consecutive tills repeated the same sound")

	harvest.harvest_completed.emit()
	await process_frame
	_expect(action_audio._harvest_streams.has(harvest_player.stream), "harvest did not select a harvest sound")
	_expect(harvest_player.pitch_scale >= 0.96 and harvest_player.pitch_scale <= 1.04, "harvest pitch out of range %f" % harvest_player.pitch_scale)
	_expect(abs(harvest_player.volume_db - (-8.0)) < 0.1, "harvest volume expected -8 got %f" % harvest_player.volume_db)
	var first_harvest_stream: AudioStream = harvest_player.stream
	harvest.harvest_completed.emit()
	_expect(harvest_player.stream != first_harvest_stream, "consecutive harvests repeated the same sound")

	consumption.item_consumed.emit(&"pumpkin")
	await process_frame
	_expect(pumpkin_consume_profile.streams.has(consume_player.stream), "pumpkin consumption did not select its munch sound")
	_expect(consume_player.pitch_scale >= pumpkin_consume_profile.pitch_min and consume_player.pitch_scale <= pumpkin_consume_profile.pitch_max, "consume pitch out of range %f" % consume_player.pitch_scale)
	_expect(is_equal_approx(consume_player.volume_db, pumpkin_consume_profile.volume_db), "consume volume was %f" % consume_player.volume_db)

	var sword_action := item_catalog.get_definition(&"copper_sword").primary_action as MeleeAttackActionDefinition
	var player_contact := MeleeContact.new(MeleeCombatCoordinator.PLAYER_RUNTIME_ID, &"player", 1, &"zombie", sword_action.attack_profile.id, Vector3.ONE, Vector3.RIGHT)
	combat.melee_outcome_committed.emit(MeleeOutcome.new(player_contact, &"copper_sword", 1.0, false))
	await process_frame
	_expect(action_audio._creature_hit_streams.has(creature_hit.stream), "confirmed player contact did not select a creature hit sound")
	_expect(creature_hit.pitch_scale >= 0.94 and creature_hit.pitch_scale <= 1.06, "creature hit pitch out of range %f" % creature_hit.pitch_scale)
	_expect(player_hit.stream == null, "outgoing player contact played the incoming player hit sound")
	creature_hit.stop()
	creature_hit.stream = null
	var entity_contact := MeleeContact.new(1, &"zombie", 0, &"player", &"zombie_melee", Vector3.ONE, Vector3.LEFT)
	combat.melee_outcome_committed.emit(MeleeOutcome.new(entity_contact, &"", 1.0, false))
	_expect(creature_hit.stream == null, "non-player contact played the player's creature hit sound")
	_expect(action_audio._player_hit_streams.has(player_hit.stream), "confirmed enemy contact did not select a player hit sound")
	_expect(player_hit.pitch_scale >= 0.96 and player_hit.pitch_scale <= 1.04, "player hit pitch out of range %f" % player_hit.pitch_scale)
	_expect(abs(player_hit.volume_db - (-11.0)) < 0.1, "player hit volume expected -11 got %f" % player_hit.volume_db)

	_expect(inventory.select_slot(3), "sword selection failed")
	_expect(sword_equip_profile.streams.has(equip.stream), "selecting the sword did not play a draw sound")
	_expect(equip.pitch_scale >= sword_equip_profile.pitch_min and equip.pitch_scale <= sword_equip_profile.pitch_max, "sword equip pitch out of range %f" % equip.pitch_scale)
	_expect(is_equal_approx(equip.volume_db, sword_equip_profile.volume_db), "sword equip volume was %f" % equip.volume_db)
	var first_draw: AudioStream = equip.stream
	equip.stop()
	equip.stream = null
	inventory.inventory_changed.emit()
	_expect(equip.stream == null, "unchanged sword selection replayed the draw sound")
	_expect(inventory.select_slot(0), "pickaxe selection failed")
	_expect(equip.stream == null, "selecting the stone pickaxe played equip audio")
	_expect(inventory.select_slot(1), "copper pickaxe selection failed")
	_expect(pickaxe_equip_profile.streams.has(equip.stream), "selecting the copper pickaxe did not play its equip sound")
	_expect(equip.pitch_scale >= pickaxe_equip_profile.pitch_min and equip.pitch_scale <= pickaxe_equip_profile.pitch_max, "pickaxe equip pitch out of range %f" % equip.pitch_scale)
	_expect(is_equal_approx(equip.volume_db, pickaxe_equip_profile.volume_db), "pickaxe equip volume was %f" % equip.volume_db)
	var first_pickaxe_draw: AudioStream = equip.stream
	equip.stop()
	equip.stream = null
	_expect(inventory.select_slot(2), "copper hoe selection failed")
	_expect(hoe_equip_profile.streams.has(equip.stream), "selecting the copper hoe did not play its equip sound")
	_expect(equip.pitch_scale >= hoe_equip_profile.pitch_min and equip.pitch_scale <= hoe_equip_profile.pitch_max, "hoe equip pitch out of range %f" % equip.pitch_scale)
	_expect(is_equal_approx(equip.volume_db, hoe_equip_profile.volume_db), "hoe equip volume was %f" % equip.volume_db)
	equip.stop()
	equip.stream = null
	_expect(inventory.select_slot(3), "sword reselection failed")
	_expect(equip.stream != null and equip.stream != first_draw, "reselecting the sword did not play a different draw sound")
	equip.stop()
	equip.stream = null
	_expect(inventory.select_slot(1), "copper pickaxe reselection failed")
	_expect(equip.stream != null and equip.stream != first_pickaxe_draw, "reselecting the copper pickaxe did not play a different draw sound")

	player.queue_free()
	combat.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish", "AUDIO_ACTION")
