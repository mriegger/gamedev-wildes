extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 14

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[watcher_behavior] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	return world

func _test_definition() -> void:
	var definition := load("res://entities/definitions/watcher.tres") as EntityDefinition
	_expect(definition != null, "watcher definition did not load")
	if definition == null:
		return
	var behavior := definition.behavior as WatcherBehaviorDefinition
	_expect(definition.validate(definition.resource_path), "watcher definition is invalid")
	_expect(definition.id == &"watcher", "watcher stable ID changed")
	_expect(is_equal_approx(definition.body_width, 0.6) and is_equal_approx(definition.body_height, 2.7), "watcher body dimensions changed")
	_expect(definition.experience_reward == 25 and definition.loot_pool == null, "watcher reward configuration changed")
	_expect(definition.ambient_spawn_phase == EntityDefinition.SpawnPhase.NIGHT, "watcher is not night-spawned")
	_expect(is_equal_approx(definition.ambient_spawn_weight, 10.0) and definition.ambient_max_active == 0, "watcher ambient weight changed")
	_expect(definition.ambient_spawn_floor_ids == [BlockId.Type.GRASS, BlockId.Type.DIRT, BlockId.Type.SAND, BlockId.Type.STONE], "watcher spawn floors changed")
	_expect(not definition.ambient_despawn_outside_spawn_phase, "watcher despawns at dawn")
	_expect(behavior != null and behavior.validate(behavior.resource_path), "watcher behavior is invalid")
	if behavior != null:
		_expect(is_equal_approx(behavior.wander_speed, 1.6) and is_equal_approx(behavior.stalk_speed, 2.2) and is_equal_approx(behavior.sprint_speed, 7.0), "watcher movement speeds changed")
		_expect(is_equal_approx(behavior.detection_range, 16.0) and is_equal_approx(behavior.forget_range, 24.0) and is_equal_approx(behavior.target_memory_seconds, 3.0), "watcher perception changed")
		_expect(is_equal_approx(behavior.stalk_inner_radius, 2.5) and is_equal_approx(behavior.stalk_radius, 3.0) and is_equal_approx(behavior.stalk_outer_radius, 3.5), "watcher stalking band changed")
		_expect(is_equal_approx(behavior.stalk_step_degrees, 45.0) and is_equal_approx(behavior.stalk_pause_seconds, 0.8), "watcher stalking cadence changed")
		_expect(is_equal_approx(behavior.melee_profile.duration, 0.55) and is_equal_approx(behavior.melee_profile.contact_time, 0.28), "watcher attack timing changed")
		_expect(is_equal_approx(behavior.melee_profile.cooldown, 1.0) and is_equal_approx(behavior.melee_profile.reach, 1.5) and is_equal_approx(behavior.melee_profile.base_damage, 10.0), "watcher melee profile changed")
	_expect(is_equal_approx(definition.stats_definition.maximum_hp, 100.0), "watcher HP changed")
	_expect(is_equal_approx(definition.stats_definition.defense, 4.0), "watcher defense changed")
	_expect(is_equal_approx(definition.stats_definition.strength, 6.0), "watcher strength changed")
	_expect(definition.is_actor_compatible(), "watcher actor rejected its definition")

