extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")
const StoneGolemLandingDustType := preload("res://entities/stone_golem/stone_golem_landing_dust.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 16
const FIXED_DELTA: float = 0.01
const WINDUP_TICKS: int = 60
const MAX_FLIGHT_TICKS: int = 180
const MAX_VISIBILITY_TICKS: int = 16

class Fixture:
	extends RefCounted
	var world: VoxelWorld
	var runtime: EntityRuntime
	var combat: MeleeCombatCoordinator
	var player: PlayerMotor
	var player_stats: ActorStats
	var player_inventory: InventoryModel
	var runtime_id: int = -1
	var actor: StoneGolemActor
	var dust: StoneGolemLandingDustType

var _failures: int = 0
var _radial_source_ids: Array[int] = []
var _outcomes: Array[MeleeOutcome] = []

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_slam_hardening_integration] FAIL: %s" % message)

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
	definition.ambient_max_active = 1
	var definitions: Array[EntityDefinition] = [definition]
	var catalog := EntityCatalog.new()
	catalog.definitions = definitions
	return catalog

func _observation(player_position: Vector3) -> EntityTargetObservation:
	var observation := EntityTargetObservation.create(
		player_position,
		player_position + Vector3(8.0, 10.0, 8.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)
	assert(observation != null)
	return observation

func _reset_records() -> void:
	_radial_source_ids.clear()
	_outcomes.clear()

func _record_radial_contact(source_runtime_id: int, _profile: MeleeAttackProfile) -> void:
	_radial_source_ids.append(source_runtime_id)

func _record_outcome(outcome: MeleeOutcome) -> void:
	_outcomes.append(outcome)

func _create_fixture(player_position: Vector3) -> Fixture:
	_reset_records()
	var fixture := Fixture.new()
	fixture.world = _make_world()
	fixture.runtime = EntityRuntime.new()
	fixture.combat = MeleeCombatCoordinator.new()
	fixture.player = (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	get_root().add_child(fixture.runtime)
	get_root().add_child(fixture.combat)
	get_root().add_child(fixture.player)
	fixture.player.global_position = player_position
	fixture.player.set_physics_process(false)
	fixture.player.interactor.set_physics_process(false)
	fixture.player.animation_driver.set_process(false)
	fixture.runtime.setup(_make_catalog(), fixture.world, 1, 2, EntityNavigationLimits.new(32, 512, 2), EntityRuntime.Mode.GAMEPLAY)
	fixture.player_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(fixture.player_stats.set_base_value(&"defense", 0.0), "unarmored player defense setup failed")
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	fixture.player_inventory = InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	fixture.combat.setup(fixture.world, fixture.player, fixture.player_stats, fixture.player_inventory, fixture.runtime, load("res://combat/damage/damage_type_catalog.tres") as DamageTypeCatalog)
	fixture.runtime.entity_melee_contact_reached.connect(fixture.combat.try_commit_entity_contact)
	fixture.runtime.entity_radial_contact_reached.connect(_record_radial_contact)
	fixture.runtime.entity_radial_contact_reached.connect(fixture.combat.try_commit_entity_radial_contact)
	fixture.combat.melee_outcome_committed.connect(fixture.runtime.record_melee_outcome)
	fixture.combat.melee_outcome_committed.connect(_record_outcome)
	var runtime_ids := fixture.runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"stone_golem", Vector3(0.5, FEET_Y, 0.5), 8801),
	])
	_expect(runtime_ids.size() == 1, "production runtime did not spawn the Stone Golem fixture")
	if runtime_ids.size() != 1:
		return fixture
	fixture.runtime_id = runtime_ids[0]
	fixture.actor = fixture.runtime.get_actor(fixture.runtime_id) as StoneGolemActorType
	fixture.actor.set_process(false)
	fixture.actor.on_ground = true
	fixture.dust = fixture.actor._landing_dust
	return fixture

func _tick(fixture: Fixture, count: int = 1) -> void:
	for _tick_index in range(count):
		fixture.runtime.tick_gameplay(FIXED_DELTA, _observation(fixture.player.global_position))

func _start_slam(fixture: Fixture) -> bool:
	for _sample_tick in range(MAX_VISIBILITY_TICKS):
		_tick(fixture)
		if fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_WINDUP:
			return true
	_expect(false, "fresh visible target did not start slam windup")
	return false

