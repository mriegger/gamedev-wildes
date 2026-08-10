extends SceneTree

const FLAT_HEIGHT: int = 6
const FEET_Y: int = FLAT_HEIGHT + 1
const TEST_RADIUS: int = 16
const BODY_WIDTH: float = 0.8
const BODY_HEIGHT: float = 1.4

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[sheep_behavior_integration] FAIL: %s" % message)

func _make_behavior() -> SheepBehaviorDefinition:
	var behavior := SheepBehaviorDefinition.new()
	behavior.wander_speed = 1.2
	behavior.flee_speed = 3.6
	behavior.gravity = 30.0
	behavior.jump_velocity = 7.0
	behavior.wander_radius = 5.0
	behavior.wander_goal_seconds = 2.0
	behavior.idle_seconds = 0.1
	behavior.flee_seconds = 4.0
	behavior.flee_goal_distance = 8.0
	behavior.repath_seconds = 0.5
	return behavior

func _make_flat_world() -> VoxelWorld:
	var catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _make_definition(behavior: SheepBehaviorDefinition) -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.id = &"sheep"
	definition.actor_scene = load("res://entities/sheep/sheep.tscn") as PackedScene
	definition.behavior = behavior
	definition.body_width = BODY_WIDTH
	definition.body_height = BODY_HEIGHT
	definition.spawn_phase = EntityDefinition.SpawnPhase.DAY
	definition.max_active = 6
	var spawn_floor_ids: Array[int] = [BlockId.Type.GRASS]
	definition.spawn_floor_ids = spawn_floor_ids
	return definition

func _test_deterministic_wander_and_flee() -> void:
	var behavior := _make_behavior()
	_expect(behavior.validate("test"), "valid sheep behavior definition was rejected")
	var origin := Vector3(2.5, float(FEET_Y), 3.5)
	var first := SheepBrain.new(behavior, 451)
	var second := SheepBrain.new(behavior, 451)
	first.advance(behavior.idle_seconds, origin)
	second.advance(behavior.idle_seconds, origin)
	_expect(first.state == SheepBrain.State.WANDER, "sheep did not leave idle for wander")
	_expect(first.get_movement_goal().is_equal_approx(second.get_movement_goal()), "same seed produced different wander goals")
	var wander_distance := Vector2(first.get_movement_goal().x - origin.x, first.get_movement_goal().z - origin.z).length()
	_expect(wander_distance >= behavior.wander_radius * 0.35 and wander_distance <= behavior.wander_radius, "wander goal exceeded its configured radius")

	first.record_melee_contact(origin, Vector3.RIGHT)
	_expect(first.state == SheepBrain.State.FLEE, "melee contact did not start fleeing")
	_expect(first._flee_direction.is_equal_approx(Vector3.RIGHT), "flee direction did not follow the hit direction")
	_expect(first.get_movement_goal().is_equal_approx(origin + Vector3.RIGHT * behavior.flee_goal_distance), "flee goal did not lead away from contact")
	_expect(is_equal_approx(first._flee_remaining, behavior.flee_seconds), "flee timer did not start at its configured duration")
	first.advance(behavior.flee_seconds - 0.01, origin)
	_expect(first.state == SheepBrain.State.FLEE and first._flee_remaining > 0.0, "flee ended before four seconds")
	first.advance(0.02, origin)
	_expect(first.state == SheepBrain.State.FLEE and is_zero_approx(first._flee_remaining), "flee completion tick was not retained")
	first.advance(0.001, origin)
	_expect(first.state == SheepBrain.State.IDLE, "sheep did not return to idle after fleeing")

func _test_actor_movement_and_animation() -> SheepActor:
	var behavior := _make_behavior()
	var definition := _make_definition(behavior)
	_expect(definition.validate("test"), "valid sheep entity definition was rejected")
	var actor := definition.actor_scene.instantiate() as SheepActor
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, float(FEET_Y), 0.5)
	actor.setup(7, definition, _make_flat_world(), 882)
	var animation := actor.animation_driver as SheepAnimationDriver
	animation.advance(0.05)
	_expect(animation.get_current_state() == SheepAnimationDriver.IDLE, "sheep animation did not start idle")

	var initial_position := actor.global_position
	actor.tick(behavior.idle_seconds, Vector3.ZERO, Vector3.ZERO)
	for _step in range(4):
		actor.tick(0.1, Vector3.ZERO, Vector3.ZERO)
	animation.advance(0.1)
	_expect(actor.brain.state == SheepBrain.State.WANDER, "sheep actor did not enter wander")
	_expect(actor.global_position.distance_squared_to(initial_position) > 0.01, "sheep did not move across flat terrain")
	_expect(actor.on_ground, "sheep lost flat-world grounding while wandering")
	_expect(animation.get_current_state() == SheepAnimationDriver.WALK, "sheep animation did not enter walk")

	var pre_flee_position := actor.global_position
	actor.model_root.rotation.y = 0.0
	actor.record_melee_contact(Vector3.RIGHT)
	animation.advance(0.01)
	_expect(actor.brain.state == SheepBrain.State.FLEE, "actor did not record melee-triggered flee")
	_expect(animation.get_current_state() == SheepAnimationDriver.HIT, "sheep animation did not enter hit reaction")
	_expect((animation._rig_root.position - animation._rig_origin_position).dot(Vector3.RIGHT) > 0.0, "sheep recoil moved toward the attacker")
	actor.tick(0.1, Vector3.ZERO, Vector3.ZERO)
	animation.advance(SheepAnimationDriver.HIT_SECONDS)
	_expect(actor.global_position.x > pre_flee_position.x, "sheep did not move along its flee direction")
	_expect(is_equal_approx(Vector2(actor.velocity.x, actor.velocity.z).length(), behavior.flee_speed), "sheep did not use flee speed")
	_expect(animation.get_current_state() == SheepAnimationDriver.FLEE, "sheep animation did not enter flee")
	return actor

func _run() -> void:
	_test_deterministic_wander_and_flee()
	var actor := _test_actor_movement_and_animation()
	actor.queue_free()
	await process_frame
	await process_frame
	_expect(not is_instance_valid(actor), "sheep actor remained alive after cleanup")
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "orphan count ended at %d" % orphan_count)
	if _failures == 0:
		print("SHEEP_BEHAVIOR_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("SHEEP_BEHAVIOR_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