func _test_visual_geometry() -> void:
	var visual_scene := load("res://entities/watcher/watcher_visual.tscn") as PackedScene
	_expect(visual_scene != null, "watcher visual scene did not load")
	if visual_scene == null:
		return
	var visual := visual_scene.instantiate() as BlockyHumanoidAnimator
	_expect(visual != null, "watcher visual did not instantiate as a humanoid animator")
	if visual == null:
		return
	get_root().add_child(visual)
	var torso := visual.get_node(^"RigRoot/BodySecondary/BodyAction/TorsoBase/Torso") as MeshInstance3D
	var head_secondary := visual.get_node(^"RigRoot/BodySecondary/BodyAction/TorsoBase/HeadAnchor/HeadBase/HeadSecondary") as Node3D
	var head := head_secondary.get_node(^"Head") as MeshInstance3D
	var left_arm := visual.get_node(^"RigRoot/BodySecondary/BodyAction/TorsoBase/LeftShoulder/LeftArmBase/LeftArmAction/LeftArm") as MeshInstance3D
	var left_leg := visual.get_node(^"RigRoot/LeftHip/LeftLegLocomotion/LeftLegBase/LeftLeg") as MeshInstance3D
	var torso_size := (torso.mesh as BoxMesh).size
	var head_size := (head.mesh as BoxMesh).size
	var arm_size := (left_arm.mesh as BoxMesh).size
	var leg_size := (left_leg.mesh as BoxMesh).size
	_expect(torso_size.is_equal_approx(Vector3(0.34, 0.9, 0.18)), "watcher torso was not slender")
	_expect(head_size.is_equal_approx(Vector3(0.6, 0.6, 0.6)), "watcher head was not a cube")
	_expect(arm_size.is_equal_approx(Vector3(0.1, 1.35, 0.1)), "watcher arms were not slender")
	_expect(leg_size.is_equal_approx(Vector3(0.12, 1.2, 0.12)), "watcher legs were not slender")
	_expect(head_secondary.get_node_or_null(^"LeftEye") == null and head_secondary.get_node_or_null(^"RightEye") == null, "watcher retained visible eyes")
	var left_shoulder := visual.get_node(^"RigRoot/BodySecondary/BodyAction/TorsoBase/LeftShoulder") as Node3D
	var right_shoulder := visual.get_node(^"RigRoot/BodySecondary/BodyAction/TorsoBase/RightShoulder") as Node3D
	var left_hip := visual.get_node(^"RigRoot/LeftHip") as Node3D
	var right_hip := visual.get_node(^"RigRoot/RightHip") as Node3D
	_expect(left_shoulder.position.is_equal_approx(Vector3(-0.22, 0.9, 0.0)) and right_shoulder.position.is_equal_approx(Vector3(0.22, 0.9, 0.0)), "watcher shoulders were not symmetric")
	_expect(left_hip.position.is_equal_approx(Vector3(-0.07, 1.2, 0.0)) and right_hip.position.is_equal_approx(Vector3(0.07, 1.2, 0.0)), "watcher hips were not symmetric")
	var visual_top := head.global_position.y + head_size.y * 0.5
	var visual_bottom := left_leg.global_position.y - leg_size.y * 0.5
	_expect(is_equal_approx(visual_top - visual_bottom, 2.7) and is_zero_approx(visual_bottom), "watcher visual height did not span exactly 2.7 blocks from its feet")
	var animation_state := ActorAnimationState.new()
	animation_state.grounded = true
	visual.setup(animation_state)
	_expect(visual.animation_state == animation_state and visual.get_current_state() == BlockyHumanoidAnimator.IDLE, "watcher animator setup failed")
	visual.free()

func _test_deterministic_stalking() -> void:
	var behavior := load("res://entities/watcher/watcher_behavior.tres") as WatcherBehaviorDefinition
	var first := WatcherBrain.new(behavior, 4419)
	var second := WatcherBrain.new(behavior, 4419)
	var origin := Vector3(0.5, FEET_Y, 0.5)
	var player := Vector3(3.5, FEET_Y, 0.5)
	first.advance(0.0, origin, player, true)
	second.advance(0.0, origin, player, true)
	_expect(first.state == WatcherBrain.State.STARE, "watcher did not pause after reaching its first ring point")
	_expect(first.get_movement_goal().is_equal_approx(second.get_movement_goal()), "identical seeds produced different stalking goals")
	first.advance(behavior.stalk_pause_seconds - 0.01, origin, player, true)
	_expect(first.state == WatcherBrain.State.STARE, "watcher ended its stare early")
	first.advance(0.02, origin, player, true)
	_expect(first.state == WatcherBrain.State.STALK, "watcher did not resume stalking after its pause")
	var previous_direction := (origin - player).normalized()
	var next_direction := (first.get_movement_goal() - player).normalized()
	_expect(is_equal_approx(absf(previous_direction.dot(next_direction)), cos(deg_to_rad(45.0))), "watcher ring step was not 45 degrees")
	var matching := WatcherBrain.new(behavior, 4419)
	matching.advance(0.0, origin, player, true)
	matching.advance(behavior.stalk_pause_seconds + 0.01, origin, player, true)
	_expect(first.get_movement_goal().is_equal_approx(matching.get_movement_goal()), "stalking sequence is not deterministic")

