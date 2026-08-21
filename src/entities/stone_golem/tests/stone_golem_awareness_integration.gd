extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")
const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")
const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const WORLD_RADIUS: int = 64

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_awareness_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
		for z in range(-WORLD_RADIUS, WORLD_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _observation(player_position: Vector3) -> EntityTargetObservationType:
	var observation := EntityTargetObservationType.create(
		player_position,
		player_position + Vector3(12.0, 16.0, 12.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)
	assert(observation != null)
	return observation

func _tick(actor: StoneGolemActorType, delta: float, player_position: Vector3) -> void:
	actor.tick_gameplay(delta, _observation(player_position), Vector3.ZERO, NavigationSearchBudget.new(2))

func _expect_dormant_eye(material: StandardMaterial3D, context: String) -> void:
	_expect(material.albedo_color.is_equal_approx(StoneGolemAnimationDriverType.DORMANT_EYE_COLOR), "%s eye was not dark" % context)
	_expect(not material.emission_enabled, "%s eye retained emission" % context)
	_expect(is_zero_approx(material.emission_energy_multiplier), "%s eye retained emission energy" % context)

func _expect_alerted_eye(material: StandardMaterial3D, context: String) -> void:
	_expect(material.albedo_color.is_equal_approx(StoneGolemAnimationDriverType.ALERT_EYE_COLOR), "%s eye was not red" % context)
	_expect(material.emission_enabled, "%s eye did not enable emission" % context)
	_expect(material.emission.is_equal_approx(StoneGolemAnimationDriverType.ALERT_EYE_COLOR), "%s eye emission color was not red" % context)
	_expect(is_equal_approx(material.emission_energy_multiplier, StoneGolemAnimationDriverType.ALERT_EYE_ENERGY), "%s eye emission energy changed" % context)

func _contains_light(node: Node) -> bool:
	if node is Light3D:
		return true
	for child in node.get_children():
		if _contains_light(child):
			return true
	return false

func _spawn_actor(definition: EntityDefinition, world: VoxelWorld, runtime_id: int, position: Vector3) -> StoneGolemActorType:
	var actor := definition.actor_scene.instantiate() as StoneGolemActorType
	get_root().add_child(actor)
	actor.global_position = position
	actor.setup(runtime_id, definition, world, 1000 + runtime_id, EntityNavigationLimits.new(32, 512, 2))
	actor.set_process(false)
	actor.on_ground = true
	actor.brain._slam_cooldown_remaining = INF
	return actor

func _run() -> void:
	var definition := load("res://entities/definitions/stone_golem.tres") as EntityDefinition
	var behavior := definition.behavior as StoneGolemBehaviorDefinition
	var world := _make_world()
	var first := _spawn_actor(definition, world, 0, Vector3(0.5, FEET_Y, 0.5)) as StoneGolemActorType
	var second := _spawn_actor(definition, world, 1, Vector3(40.5, FEET_Y, 0.5)) as StoneGolemActorType
	var first_driver := first.animation_driver as StoneGolemAnimationDriverType
	var second_driver := second.animation_driver as StoneGolemAnimationDriverType
	var material_ids: Dictionary = {}
	for material in [first_driver.left_eye_material, first_driver.right_eye_material, second_driver.left_eye_material, second_driver.right_eye_material]:
		material_ids[material.get_instance_id()] = true
	_expect(material_ids.size() == 4, "production Stone Golems shared an eye material instance")
	_expect(first_driver.left_eye.get_surface_override_material(0) == first_driver.left_eye_material, "first left eye did not use its local override")
	_expect(first_driver.right_eye.get_surface_override_material(0) == first_driver.right_eye_material, "first right eye did not use its local override")
	_expect(second_driver.left_eye.get_surface_override_material(0) == second_driver.left_eye_material, "second left eye did not use its local override")
	_expect(second_driver.right_eye.get_surface_override_material(0) == second_driver.right_eye_material, "second right eye did not use its local override")
	_expect_dormant_eye(first_driver.left_eye_material, "first dormant left")
	_expect_dormant_eye(first_driver.right_eye_material, "first dormant right")
	_expect_dormant_eye(second_driver.left_eye_material, "second dormant left")
	_expect_dormant_eye(second_driver.right_eye_material, "second dormant right")
	_expect(not _contains_light(first) and not _contains_light(second), "Stone Golem presentation introduced a gameplay light")

	var outside_detection := second.global_position + Vector3(behavior.detection_range + 0.5, 0.0, 0.0)
	_tick(second, VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS, outside_detection)
	_expect(second.brain.state == StoneGolemBrainType.State.DORMANT, "clear target beyond detection alerted the second Stone Golem")
	_expect_dormant_eye(second_driver.left_eye_material, "out-of-range second left")
	_expect_dormant_eye(second_driver.right_eye_material, "out-of-range second right")

	var visible_player := first.global_position + Vector3(8.0, 0.0, 0.0)
	_tick(first, 0.0, visible_player)
	_expect(first.brain.state == StoneGolemBrainType.State.CHASE and first.brain.is_alerted(), "clear line of sight did not alert the first Stone Golem")
	_expect_alerted_eye(first_driver.left_eye_material, "alerted first left")
	_expect_alerted_eye(first_driver.right_eye_material, "alerted first right")
	_expect_dormant_eye(second_driver.left_eye_material, "isolated second left")
	_expect_dormant_eye(second_driver.right_eye_material, "isolated second right")

	var wall_blocks: Dictionary = {}
	for z in range(-8, 9):
		wall_blocks[Vector3i(4, FLAT_HEIGHT + 2, z)] = BlockId.Type.STONE
	world.restore_block_edits(wall_blocks, {})
	_tick(first, VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS, visible_player)
	_expect(first.brain.is_alerted(), "occlusion cleared the alert before target memory elapsed")
	_expect_alerted_eye(first_driver.left_eye_material, "remembering first left")
	var memory_before_expiry := behavior.target_memory_seconds - VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS - 0.001
	_tick(first, memory_before_expiry, visible_player)
	_expect(first.brain.is_alerted(), "occluded target memory expired early")
	_tick(first, 0.002, visible_player)
	_expect(first.brain.state == StoneGolemBrainType.State.DORMANT and not first.brain.is_alerted(), "occluded target remained alerted after memory expired")
	_expect_dormant_eye(first_driver.left_eye_material, "forgotten first left")
	_expect_dormant_eye(first_driver.right_eye_material, "forgotten first right")

	world.restore_block_edits({}, {})
	_tick(first, VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS, visible_player)
	_expect(first.brain.is_alerted(), "restored line of sight did not alert the Stone Golem")
	var beyond_forget := first.global_position + Vector3(behavior.forget_range + 0.001, 0.0, 0.0)
	_tick(first, 0.0, beyond_forget)
	_expect(first.brain.state == StoneGolemBrainType.State.DORMANT and not first.brain.is_alerted(), "target beyond forget range did not clear the alert immediately")
	_expect_dormant_eye(first_driver.left_eye_material, "forgotten-range first left")
	_expect_dormant_eye(first_driver.right_eye_material, "forgotten-range first right")

	_tick(first, VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS, visible_player)
	_expect(first.brain.is_alerted(), "death fixture did not restore the alert")
	first.begin_death_retirement()
	var death_time_remaining := first_driver.get_death_time_remaining()
	_expect_dormant_eye(first_driver.left_eye_material, "dying first left")
	_expect_dormant_eye(first_driver.right_eye_material, "dying first right")
	first.begin_death_retirement()
	first_driver.set_alerted(true)
	_expect(is_equal_approx(first_driver.get_death_time_remaining(), death_time_remaining), "repeated death restarted the Stone Golem death timer")
	_expect_dormant_eye(first_driver.left_eye_material, "repeated-death first left")
	_expect_dormant_eye(first_driver.right_eye_material, "repeated-death first right")
	_expect_dormant_eye(second_driver.left_eye_material, "surviving second left")
	_expect_dormant_eye(second_driver.right_eye_material, "surviving second right")
	_expect(not _contains_light(first) and not _contains_light(second), "awareness or death introduced a gameplay light")

	first.free()
	second.free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "awareness integration ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("STONE_GOLEM_AWARENESS_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("STONE_GOLEM_AWARENESS_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
