extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[combat_hit_particles] starting")
	call_deferred("_run")

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
		print("[combat_hit_particles] FAIL: %s" % message)

func _run():
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var particle_catalog := load("res://combat/particles/combat_hit_particle_catalog.tres") as CombatHitParticleCatalog
	var particle_scene := load("res://combat/particles/combat_hit_particles.tscn") as PackedScene
	var game_scene := load("res://game/game.tscn") as PackedScene
	_expect(entity_catalog != null, "entity catalog did not load")
	_expect(particle_catalog != null, "particle catalog did not load")
	_expect(particle_scene != null, "particle scene did not load")
	_expect(game_scene != null, "game scene did not load")
	_expect(particle_catalog.validate(entity_catalog), "particle catalog is invalid")
	var game := game_scene.instantiate() as Game
	_expect(game.combat_hit_particle_catalog != null, "game particle catalog is missing")
	_expect(game.get_node_or_null("CombatHitParticles") is CombatHitParticles, "game particle presenter is missing")
	game.free()
	var particles := particle_scene.instantiate() as CombatHitParticles
	var combat := MeleeCombatCoordinator.new()
	root.add_child(particles)
	root.add_child(combat)
	await process_frame
	_expect(particles._bursts.size() == 4, "expected four pooled bursts got %d" % particles._bursts.size())
	for burst in particles._bursts:
		var primary := burst.get_node("Primary") as CPUParticles3D
		var accent := burst.get_node("Accent") as CPUParticles3D
		_expect(primary != null and accent != null, "%s emitters are missing" % burst.name)
		_expect(primary.one_shot and accent.one_shot, "%s emitters are not one-shot" % burst.name)
		_expect(primary.amount + accent.amount == 10, "%s particle count changed" % burst.name)
		_expect(primary.mesh is QuadMesh and accent.mesh is QuadMesh, "%s does not use chunky quads" % burst.name)
		_expect((primary.mesh as QuadMesh).size.is_equal_approx(Vector2(0.16, 0.16)), "%s quad size changed" % burst.name)
		var material := (primary.mesh as QuadMesh).material as StandardMaterial3D
		_expect(material != null and material.billboard_mode == BaseMaterial3D.BILLBOARD_ENABLED, "%s quads are not billboarded" % burst.name)
	particles.setup(combat, particle_catalog)
	var connected := false
	for connection in combat.melee_outcome_committed.get_connections():
		if connection["callable"].get_object() == particles:
			connected = true
	_expect(connected, "combat outcome signal is not connected")
	var player_zombie := MeleeContact.new(0, &"player", 1, &"zombie", &"copper_sword_melee", Vector3(1.0, 2.0, 3.0), Vector3.RIGHT)
	_emit_outcome(combat, player_zombie)
	var guts := particles._bursts[0]
	var guts_profile := particle_catalog.get_profile(&"player", &"zombie")
	_expect(guts.global_position.is_equal_approx(player_zombie.world_position), "guts burst position changed")
	_expect((guts.get_node("Primary") as CPUParticles3D).emitting and (guts.get_node("Accent") as CPUParticles3D).emitting, "guts burst did not emit")
	_expect((guts.get_node("Primary") as CPUParticles3D).color.is_equal_approx(guts_profile.primary_color), "guts primary color changed")
	_expect((guts.get_node("Accent") as CPUParticles3D).color.is_equal_approx(guts_profile.accent_color), "guts accent color changed")
	var expected_direction := (Vector3.RIGHT + Vector3.UP * CombatHitParticleBurst.UPWARD_BIAS).normalized()
	_expect((guts.get_node("Primary") as CPUParticles3D).direction.is_equal_approx(expected_direction), "guts direction changed")
	var zombie_player := MeleeContact.new(1, &"zombie", 0, &"player", &"zombie_melee", Vector3(2.0, 3.0, 4.0), Vector3.LEFT)
	_emit_outcome(combat, zombie_player)
	var blood := particles._bursts[1]
	var blood_profile := particle_catalog.get_profile(&"zombie", &"player")
	_expect((blood.get_node("Primary") as CPUParticles3D).color.is_equal_approx(blood_profile.primary_color), "blood primary color changed")
	_expect((blood.get_node("Accent") as CPUParticles3D).color.is_equal_approx(blood_profile.accent_color), "blood accent color changed")
	var player_sheep := MeleeContact.new(0, &"player", 2, &"sheep", &"copper_sword_melee", Vector3(3.0, 4.0, 5.0), Vector3.BACK)
	_emit_outcome(combat, player_sheep)
	var wool := particles._bursts[2]
	var wool_profile := particle_catalog.get_profile(&"player", &"sheep")
	_expect((wool.get_node("Primary") as CPUParticles3D).color.is_equal_approx(wool_profile.primary_color), "wool primary color changed")
	_expect((wool.get_node("Accent") as CPUParticles3D).color.is_equal_approx(wool_profile.accent_color), "wool accent color changed")
	var unsupported := MeleeContact.new(2, &"sheep", 0, &"player", &"test", Vector3.ONE, Vector3.FORWARD)
	_emit_outcome(combat, unsupported)
	_expect(particles._next_burst == 3, "unsupported contact consumed a pooled burst")
	_expect(not (particles._bursts[3].get_node("Primary") as CPUParticles3D).emitting, "unsupported contact emitted particles")
	_emit_outcome(combat, player_zombie)
	_emit_outcome(combat, player_sheep)
	_expect(particles._next_burst == 1, "particle pool did not wrap")
	particles.queue_free()
	combat.queue_free()
	for _frame_index in range(10):
		await process_frame
	_finish()

func _emit_outcome(combat: MeleeCombatCoordinator, contact: MeleeContact):
	combat.melee_outcome_committed.emit(MeleeOutcome.new(contact, &"copper_sword", 1.0, false))

func _finish():
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d" % orphan_after)
	if _errors.is_empty():
		print("COMBAT_HIT_PARTICLES PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("COMBAT_HIT_PARTICLES FAIL %s" % str(_errors))
		quit(1)
