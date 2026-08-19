extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")
const MeleeContactType := preload("res://combat/melee_contact.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 16
const CONTACT_EPSILON: float = 0.001

var _failures: int = 0
var _contacts: Array[MeleeContactType] = []
var _outcomes: Array[MeleeOutcome] = []

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_punch_integration] FAIL: %s" % message)

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

func _tick(runtime: EntityRuntime, delta: float, player: PlayerMotor) -> void:
	runtime.tick(delta, _observation(player.global_position))

func _record_outcome(outcome: MeleeOutcome) -> void:
	_outcomes.append(outcome)
	_contacts.append(outcome.contact)

func _position_for_punch(actor: StoneGolemActorType, player: PlayerMotor) -> void:
	actor.global_position = player.global_position + Vector3(0.0, 0.0, -1.0)
	actor.velocity = Vector3.ZERO
	actor.on_ground = true

func _hold_slam_cooldown(actor: StoneGolemActorType) -> void:
	var behavior := actor.definition.behavior as StoneGolemBehaviorDefinition
	assert(behavior != null)
	actor.brain._slam_cooldown_remaining = behavior.slam_profile.cooldown * 10.0

func _complete_cooldown_and_start_next(
	runtime: EntityRuntime,
	actor: StoneGolemActorType,
	player: PlayerMotor,
	profile: MeleeAttackProfile,
) -> void:
	_tick(runtime, profile.duration - profile.contact_time, player)
	_expect(actor.brain.state == StoneGolemBrainType.State.PUNCH, "punch did not retain its duration completion tick")
	_tick(runtime, profile.cooldown - profile.duration - VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS - CONTACT_EPSILON, player)
	_expect(actor.brain.state != StoneGolemBrainType.State.PUNCH, "punch restarted before its 1.4-second cooldown")
	_position_for_punch(actor, player)
	_tick(runtime, VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS + CONTACT_EPSILON, player)
	_expect(actor.brain.state == StoneGolemBrainType.State.PUNCH, "punch did not restart at its cooldown boundary")
	_expect(actor._timed_melee_contact.is_pending(), "restarted punch did not arm timed contact")

