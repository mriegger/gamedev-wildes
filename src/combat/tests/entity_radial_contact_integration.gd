extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 8

var _failures: int = 0
var _outcomes: Array[MeleeOutcome] = []

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_radial_contact_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _make_catalog() -> EntityCatalog:
	var source := load("res://entities/definitions/stone_golem.tres") as EntityDefinition
	var definition := source.duplicate(true) as EntityDefinition
	definition.ambient_max_active = 2
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _record_outcome(outcome: MeleeOutcome) -> void:
	_outcomes.append(outcome)

func _run() -> void:
	var profile := load("res://combat/profiles/stone_golem_slam.tres") as MeleeAttackProfile
	_expect(profile != null and profile.validate(profile.resource_path), "Stone Golem slam profile was invalid")
	_expect(profile.id == &"stone_golem_slam" and is_equal_approx(profile.reach, 1.0), "Stone Golem slam radial identity or reach changed")
	_expect(is_equal_approx(profile.calculate_damage(10.0, 0.0), 30.0), "Stone Golem slam unarmored damage changed")
	var world := _make_world()
	var runtime := EntityRuntime.new()
	var combat := MeleeCombatCoordinator.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	get_root().add_child(runtime)
	get_root().add_child(combat)
	get_root().add_child(player)
	player.global_position = Vector3(0.5, FEET_Y, 0.5)
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	runtime.setup(_make_catalog(), world, 2, 2, EntityNavigationLimits.new(32, 512, 2))
	var spawn_requests: Array[EntitySpawnRequest] = [
		EntitySpawnRequest.new(&"stone_golem", Vector3(2.5, FEET_Y, 0.5), 6101),
		EntitySpawnRequest.new(&"stone_golem", Vector3(5.5, FEET_Y, 0.5), 6102),
	]
	var runtime_ids := runtime.try_spawn_batch(spawn_requests)
	_expect(runtime_ids.size() == 2, "production runtime did not spawn the radial-contact fixture")
	if runtime_ids.size() != 2:
		await _cleanup(combat, runtime, player)
		_finish()
		return
	var source := runtime.get_actor(runtime_ids[0])
	var bystander := runtime.get_actor(runtime_ids[1])
	source.set_process(false)
	bystander.set_process(false)
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(player_stats.set_base_value(&"defense", 0.0), "unarmored player defense setup failed")
	combat.setup(world, player, player_stats, runtime)
	runtime.entity_radial_contact_reached.connect(combat.try_commit_entity_radial_contact)
	combat.melee_outcome_committed.connect(_record_outcome)
	var bystander_hp := runtime.get_current_hp(bystander.runtime_id)
	var terrain_position := Vector3i(0, FLAT_HEIGHT, 0)
	var terrain_before := world.get_block_id_at(terrain_position)

	source.global_position = player.global_position + Vector3.RIGHT * (profile.reach + 0.01)
	var hp_before := player_stats.current_hp
	source.radial_contact_reached.emit(source.runtime_id, profile)
	_expect(_outcomes.is_empty(), "out-of-radius actor signal committed radial damage")
	_expect(is_equal_approx(player_stats.current_hp, hp_before), "out-of-radius actor signal changed player HP")

	source.global_position = player.global_position + Vector3.RIGHT * profile.reach
	source.radial_contact_reached.emit(source.runtime_id, profile)
	_expect(_outcomes.size() == 1, "exact-radius actor signal did not forward through EntityRuntime")
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 30.0), "exact-radius slam did not deal 30 unarmored damage")
	if _outcomes.size() == 1:
		var contact := (_outcomes[0] as MeleeOutcome).contact
		_expect(
			contact.source_runtime_id == source.runtime_id
			and contact.source_definition_id == &"stone_golem"
			and contact.target_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID
			and contact.target_definition_id == MeleeCombatCoordinator.PLAYER_DEFINITION_ID
			and contact.attack_id == profile.id,
			"radial contact payload did not identify the Stone Golem and player",
		)
		_expect(contact.world_position.is_equal_approx(player.global_position + Vector3.UP * player.player_height * 0.5), "radial contact did not use the current player center")
	_expect(is_equal_approx(runtime.get_current_hp(bystander.runtime_id), bystander_hp), "radial contact damaged a nearby mob")
	_expect(world.get_block_id_at(terrain_position) == terrain_before, "radial contact changed terrain")

	_expect(player_stats.set_base_value(&"defense", 4.0), "defended player setup failed")
	_expect(player_stats.set_current_hp(player_stats.get_value(&"hp")), "defended player health reset failed")
	source.global_position = player.global_position + Vector3.DOWN * ((source.definition.body_height - player.player_height) * 0.5)
	var outcome_count := _outcomes.size()
	_expect(combat.try_commit_entity_radial_contact(source.runtime_id, profile), "coincident-center radial contact did not commit")
	_expect(_outcomes.size() == outcome_count + 1, "coincident-center radial contact emitted the wrong outcome count")
	_expect(is_equal_approx(player_stats.current_hp, player_stats.get_value(&"hp") - 26.0), "radial contact did not apply source strength and player defense")
	if _outcomes.size() == outcome_count + 1:
		var centered_outcome := _outcomes.back() as MeleeOutcome
		_expect(centered_outcome.contact.hit_direction.is_equal_approx(Vector3.UP), "coincident centers did not produce a stable upward hit direction")
		_expect(is_equal_approx(centered_outcome.applied_damage, 26.0), "defended radial outcome recorded incorrect damage")

	hp_before = player_stats.current_hp
	outcome_count = _outcomes.size()
	source.global_position = player.global_position + Vector3.UP * player.player_height
	_expect(not combat.try_commit_entity_radial_contact(source.runtime_id, profile), "vertically separated bounds accepted radial damage")
	_expect(_outcomes.size() == outcome_count and is_equal_approx(player_stats.current_hp, hp_before), "vertical rejection changed combat state")

	source.global_position = player.global_position + Vector3.RIGHT * profile.reach
	var occluding_cell := Vector3i(floori(player.global_position.x), FLAT_HEIGHT + 2, floori(player.global_position.z))
	world.restore_block_edits({occluding_cell: BlockId.Type.STONE}, {})
	_expect(not combat.try_commit_entity_radial_contact(source.runtime_id, profile), "voxel-occluded radial contact committed")
	_expect(_outcomes.size() == outcome_count and is_equal_approx(player_stats.current_hp, hp_before), "occluded radial rejection changed combat state")
	world.restore_block_edits({}, {})

	_expect(runtime.try_despawn(source.runtime_id), "radial source could not despawn")
	_expect(not combat.try_commit_entity_radial_contact(source.runtime_id, profile), "despawned source committed radial damage")
	source.radial_contact_reached.emit(source.runtime_id, profile)
	_expect(_outcomes.size() == outcome_count and is_equal_approx(player_stats.current_hp, hp_before), "despawned actor signal remained connected")
	_expect(is_equal_approx(runtime.get_current_hp(bystander.runtime_id), bystander_hp), "radial lifecycle checks damaged the bystander")

	await _cleanup(combat, runtime, player)
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "radial contact integration ended with %d orphan nodes" % orphan_count)
	_finish()

func _cleanup(combat: MeleeCombatCoordinator, runtime: EntityRuntime, player: PlayerMotor) -> void:
	combat.shutdown()
	runtime.shutdown()
	combat.free()
	runtime.free()
	player.free()
	await process_frame
	await process_frame

func _finish() -> void:
	if _failures == 0:
		print("ENTITY_RADIAL_CONTACT_INTEGRATION PASS")
		quit(0)
	else:
		print("ENTITY_RADIAL_CONTACT_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
