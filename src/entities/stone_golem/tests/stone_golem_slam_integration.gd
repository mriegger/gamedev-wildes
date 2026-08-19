extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")
const StoneGolemLandingMarkerType := preload("res://entities/stone_golem/stone_golem_landing_marker.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 16
const FIXED_DELTA: float = 0.01
const WINDUP_TICKS: int = 60
const NOMINAL_FLIGHT_SECONDS: float = 0.8
const MAX_FLIGHT_TICKS: int = 82
const PUNCH_CONTACT_TICKS: int = 46

var _failures: int = 0
var _radial_source_ids: Array[int] = []
var _radial_profile_ids: Array[StringName] = []
var _outcomes: Array[MeleeOutcome] = []

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_slam_integration] FAIL: %s" % message)

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

func _tick(runtime: EntityRuntime, player: PlayerMotor, count: int = 1) -> void:
	for _tick_index in range(count):
		runtime.tick(FIXED_DELTA, _observation(player.global_position))

func _record_radial_contact(source_runtime_id: int, profile: MeleeAttackProfile) -> void:
	_radial_source_ids.append(source_runtime_id)
	_radial_profile_ids.append(profile.id)

func _record_outcome(outcome: MeleeOutcome) -> void:
	_outcomes.append(outcome)

func _run() -> void:
	var slam_profile := load("res://combat/profiles/stone_golem_slam.tres") as MeleeAttackProfile
	var punch_profile := load("res://combat/profiles/stone_golem_punch.tres") as MeleeAttackProfile
	_expect(slam_profile != null and slam_profile.validate(slam_profile.resource_path), "Stone Golem slam profile was invalid")
	_expect(punch_profile != null and punch_profile.validate(punch_profile.resource_path), "Stone Golem punch profile was invalid")
	_expect(
		slam_profile.id == &"stone_golem_slam"
		and is_equal_approx(slam_profile.duration, 2.15)
		and is_equal_approx(slam_profile.contact_time, 1.4)
		and is_equal_approx(slam_profile.cooldown, 4.0)
		and is_equal_approx(slam_profile.reach, 1.0)
		and is_equal_approx(slam_profile.base_damage, 20.0),
		"Stone Golem slam timing, radius, or damage changed",
	)

	var world := _make_world()
	var runtime := EntityRuntime.new()
	var combat := MeleeCombatCoordinator.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	get_root().add_child(runtime)
	get_root().add_child(combat)
	get_root().add_child(player)
	player.global_position = Vector3(1.5, FEET_Y, 0.5)
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	runtime.setup(_make_catalog(), world, 1, 2, EntityNavigationLimits.new(32, 512, 2))
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(player_stats.set_base_value(&"defense", 0.0), "unarmored player defense setup failed")
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var player_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	combat.setup(world, player, player_stats, player_inventory, runtime)
	runtime.entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	runtime.entity_radial_contact_reached.connect(_record_radial_contact)
	runtime.entity_radial_contact_reached.connect(combat.try_commit_entity_radial_contact)
	combat.melee_outcome_committed.connect(runtime.record_melee_outcome)
	combat.melee_outcome_committed.connect(_record_outcome)
	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"stone_golem", Vector3(0.5, FEET_Y, 0.5), 7301),
	])
	_expect(runtime_ids.size() == 1, "production runtime did not spawn the Stone Golem")
	if runtime_ids.size() != 1:
		await _cleanup(combat, runtime, player)
		_finish()
		return

	var runtime_id := runtime_ids[0]
	var actor := runtime.get_actor(runtime_id) as StoneGolemActorType
	actor.set_process(false)
	actor.on_ground = true
	for _sample_tick in range(16):
		_tick(runtime, player)
		if actor.brain.state == StoneGolemBrainType.State.SLAM_WINDUP:
			break
	_expect(actor.brain.state == StoneGolemBrainType.State.SLAM_WINDUP, "fresh visible in-range player did not prioritize slam")
	_expect(not actor._timed_melee_contact.is_pending(), "slam priority incorrectly armed the fallback punch")
	var marker := actor.get_node(^"LandingMarker") as StoneGolemLandingMarkerType
	var locked_target := player.global_position
	var takeoff_position := actor.global_position
	_expect(marker.visible and marker.global_position.is_equal_approx(locked_target), "slam marker did not appear at the locked target")
	_expect(actor.brain.get_locked_slam_target().is_equal_approx(locked_target), "slam brain did not retain the takeoff target")
	actor.animation_driver.advance(0.0)
	_expect(
		(actor.animation_driver as StoneGolemAnimationDriverType).get_current_state() == StoneGolemAnimationDriverType.SLAM_WINDUP,
		"production slam did not select windup presentation",
	)

	player.global_position += Vector3(0.0, 0.0, 0.5)
	_tick(runtime, player, WINDUP_TICKS - 1)
	_expect(actor.brain.state == StoneGolemBrainType.State.SLAM_WINDUP, "slam launched before its 0.6-second windup")
	_expect(actor.global_position.is_equal_approx(takeoff_position), "Stone Golem moved during slam windup")
	_expect(marker.visible and marker.global_position.is_equal_approx(locked_target), "moving player changed the takeoff-locked marker")
	_expect(actor.brain.get_locked_slam_target().is_equal_approx(locked_target), "moving player changed the locked slam target")
	_tick(runtime, player)
	_expect(actor.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE, "slam did not launch at the 0.6-second boundary")
	_expect(not actor.on_ground and actor.global_position.is_equal_approx(takeoff_position), "slam launch did not begin from the grounded takeoff position")

	var hp_before_slam := player_stats.current_hp
	var flight_ticks := 0
	var rose_during_flight := false
	while actor.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE and flight_ticks < MAX_FLIGHT_TICKS:
		_tick(runtime, player)
		flight_ticks += 1
		rose_during_flight = rose_during_flight or actor.global_position.y > takeoff_position.y
		if actor.brain.state == StoneGolemBrainType.State.SLAM_AIRBORNE:
			_expect(_radial_source_ids.is_empty() and _outcomes.is_empty(), "slam contacted before actual landing")
			_expect(marker.visible and marker.global_position.is_equal_approx(locked_target), "airborne slam changed its landing marker")
	_expect(rose_during_flight, "solver-backed slam did not rise after launch")
	_expect(
		absf(float(flight_ticks) * FIXED_DELTA - NOMINAL_FLIGHT_SECONDS) <= FIXED_DELTA + 0.0001,
		"slam flight diverged from its nominal 0.8 seconds",
	)
	_expect(actor.brain.state == StoneGolemBrainType.State.SLAM_RECOVERY, "grounded slam did not enter recovery")
	_expect(actor.on_ground and is_equal_approx(actor.global_position.y, FEET_Y), "slam did not finish at an actual grounded voxel-solver landing")
	var landing_planar_offset := actor.global_position - locked_target
	landing_planar_offset.y = 0.0
	_expect(landing_planar_offset.length() < 0.02, "nominal slam did not land at the takeoff-locked target")
	_expect(not marker.visible, "landing marker remained visible after actual landing")
	_expect(_radial_source_ids.size() == 1 and _radial_source_ids[0] == runtime_id, "runtime did not forward exactly one radial contact")
	_expect(_radial_profile_ids.size() == 1 and _radial_profile_ids[0] == slam_profile.id, "runtime forwarded the wrong radial profile")
	_expect(_outcomes.size() == 1, "actual slam landing did not commit exactly one combat outcome")
	_expect(is_equal_approx(player_stats.current_hp, hp_before_slam - 30.0), "slam did not deal 30 unarmored damage within one block")
	if _outcomes.size() == 1:
		var slam_outcome := _outcomes[0]
		_expect(slam_outcome.contact.attack_id == slam_profile.id and is_equal_approx(slam_outcome.applied_damage, 30.0), "slam combat outcome payload was invalid")

	var recovery_ticks := 0
	while actor.brain.state == StoneGolemBrainType.State.SLAM_RECOVERY and recovery_ticks < 100:
		_tick(runtime, player)
		recovery_ticks += 1
	_expect(recovery_ticks == 76, "slam recovery did not retain its 0.75-second completion tick")
	var punch_wait_ticks := 0
	while actor.brain.state != StoneGolemBrainType.State.PUNCH and punch_wait_ticks < 14:
		_expect(actor.brain.state != StoneGolemBrainType.State.SLAM_WINDUP, "Stone Golem restarted slam before its four-second cooldown")
		_tick(runtime, player)
		punch_wait_ticks += 1
	_expect(actor.brain.state == StoneGolemBrainType.State.PUNCH, "visible in-range player did not fall back to punch during slam cooldown")
	_expect(actor._timed_melee_contact.is_pending(), "slam-cooldown fallback punch did not arm timed contact")
	_expect(_radial_source_ids.size() == 1 and _outcomes.size() == 1, "slam recovery emitted duplicate contact")
	var hp_before_punch := player_stats.current_hp
	_tick(runtime, player, PUNCH_CONTACT_TICKS - 1)
	_expect(_outcomes.size() == 1 and is_equal_approx(player_stats.current_hp, hp_before_punch), "fallback punch contacted before its contact time")
	_tick(runtime, player)
	_expect(_outcomes.size() == 2, "fallback punch did not commit through production combat")
	_expect(is_equal_approx(player_stats.current_hp, hp_before_punch - 15.0), "slam-cooldown fallback punch did not deal 15 unarmored damage")
	if _outcomes.size() == 2:
		var punch_outcome := _outcomes[1]
		_expect(punch_outcome.contact.attack_id == punch_profile.id and is_equal_approx(punch_outcome.applied_damage, 15.0), "fallback punch combat outcome payload was invalid")
	_expect(_radial_source_ids.size() == 1, "fallback punch emitted another radial contact")

	await _cleanup(combat, runtime, player)
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "Stone Golem slam integration ended with %d orphan nodes" % orphan_count)
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
		print("STONE_GOLEM_SLAM_INTEGRATION PASS")
		quit(0)
	else:
		print("STONE_GOLEM_SLAM_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