func _advance_to_airborne(fixture: Fixture) -> bool:
	_tick(fixture, WINDUP_TICKS)
	var airborne := fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE
	_expect(airborne, "clear slam did not become airborne after windup")
	return airborne

func _advance_to_landing(fixture: Fixture) -> int:
	var flight_ticks := 0
	while fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE and flight_ticks < MAX_FLIGHT_TICKS:
		_tick(fixture)
		flight_ticks += 1
	_expect(fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_RECOVERY, "airborne slam did not reach recovery")
	return flight_ticks

func _advance_through_recovery(fixture: Fixture) -> int:
	var recovery_ticks := 0
	while fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_RECOVERY and recovery_ticks < 100:
		_tick(fixture)
		recovery_ticks += 1
	return recovery_ticks

func _make_ceiling() -> Dictionary:
	var blocks: Dictionary = {}
	for x in range(-1, 2):
		for z in range(-1, 2):
			blocks[Vector3i(x, 10, z)] = BlockId.Type.STONE
	return blocks

func _make_wall() -> Dictionary:
	var blocks: Dictionary = {}
	for y in range(int(FEET_Y), 15):
		for z in range(-1, 2):
			blocks[Vector3i(2, y, z)] = BlockId.Type.STONE
	return blocks

func _cleanup_fixture(fixture: Fixture) -> void:
	fixture.combat.shutdown()
	fixture.runtime.shutdown()
	fixture.combat.free()
	fixture.runtime.free()
	fixture.player.free()
	await process_frame
	await process_frame

func _test_ceiling_abort() -> void:
	var fixture := _create_fixture(Vector3(1.5, FEET_Y, 0.5))
	if fixture.actor == null:
		await _cleanup_fixture(fixture)
		return
	if not _start_slam(fixture):
		await _cleanup_fixture(fixture)
		return
	fixture.world.restore_block_edits(_make_ceiling(), {})
	fixture.player.global_position = Vector3(5.5, FEET_Y, 0.5)
	var hp_before := fixture.player_stats.current_hp
	_tick(fixture, WINDUP_TICKS)
	_expect(fixture.actor.brain.state != StoneGolemBrainType.State.SLAM_AIRBORNE, "blocked launch ignored ceiling clearance")
	_expect(fixture.actor.on_ground, "ceiling-aborted slam left the Stone Golem airborne")
	_expect(not fixture.actor._slam_contact_pending, "ceiling-aborted slam retained pending contact")
	_expect(_radial_source_ids.is_empty() and _outcomes.is_empty(), "ceiling-aborted slam emitted contact")
	_expect(is_equal_approx(fixture.player_stats.current_hp, hp_before), "ceiling-aborted slam damaged the player")
	_tick(fixture, 250)
	_expect(_radial_source_ids.is_empty() and _outcomes.is_empty(), "ceiling-aborted slam emitted delayed contact")
	_expect(is_equal_approx(fixture.player_stats.current_hp, hp_before), "ceiling-aborted slam dealt delayed damage")
	_expect(fixture.dust.get_play_count() == 0, "ceiling-aborted slam played landing dust")
	await _cleanup_fixture(fixture)

