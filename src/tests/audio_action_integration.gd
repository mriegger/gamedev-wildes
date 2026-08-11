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
	var creature_hit = action_audio.get_node_or_null("CreatureHitPlayer") as AudioStreamPlayer
	var draw = action_audio.get_node_or_null("DrawPlayer") as AudioStreamPlayer
	_expect(clunk != null, "ClunkPlayer missing")
	_expect(action_audio.get_node_or_null("SwingPlayer") == null, "SwingPlayer still present")
	_expect(creature_hit != null, "CreatureHitPlayer missing")
	_expect(draw != null, "DrawPlayer missing")
	_expect(clunk.bus == &"SFX", "clunk bus not SFX is %s" % clunk.bus)
	_expect(creature_hit.bus == &"SFX", "creature hit bus not SFX is %s" % creature_hit.bus)
	_expect(draw.bus == &"SFX", "draw bus not SFX is %s" % draw.bus)
	_expect(action_audio._clunk_streams.size() == 4, "clunk streams expected 4 got %d" % action_audio._clunk_streams.size())
	_expect(action_audio._creature_hit_streams.size() == 3, "creature hit streams expected 3 got %d" % action_audio._creature_hit_streams.size())
	_expect(action_audio._draw_streams.size() == 3, "draw streams expected 3 got %d" % action_audio._draw_streams.size())
	for stream in action_audio._clunk_streams + action_audio._creature_hit_streams + action_audio._draw_streams:
		_expect(stream != null, "action audio stream is null")

	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog)
	inventory.setup_starter()
	var combat := MeleeCombatCoordinator.new()
	root.add_child(combat)

	animation_driver.setup(player, interactor)
	animation_driver.set_process(false)
	action_audio.setup(animation_driver, interactor, inventory, combat)
	await process_frame

	var has_mining = false
	var has_terrain_hit = false
	var has_swing = false
	var has_creature_hit = false
	var has_inventory = false
	for c in animation_driver.mining_impact.get_connections():
		if c["callable"].get_object() == action_audio:
			has_mining = true
	for c in interactor.melee_terrain_hit.get_connections():
		if c["callable"].get_object() == action_audio:
			has_terrain_hit = true
	for c in interactor.melee_attack_started.get_connections():
		if c["callable"].get_object() == action_audio:
			has_swing = true
	for c in combat.melee_contact_committed.get_connections():
		if c["callable"].get_object() == action_audio:
			has_creature_hit = true
	for c in inventory.inventory_changed.get_connections():
		if c["callable"].get_object() == action_audio:
			has_inventory = true
	_expect(has_mining, "mining impact not connected to action audio")
	_expect(has_terrain_hit, "melee_terrain_hit not connected")
	_expect(not has_swing, "melee_attack_started still connected to action audio")
	_expect(has_creature_hit, "melee_contact_committed not connected")
	_expect(has_inventory, "inventory_changed not connected")
	_expect(draw.stream == null, "initial selected item played a draw sound")

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

	var sword_action := item_catalog.get_definition(&"copper_sword").primary_action as MeleeAttackActionDefinition
	var player_contact := MeleeContact.new(MeleeCombatCoordinator.PLAYER_RUNTIME_ID, &"player", 1, &"zombie", sword_action.attack_profile.id, Vector3.ONE, Vector3.RIGHT)
	combat.melee_contact_committed.emit(player_contact)
	await process_frame
	_expect(action_audio._creature_hit_streams.has(creature_hit.stream), "confirmed player contact did not select a creature hit sound")
	_expect(creature_hit.pitch_scale >= 0.94 and creature_hit.pitch_scale <= 1.06, "creature hit pitch out of range %f" % creature_hit.pitch_scale)
	creature_hit.stop()
	creature_hit.stream = null
	var entity_contact := MeleeContact.new(1, &"zombie", 0, &"player", &"zombie_melee", Vector3.ONE, Vector3.LEFT)
	combat.melee_contact_committed.emit(entity_contact)
	_expect(creature_hit.stream == null, "non-player contact played the player's creature hit sound")

	_expect(inventory.select_slot(3), "sword selection failed")
	_expect(action_audio._draw_streams.has(draw.stream), "selecting the sword did not play a draw sound")
	_expect(draw.pitch_scale >= 0.98 and draw.pitch_scale <= 1.02, "draw pitch out of range %f" % draw.pitch_scale)
	var first_draw: AudioStream = draw.stream
	draw.stop()
	draw.stream = null
	inventory.inventory_changed.emit()
	_expect(draw.stream == null, "unchanged sword selection replayed the draw sound")
	_expect(inventory.select_slot(0), "pickaxe selection failed")
	_expect(draw.stream == null, "selecting a non-melee item played a draw sound")
	_expect(inventory.select_slot(3), "sword reselection failed")
	_expect(draw.stream != null and draw.stream != first_draw, "reselecting the sword did not play a different draw sound")

	player.queue_free()
	combat.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish", "AUDIO_ACTION")
