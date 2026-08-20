extends SceneTree

const WatcherTeleportSearchType := preload("res://entities/watcher/watcher_teleport_search.gd")
const MeleeContactType := preload("res://combat/melee_contact.gd")
const MeleeOutcomeType := preload("res://combat/melee_outcome.gd")
const ProjectileContactType := preload("res://combat/projectiles/projectile_contact.gd")
const ProjectileOutcomeType := preload("res://combat/projectiles/projectile_outcome.gd")

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const WORLD_RADIUS: int = 24
const PLAYER_POSITION := Vector3(0.5, FEET_Y, 0.5)

class TestScreenEffect:
	extends WatcherScreenEffect

	var active: bool = false
	var transitions: Array[bool] = []

	func set_active(value: bool) -> void:
		if active == value:
			return
		active = value
		transitions.append(value)

var _failures: int = 0
var _positions_ready: bool = true

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var world := _make_world()
	var runtime := EntityRuntime.new()
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var effect := TestScreenEffect.new()
	var coordinator := WatcherEncounterCoordinator.new()
	root.add_child(runtime)
	root.add_child(player)
	root.add_child(coordinator)
	player.global_position = PLAYER_POSITION
	player.set_physics_process(false)
	player.interactor.set_physics_process(false)
	player.animation_driver.set_process(false)
	runtime.setup(
		_make_catalog(),
		world,
		8,
		4,
		EntityNavigationLimits.new(24, 256, 2),
	)
	coordinator.setup(player, effect)
	coordinator.bind_context(world, runtime, _position_ready)
	var runtime_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"watcher", Vector3(3.5, FEET_Y, 0.5), 8117),
		EntitySpawnRequest.new(&"watcher", Vector3(-12.5, FEET_Y, -12.5), 9921),
	])
	_expect(runtime_ids == [1, 2], "watcher fixture did not receive stable runtime IDs")
	if runtime_ids == [1, 2]:
		_test_provocation_teleport_and_reset(coordinator, runtime, player, effect, runtime_ids)
		_test_removal_lifecycle(coordinator, runtime, effect, runtime_ids)
	coordinator.unbind_context()
	runtime.shutdown()
	coordinator.queue_free()
	player.queue_free()
	runtime.queue_free()
	effect.free()
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "encounter test changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if _failures == 0:
		print("WATCHER_ENCOUNTER_COORDINATOR PASS")
		quit(0)
	else:
		print("WATCHER_ENCOUNTER_COORDINATOR FAIL failures=%d" % _failures)
		quit(1)

func _test_provocation_teleport_and_reset(
	coordinator: WatcherEncounterCoordinator,
	runtime: EntityRuntime,
	player: PlayerMotor,
	effect: TestScreenEffect,
	runtime_ids: Array[int],
) -> void:
	var first := runtime.get_actor(runtime_ids[0]) as WatcherActor
	var second := runtime.get_actor(runtime_ids[1]) as WatcherActor
	var first_origin := first.global_position
	_expect(first.try_begin_player_hit_response(player.global_position), "pre-damage response did not immediately provoke watcher")
	_expect(first.get_teleport_sequence() == 0, "pre-damage response consumed a committed-hit teleport sequence")
	var blocked_candidates := WatcherTeleportSearchType.find_candidates(
		first.voxel_space,
		first.definition,
		first.behavior_seed,
		1,
		player.global_position,
		player.get_world_bounds(),
		first_origin,
		_position_ready,
	)
	_expect(not blocked_candidates.is_empty(), "occupied-candidate fixture had no teleport destination")
	if not blocked_candidates.is_empty():
		_expect(runtime.try_relocate_actor(second.runtime_id, blocked_candidates[0]), "blocker could not be positioned")
	coordinator.record_melee_outcome(_player_outcome(first.runtime_id))
	_expect(first.is_aggressive(), "nonlethal player hit did not provoke watcher")
	_expect(first.get_teleport_sequence() == 1, "first hit did not advance teleport sequence")
	_expect(coordinator.get_tracked_count() == 1, "provoked watcher was not tracked")
	_expect(effect.active and effect.transitions == [true], "first provocation did not activate one shared effect")
	_expect(not first.global_position.is_equal_approx(first_origin), "first hit did not teleport watcher")
	if not blocked_candidates.is_empty():
		_expect(not first.global_position.is_equal_approx(blocked_candidates[0]), "teleport accepted an entity-occupied candidate")
	var previous_bearing := _bearing(first_origin, player.global_position)
	var new_bearing := _bearing(first.global_position, player.global_position)
	_expect(previous_bearing.dot(new_bearing) <= 0.000001, "teleport did not change bearing by at least 90 degrees")
	_expect(runtime.get_active_runtime_ids_overlapping(first.get_world_bounds()).has(first.runtime_id), "teleport destination was missing from the spatial index")
	var first_teleport_position := first.global_position
	coordinator.record_melee_outcome(_player_outcome(first.runtime_id))
	_expect(first.get_teleport_sequence() == 2, "repeat hit did not advance teleport sequence")
	_expect(not first.global_position.is_equal_approx(first_teleport_position), "repeat hit did not teleport watcher")
	_expect(coordinator.get_tracked_count() == 1 and effect.transitions == [true], "repeat hit duplicated encounter ownership")
	_positions_ready = false
	var failed_origin := first.global_position
	first.velocity = Vector3(3.0, 2.0, 1.0)
	first.knockback_velocity = Vector3.RIGHT * 5.0
	coordinator.record_melee_outcome(_player_outcome(first.runtime_id))
	_expect(first.get_teleport_sequence() == 3, "failed teleport attempt did not advance sequence")
	_expect(first.global_position.is_equal_approx(failed_origin), "unready teleport search moved watcher")
	_expect(first.velocity.is_zero_approx() and first.knockback_velocity.is_zero_approx(), "failed teleport did not clear hit motion")
	_expect(first.is_aggressive() and coordinator.get_tracked_count() == 1 and effect.active, "failed teleport ended aggression")
	_positions_ready = true
	var second_sequence := second.get_teleport_sequence()
	coordinator.record_melee_outcome(_nonplayer_outcome(second.runtime_id))
	_expect(second.get_teleport_sequence() == second_sequence and coordinator.get_tracked_count() == 1, "nonplayer outcome provoked watcher")
	coordinator.record_melee_outcome(_lethal_player_outcome(second.runtime_id))
	_expect(second.get_teleport_sequence() == second_sequence and coordinator.get_tracked_count() == 1, "lethal outcome provoked watcher")
	coordinator.record_melee_outcome(_player_outcome(second.runtime_id))
	_expect(second.is_aggressive() and coordinator.get_tracked_count() == 2, "second watcher was not independently tracked")
	var hp_before_reset := runtime.get_current_hp(first.runtime_id)
	runtime.suspend()
	coordinator.reset_for_player_defeat([runtime])
	runtime.resume()
	_expect(not first.is_aggressive() and not second.is_aggressive(), "player defeat did not calm every watcher")
	_expect(is_equal_approx(runtime.get_current_hp(first.runtime_id), hp_before_reset), "player defeat healed watcher")
	_expect(coordinator.get_tracked_count() == 0 and not effect.active, "player defeat did not clear encounter effect")