func _test_obstructed_landing() -> void:
	var fixture := _create_fixture(Vector3(3.5, FEET_Y, 0.5))
	if fixture.actor == null:
		await _cleanup_fixture(fixture)
		return
	if not _start_slam(fixture):
		await _cleanup_fixture(fixture)
		return
	var locked_target := fixture.actor.brain.get_locked_slam_target()
	fixture.world.restore_block_edits(_make_wall(), {})
	var hp_before := fixture.player_stats.current_hp
	if not _advance_to_airborne(fixture):
		await _cleanup_fixture(fixture)
		return
	var flight_ticks := 0
	while fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE and flight_ticks < MAX_FLIGHT_TICKS:
		_expect(fixture.actor.brain.get_locked_slam_target().is_equal_approx(locked_target), "obstructed flight changed its locked target")
		_tick(fixture)
		flight_ticks += 1
	var landing_offset := fixture.actor.global_position - locked_target
	landing_offset.y = 0.0
	_expect(fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_RECOVERY, "obstructed slam did not enter recovery at actual landing")
	_expect(landing_offset.length() > 1.0, "horizontal obstruction did not move actual landing away from the locked target")
	_expect(fixture.actor.global_position.x < 2.0 and fixture.world.is_solid(Vector3i(2, 8, 0)), "actual landing was not stopped before the wall")
	_expect(_radial_source_ids.size() == 1 and _radial_source_ids[0] == fixture.runtime_id, "obstructed landing did not emit exactly one radial contact")
	_expect(_outcomes.is_empty() and is_equal_approx(fixture.player_stats.current_hp, hp_before), "obstructed landing damaged through the wall")
	_expect(fixture.dust.get_play_count() == 1, "obstructed actual landing did not play exactly one dust burst")
	_expect(fixture.dust.global_position.is_equal_approx(fixture.actor.global_position), "obstructed dust did not use the actual landing position")
	var recovery_ticks := _advance_through_recovery(fixture)
	_expect(recovery_ticks == 76, "obstructed landing did not preserve 0.75-second recovery")
	_tick(fixture, 20)
	_expect(_radial_source_ids.size() == 1 and _outcomes.is_empty(), "obstructed recovery emitted duplicate contact")
	_expect(fixture.dust.get_play_count() == 1, "obstructed recovery replayed landing dust")
	await _cleanup_fixture(fixture)

func _test_dodge_recovery_and_cooldown() -> void:
	var fixture := _create_fixture(Vector3(1.5, FEET_Y, 0.5))
	if fixture.actor == null:
		await _cleanup_fixture(fixture)
		return
	if not _start_slam(fixture):
		await _cleanup_fixture(fixture)
		return
	var locked_target := fixture.actor.brain.get_locked_slam_target()
	fixture.player.global_position = Vector3(5.5, FEET_Y, 0.5)
	var hp_before := fixture.player_stats.current_hp
	if not _advance_to_airborne(fixture):
		await _cleanup_fixture(fixture)
		return
	var flight_ticks := _advance_to_landing(fixture)
	var landing_offset := fixture.actor.global_position - locked_target
	landing_offset.y = 0.0
	_expect(landing_offset.length() < 0.02, "dodged slam did not land at its takeoff-locked target")
	_expect(_radial_source_ids.size() == 1 and _radial_source_ids[0] == fixture.runtime_id, "dodged slam did not emit exactly one landing contact")
	_expect(_outcomes.is_empty() and is_equal_approx(fixture.player_stats.current_hp, hp_before), "takeoff-locked slam damaged the player after a dodge")
	_expect(fixture.dust.get_play_count() == 1, "dodged actual landing did not play exactly one dust burst")
	_expect(fixture.dust.global_position.is_equal_approx(fixture.actor.global_position), "dodged slam dust did not stay at its actual landing")
	var recovery_ticks := _advance_through_recovery(fixture)
	_expect(recovery_ticks == 76, "dodged slam did not preserve 0.75-second recovery")
	var ticks_since_start := WINDUP_TICKS + flight_ticks + recovery_ticks
	while ticks_since_start < 399:
		fixture.player.global_position = fixture.actor.global_position + Vector3.RIGHT * 4.0
		_tick(fixture)
		ticks_since_start += 1
		_expect(fixture.actor.brain.state != StoneGolemBrainType.State.SLAM_WINDUP, "slam restarted before its four-second cooldown")
	var restart_target := fixture.player.global_position
	for _sample_tick in range(MAX_VISIBILITY_TICKS):
		fixture.player.global_position = fixture.actor.global_position + Vector3.RIGHT * 4.0
		restart_target = fixture.player.global_position
		_tick(fixture)
		ticks_since_start += 1
		if fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_WINDUP:
			break
	_expect(ticks_since_start >= 400, "slam restarted before four seconds elapsed")
	_expect(fixture.actor.brain.state == StoneGolemBrainType.State.SLAM_WINDUP, "slam did not become eligible after its four-second cooldown")
	_expect(fixture.actor.brain.get_locked_slam_target().is_equal_approx(restart_target), "post-cooldown slam did not lock its fresh target")
	_expect(_radial_source_ids.size() == 1 and _outcomes.is_empty(), "cooldown tracking emitted an extra contact")
	_expect(fixture.dust.get_play_count() == 1, "slam cooldown replayed landing dust")
	await _cleanup_fixture(fixture)