func _test_awareness_and_aggression() -> void:
	var behavior := load("res://entities/watcher/watcher_behavior.tres") as WatcherBehaviorDefinition
	var brain := WatcherBrain.new(behavior, 991)
	var origin := Vector3(0.5, FEET_Y, 0.5)
	var nearby_player := Vector3(1.5, FEET_Y, 0.5)
	brain.advance(0.0, origin, nearby_player, true)
	_expect(brain.state == WatcherBrain.State.STARE and not brain.consume_attack_started(), "passive watcher attacked a nearby player")
	brain.advance(behavior.target_memory_seconds - 0.01, origin, nearby_player, false)
	_expect(brain.state == WatcherBrain.State.STARE, "watcher forgot the player before memory expired")
	brain.advance(0.02, origin, nearby_player, false)
	_expect(brain.state == WatcherBrain.State.WANDER, "watcher retained an expired player memory")
	brain.advance(0.0, origin, Vector3(30.5, FEET_Y, 0.5), true)
	_expect(brain.state == WatcherBrain.State.WANDER, "forget range did not override visibility")
	brain.record_player_attack()
	_expect(brain.is_aggressive() and brain.state == WatcherBrain.State.CHASE, "player hit did not provoke watcher")
	brain.advance(0.0, origin, nearby_player, false)
	_expect(brain.state == WatcherBrain.State.ATTACK and brain.consume_attack_started(), "provoked watcher did not attack without visibility")
	brain.advance(behavior.melee_profile.duration, origin, nearby_player, false)
	brain.advance(behavior.melee_profile.cooldown - behavior.melee_profile.duration - 0.01, origin, nearby_player, false)
	_expect(not brain.consume_attack_started(), "watcher repeated its attack before the one-second cooldown")
	brain.advance(0.02, origin, nearby_player, false)
	_expect(brain.state == WatcherBrain.State.ATTACK and brain.consume_attack_started(), "watcher did not repeat its attack after cooldown")
	brain.record_player_attack()
	_expect(brain.state == WatcherBrain.State.CHASE and not brain.consume_attack_started(), "repeat hit did not cancel the pending attack")
	brain.reset_after_player_defeat()
	_expect(not brain.is_aggressive() and brain.state == WatcherBrain.State.WANDER, "player defeat did not calm watcher")

func _test_behavior_boundaries() -> void:
	var behavior := load("res://entities/watcher/watcher_behavior.tres") as WatcherBehaviorDefinition
	var origin := Vector3(0.5, FEET_Y, 0.5)
	var detection_edge := WatcherBrain.new(behavior, 187)
	detection_edge.advance(0.0, origin, origin + Vector3.RIGHT * behavior.detection_range, true)
	_expect(detection_edge.state == WatcherBrain.State.STALK, "watcher rejected the inclusive detection boundary")
	var outside_detection := WatcherBrain.new(behavior, 187)
	outside_detection.advance(0.0, origin, origin + Vector3.RIGHT * (behavior.detection_range + 0.01), true)
	_expect(outside_detection.state == WatcherBrain.State.WANDER, "watcher detected a player beyond sixteen blocks")
	var forget_edge := WatcherBrain.new(behavior, 188)
	forget_edge.advance(0.0, origin, origin + Vector3.RIGHT, true)
	forget_edge.advance(0.0, origin, origin + Vector3.RIGHT * behavior.forget_range, false)
	_expect(forget_edge.state != WatcherBrain.State.WANDER, "watcher forgot the player at the inclusive forget boundary")
	forget_edge.advance(0.0, origin, origin + Vector3.RIGHT * (behavior.forget_range + 0.01), false)
	_expect(forget_edge.state == WatcherBrain.State.WANDER, "watcher retained a player beyond twenty-four blocks")
	var inner_band := WatcherBrain.new(behavior, 189)
	inner_band.advance(0.0, origin, origin + Vector3.RIGHT * (behavior.stalk_inner_radius - 0.01), true)
	_expect(inner_band.state == WatcherBrain.State.STARE, "watcher retreated from inside the stalking band")
	var band_edge := WatcherBrain.new(behavior, 189)
	band_edge.advance(0.0, origin, origin + Vector3.RIGHT * behavior.stalk_inner_radius, true)
	_expect(band_edge.state == WatcherBrain.State.STALK, "watcher stopped outside the strict inner stalking boundary")