func _test_removal_lifecycle(
	coordinator: WatcherEncounterCoordinator,
	runtime: EntityRuntime,
	effect: TestScreenEffect,
	runtime_ids: Array[int],
) -> void:
	coordinator.record_projectile_outcome(_projectile_outcome(runtime_ids[0]))
	coordinator.record_melee_outcome(_player_outcome(runtime_ids[1]))
	_expect(coordinator.get_tracked_count() == 2 and effect.active, "melee and projectile hits did not track both watchers")
	_expect(runtime.try_despawn(runtime_ids[0]), "tracked watcher despawn was rejected")
	_expect(coordinator.get_tracked_count() == 1 and effect.active, "ordinary removal ended a multi-watcher encounter")
	var damage_result := runtime.try_apply_damage(runtime_ids[1], 1000.0)
	_expect(damage_result != null and damage_result.defeated, "tracked watcher defeat was rejected")
	_expect(coordinator.get_tracked_count() == 0 and not effect.active, "final watcher removal did not end effect")
	var rebound_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"watcher", Vector3(3.5, FEET_Y, 0.5), 1771),
	])
	_expect(rebound_ids.size() == 1, "unbind fixture could not spawn watcher")
	if rebound_ids.size() == 1:
		var rebound := runtime.get_actor(rebound_ids[0]) as WatcherActor
		coordinator.record_melee_outcome(_player_outcome(rebound.runtime_id))
		coordinator.unbind_context()
		_expect(rebound.is_aggressive(), "context unbind cleared permanent Watcher aggression")
		_expect(coordinator.get_tracked_count() == 0 and not effect.active, "context unbind retained encounter ownership")
		coordinator.bind_context(rebound.voxel_space, runtime, _position_ready)
		_expect(rebound.is_aggressive(), "context rebind cleared permanent Watcher aggression")
		_expect(coordinator.get_tracked_count() == 1 and effect.active, "context rebind did not restore the hostile Watcher encounter")
		coordinator.reset_for_player_defeat([runtime])

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	return world

func _make_catalog() -> EntityCatalog:
	var catalog := EntityCatalog.new()
	catalog.definitions = [load("res://entities/definitions/watcher.tres") as EntityDefinition]
	return catalog

func _position_ready(_position: Vector3) -> bool:
	return _positions_ready

func _player_outcome(runtime_id: int) -> MeleeOutcome:
	return _outcome(
		MeleeCombatCoordinator.PLAYER_RUNTIME_ID,
		MeleeCombatCoordinator.PLAYER_DEFINITION_ID,
		runtime_id,
		&"watcher",
		false,
	)

func _lethal_player_outcome(runtime_id: int) -> MeleeOutcome:
	return _outcome(
		MeleeCombatCoordinator.PLAYER_RUNTIME_ID,
		MeleeCombatCoordinator.PLAYER_DEFINITION_ID,
		runtime_id,
		&"watcher",
		true,
	)

func _nonplayer_outcome(runtime_id: int) -> MeleeOutcome:
	return _outcome(91, &"watcher", runtime_id, &"watcher", false)

func _projectile_outcome(runtime_id: int) -> ProjectileOutcome:
	var contact := ProjectileContactType.new(
		runtime_id,
		&"watcher",
		PLAYER_POSITION,
		Vector3.RIGHT,
	)
	return ProjectileOutcomeType.new(contact, &"bow", 1.0, false, DamageAffinityDefinition.Response.NEUTRAL)

func _outcome(
	source_runtime_id: int,
	source_definition_id: StringName,
	target_runtime_id: int,
	target_definition_id: StringName,
	target_defeated: bool,
) -> MeleeOutcome:
	var contact := MeleeContactType.new(
		source_runtime_id,
		source_definition_id,
		target_runtime_id,
		target_definition_id,
		&"watcher_test",
		PLAYER_POSITION,
		Vector3.RIGHT,
	)
	return MeleeOutcomeType.new(contact, &"", 1.0, target_defeated, DamageAffinityDefinition.Response.NEUTRAL)

func _bearing(position: Vector3, player_position: Vector3) -> Vector2:
	return Vector2(position.x - player_position.x, position.z - player_position.z).normalized()

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[watcher_encounter_coordinator] FAIL: %s" % message)