func _test_death_during_windup() -> void:
	var fixture := _create_fixture(Vector3(1.5, FEET_Y, 0.5))
	if fixture.actor == null:
		await _cleanup_fixture(fixture)
		return
	if not _start_slam(fixture):
		await _cleanup_fixture(fixture)
		return
	var hp_before := fixture.player_stats.current_hp
	var damage_result := fixture.runtime.try_apply_damage(fixture.runtime_id, 1000.0)
	_expect(damage_result != null and damage_result.defeated, "windup death fixture did not defeat the Stone Golem")
	_expect(fixture.runtime.get_actor(fixture.runtime_id) == null, "windup death left the Stone Golem active")
	_expect(not fixture.actor._slam_contact_pending, "windup death did not cancel pending contact")
	_tick(fixture, 250)
	_expect(_radial_source_ids.is_empty() and _outcomes.is_empty(), "windup death emitted delayed slam contact")
	_expect(is_equal_approx(fixture.player_stats.current_hp, hp_before), "windup death dealt delayed player damage")
	_expect(fixture.dust.get_play_count() == 0, "windup death played landing dust")
	await _cleanup_fixture(fixture)

func _test_death_during_airborne() -> void:
	var fixture := _create_fixture(Vector3(1.5, FEET_Y, 0.5))
	if fixture.actor == null:
		await _cleanup_fixture(fixture)
		return
	if not _start_slam(fixture) or not _advance_to_airborne(fixture):
		await _cleanup_fixture(fixture)
		return
	_tick(fixture, 5)
	_expect(fixture.actor._slam_contact_pending, "airborne death fixture did not arm slam contact")
	var hp_before := fixture.player_stats.current_hp
	var damage_result := fixture.runtime.try_apply_damage(fixture.runtime_id, 1000.0)
	_expect(damage_result != null and damage_result.defeated, "airborne death fixture did not defeat the Stone Golem")
	_expect(fixture.runtime.get_actor(fixture.runtime_id) == null, "airborne death left the Stone Golem active")
	_expect(not fixture.actor._slam_contact_pending, "airborne death did not cancel pending contact")
	_tick(fixture, 250)
	_expect(_radial_source_ids.is_empty() and _outcomes.is_empty(), "airborne death emitted delayed slam contact")
	_expect(is_equal_approx(fixture.player_stats.current_hp, hp_before), "airborne death dealt delayed player damage")
	_expect(fixture.dust.get_play_count() == 0, "airborne death played landing dust")
	await _cleanup_fixture(fixture)

func _test_despawn_during_airborne() -> void:
	var fixture := _create_fixture(Vector3(1.5, FEET_Y, 0.5))
	if fixture.actor == null:
		await _cleanup_fixture(fixture)
		return
	if not _start_slam(fixture) or not _advance_to_airborne(fixture):
		await _cleanup_fixture(fixture)
		return
	_tick(fixture, 5)
	_expect(fixture.actor._slam_contact_pending, "airborne despawn fixture did not arm slam contact")
	var hp_before := fixture.player_stats.current_hp
	_expect(fixture.runtime.try_despawn(fixture.runtime_id), "airborne Stone Golem could not despawn")
	_expect(fixture.runtime.get_actor(fixture.runtime_id) == null, "despawned Stone Golem remained active")
	_expect(not fixture.actor._slam_contact_pending, "airborne despawn did not cancel pending contact")
	_tick(fixture, 100)
	_expect(_radial_source_ids.is_empty() and _outcomes.is_empty(), "airborne despawn emitted delayed slam contact")
	_expect(is_equal_approx(fixture.player_stats.current_hp, hp_before), "airborne despawn dealt delayed player damage")
	_expect(fixture.dust.get_play_count() == 0, "airborne despawn played landing dust")
	await _cleanup_fixture(fixture)

func _run() -> void:
	await _test_ceiling_abort()
	await _test_obstructed_landing()
	await _test_dodge_recovery_and_cooldown()
	await _test_death_during_windup()
	await _test_death_during_airborne()
	await _test_despawn_during_airborne()
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "Stone Golem slam hardening ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("STONE_GOLEM_SLAM_HARDENING_INTEGRATION PASS")
		quit(0)
	else:
		print("STONE_GOLEM_SLAM_HARDENING_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