func _run() -> void:
	var profile := load("res://combat/profiles/stone_golem_punch.tres") as MeleeAttackProfile
	_expect(profile != null and profile.validate(profile.resource_path), "Stone Golem punch profile was invalid")
	_expect(profile.id == &"stone_golem_punch", "Stone Golem punch ID changed")
	_expect(
		is_equal_approx(profile.duration, 0.8)
		and is_equal_approx(profile.contact_time, 0.46)
		and is_equal_approx(profile.cooldown, 1.4)
		and is_equal_approx(profile.reach, 1.5)
		and is_equal_approx(profile.base_damage, 5.0),
		"Stone Golem punch timing, reach, or damage changed",
	)
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
	var catalog := _make_catalog()
	runtime.setup(catalog, world, 1, 2, EntityNavigationLimits.new(32, 512, 2))
	var player_stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_expect(player_stats.set_base_value(&"defense", 0.0), "unarmored player defense setup failed")
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var player_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	combat.setup(world, player, player_stats, player_inventory, runtime, load("res://combat/damage/damage_type_catalog.tres") as DamageTypeCatalog)
	runtime.entity_melee_contact_reached.connect(combat.try_commit_entity_contact)
	combat.melee_outcome_committed.connect(runtime.record_melee_outcome)
	combat.melee_outcome_committed.connect(_record_outcome)
	var spawn_position := player.global_position + Vector3(0.0, 0.0, -1.0)
	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"stone_golem", spawn_position, 5511),
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
	_hold_slam_cooldown(actor)
	_tick(runtime, VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS, player)
	_expect(actor.brain.state == StoneGolemBrainType.State.PUNCH, "visible in-range player did not start a production punch")
	_expect(actor._timed_melee_contact.is_pending(), "production punch did not arm timed contact")
	actor.animation_driver.advance(0.0)
	_expect(
		(actor.animation_driver as StoneGolemAnimationDriverType).get_current_state() == StoneGolemAnimationDriverType.PUNCH,
		"production punch did not select PUNCH presentation",
	)

	var contacts_before := _contacts.size()
	var hp_before := player_stats.current_hp
	var half_contact := profile.contact_time * 0.5
	_tick(runtime, half_contact, player)
	_expect(_contacts.size() == contacts_before, "Stone Golem punch contacted before contact time")
	_expect(is_equal_approx(player_stats.current_hp, hp_before), "Stone Golem punch damaged the player before contact time")
	_tick(runtime, half_contact, player)
	_expect(_contacts.size() == contacts_before + 1, "Stone Golem punch did not contact at contact time")
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 15.0), "Stone Golem punch did not deal 15 unarmored damage")
	var contact: MeleeContactType = _contacts.back()
	var outcome: MeleeOutcome = _outcomes.back()
	_expect(
		contact.source_runtime_id == runtime_id
		and contact.source_definition_id == &"stone_golem"
		and contact.target_runtime_id == 0
		and contact.target_definition_id == &"player"
		and contact.attack_id == profile.id,
		"Stone Golem punch contact payload was invalid",
	)
	_expect(is_equal_approx(outcome.applied_damage, 15.0), "Stone Golem unarmored outcome recorded incorrect damage")
	_tick(runtime, profile.duration, player)
	_expect(_contacts.size() == contacts_before + 1, "one Stone Golem punch contacted more than once")
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 15.0), "one Stone Golem punch damaged the player more than once")

	var cooldown_remaining := profile.cooldown - profile.contact_time - profile.duration
	_tick(runtime, cooldown_remaining - VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS - CONTACT_EPSILON, player)
	_expect(actor.brain.state != StoneGolemBrainType.State.PUNCH, "Stone Golem punch restarted before cooldown elapsed")
	_position_for_punch(actor, player)
	_tick(runtime, VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS + CONTACT_EPSILON, player)
	_expect(actor.brain.state == StoneGolemBrainType.State.PUNCH, "Stone Golem punch did not restart at 1.4 seconds")
	_expect(actor._timed_melee_contact.is_pending(), "cooldown-boundary punch did not arm contact")

	contacts_before = _contacts.size()
	hp_before = player_stats.current_hp
	player.global_position = actor.global_position + Vector3(3.0, 0.0, 0.0)
	_tick(runtime, profile.contact_time, player)
	_expect(_contacts.size() == contacts_before, "out-of-range timed Stone Golem contact committed")
	_expect(is_equal_approx(player_stats.current_hp, hp_before), "out-of-range timed contact changed player HP")
	player.global_position = actor.global_position + Vector3(0.0, 0.0, 1.0)
	_complete_cooldown_and_start_next(runtime, actor, player, profile)

	contacts_before = _contacts.size()
	hp_before = player_stats.current_hp
	var occluding_cell := Vector3i(floori(player.global_position.x), int(FEET_Y), floori(player.global_position.z))
	world.restore_block_edits({occluding_cell: BlockId.Type.STONE}, {})
	_tick(runtime, profile.contact_time, player)
	_expect(_contacts.size() == contacts_before, "voxel-occluded timed Stone Golem contact committed")
	_expect(is_equal_approx(player_stats.current_hp, hp_before), "voxel-occluded timed contact changed player HP")
	world.restore_block_edits({}, {})
	_complete_cooldown_and_start_next(runtime, actor, player, profile)

	_expect(player_stats.set_base_value(&"defense", 4.0), "defended player setup failed")
	_expect(player_stats.set_current_hp(player_stats.get_value(&"hp")), "defended player health reset failed")
	contacts_before = _contacts.size()
	hp_before = player_stats.current_hp
	_tick(runtime, half_contact, player)
	_expect(_contacts.size() == contacts_before, "defended punch contacted before contact time")
	_tick(runtime, half_contact, player)
	_expect(_contacts.size() == contacts_before + 1, "defended punch did not contact at contact time")
	_expect(is_equal_approx(player_stats.current_hp, hp_before - 11.0), "Stone Golem punch did not apply player defense")
	_expect(is_equal_approx((_outcomes.back() as MeleeOutcome).applied_damage, 11.0), "defended punch outcome recorded incorrect damage")
	_complete_cooldown_and_start_next(runtime, actor, player, profile)
	_expect(_contacts.size() == contacts_before + 1, "defended Stone Golem punch contacted more than once")

	_expect(actor._timed_melee_contact.is_pending(), "death cancellation fixture did not retain production contact")
	contacts_before = _contacts.size()
	hp_before = player_stats.current_hp
	var lethal_result := runtime.try_apply_damage(runtime_id, 1000.0)
	_expect(lethal_result != null and lethal_result.defeated, "lethal Stone Golem damage did not commit")
	_expect(runtime.get_actor(runtime_id) == null, "defeated Stone Golem remained active")
	_expect(not actor._timed_melee_contact.is_pending(), "defeated Stone Golem retained pending contact")
	_expect(actor._timed_melee_contact.advance(profile.contact_time) == null, "defeated Stone Golem completed pending contact")
	_expect(_contacts.size() == contacts_before and is_equal_approx(player_stats.current_hp, hp_before), "defeated Stone Golem changed combat state")

	var replacement_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"stone_golem", player.global_position + Vector3(0.0, 0.0, -1.0), 5512),
	])
	_expect(replacement_ids.size() == 1, "despawn cancellation fixture did not spawn replacement")
	if replacement_ids.size() == 1:
		var replacement := runtime.get_actor(replacement_ids[0]) as StoneGolemActorType
		replacement.set_process(false)
		replacement.on_ground = true
		_hold_slam_cooldown(replacement)
		_tick(runtime, VoxelPlayerVisibilitySensor.SAMPLE_INTERVAL_SECONDS, player)
		_expect(replacement.brain.state == StoneGolemBrainType.State.PUNCH, "replacement Stone Golem did not begin punch")
		_expect(replacement._timed_melee_contact.is_pending(), "replacement punch did not arm contact")
		contacts_before = _contacts.size()
		hp_before = player_stats.current_hp
		_expect(runtime.try_despawn(replacement.runtime_id), "replacement Stone Golem could not despawn")
		_expect(not replacement._timed_melee_contact.is_pending(), "despawning Stone Golem retained pending contact")
		_expect(replacement._timed_melee_contact.advance(profile.contact_time) == null, "despawning Stone Golem completed pending contact")
		_expect(_contacts.size() == contacts_before and is_equal_approx(player_stats.current_hp, hp_before), "despawning Stone Golem changed combat state")

	await _cleanup(combat, runtime, player)
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "Stone Golem punch integration ended with %d orphan nodes" % orphan_count)
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
		print("STONE_GOLEM_PUNCH_INTEGRATION PASS")
		quit(0)
	else:
		print("STONE_GOLEM_PUNCH_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