func _test_actor_contract() -> void:
	var definition := load("res://entities/definitions/watcher.tres") as EntityDefinition
	var actor := definition.actor_scene.instantiate() as WatcherActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, FEET_Y, 0.5)
	actor.setup(7, definition, _make_world(), 7202, EntityNavigationLimits.new(24, 256, 1))
	actor.set_process(false)
	_expect(not actor.is_aggressive() and not actor.is_aggroed() and actor.can_despawn_ambiently(), "fresh watcher aggression state is invalid")
	_expect(actor.supports_player_hit_response(), "watcher does not advertise its player-hit response")
	_expect(actor.get_teleport_sequence() == 0, "fresh watcher teleport sequence is not zero")
	var contact_count: Array[int] = [0]
	actor.melee_contact_reached.connect(func(_runtime_id: int, _profile: MeleeAttackProfile) -> void: contact_count[0] += 1)
	_expect(actor.try_begin_player_hit_response(actor.global_position + Vector3.RIGHT), "fresh watcher rejected its player-hit response")
	_expect(actor.is_aggressive() and actor.is_aggroed() and not actor.can_despawn_ambiently(), "provoked watcher aggression state is invalid")
	_expect(actor.get_teleport_sequence() == 0, "pre-damage response advanced the committed-hit teleport sequence")
	_expect(not actor.try_begin_player_hit_response(actor.global_position + Vector3.RIGHT), "aggressive watcher granted a second first-hit response")
	actor.record_player_attack()
	_expect(actor.get_teleport_sequence() == 1, "committed hit did not advance teleport sequence")
	var observation := EntityTargetObservation.create(
		actor.global_position + Vector3.RIGHT,
		actor.global_position,
		Vector3.FORWARD,
		Vector3.RIGHT,
	)
	var budget := NavigationSearchBudget.new(1)
	actor.tick(0.0, observation, Vector3.ZERO, budget)
	actor.tick(0.27, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 0, "watcher melee contact occurred before 0.28 seconds")
	actor.tick(0.01, observation, Vector3.ZERO, budget)
	_expect(contact_count[0] == 1, "watcher melee contact did not occur at 0.28 seconds")
	actor._timed_melee_contact.arm((definition.behavior as WatcherBehaviorDefinition).melee_profile)
	actor.velocity = Vector3(2.0, 1.0, 3.0)
	actor.knockback_velocity = Vector3.LEFT * 4.0
	actor.record_player_attack()
	_expect(actor.get_teleport_sequence() == 2, "repeat hit did not advance teleport sequence")
	_expect(actor._timed_melee_contact.advance(1.0) == null, "repeat hit did not cancel pending melee contact")
	_expect(actor.velocity.is_zero_approx() and actor.knockback_velocity.is_zero_approx(), "repeat hit did not clear watcher motion")
	var previous_position := actor.global_position
	actor.global_position = Vector3(8.5, FEET_Y, 0.5)
	actor.velocity = Vector3(4.0, 3.0, 2.0)
	actor.knockback_velocity = Vector3.RIGHT * 5.0
	actor.record_teleport_committed(previous_position)
	_expect(actor.velocity.is_zero_approx() and actor.knockback_velocity.is_zero_approx(), "teleport did not clear watcher motion")
	_expect((actor.get_node(^"TeleportDeparture") as CPUParticles3D).emitting, "teleport departure particles did not play")
	_expect((actor.get_node(^"TeleportArrival") as CPUParticles3D).emitting, "teleport arrival particles did not play")
	actor.reset_after_player_defeat()
	_expect(not actor.is_aggressive() and not actor.is_aggroed() and actor.can_despawn_ambiently(), "player defeat did not restore ambient despawning")
	_expect(actor.get_teleport_sequence() == 2, "calming watcher rewound teleport sequence")
	actor.record_player_attack()
	actor._timed_melee_contact.arm((definition.behavior as WatcherBehaviorDefinition).melee_profile)
	actor.begin_death_retirement()
	_expect(actor._timed_melee_contact.advance(1.0) == null, "watcher defeat retained a pending melee contact")
	_expect(not (actor.get_node(^"TeleportDeparture") as CPUParticles3D).emitting and not (actor.get_node(^"TeleportArrival") as CPUParticles3D).emitting, "watcher defeat retained teleport particles")
	actor.free()

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_test_definition()
	_test_visual_geometry()
	_test_deterministic_stalking()
	_test_awareness_and_aggression()
	_test_behavior_boundaries()
	_test_actor_contract()
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "watcher tests changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if _failures == 0:
		print("WATCHER_BEHAVIOR PASS")
		quit(0)
	else:
		print("WATCHER_BEHAVIOR FAIL failures=%d" % _failures)
		quit(1)
