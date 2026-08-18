extends SceneTree
const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")

const FEET_Y: float = 2.0

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_dormant_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(8, 16, 3, 4.0, block_catalog)
	for x in range(-8, 9):
		for z in range(-8, 9):
			world.height_map_dict[Vector2i(x, z)] = 1
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _observation(player_position: Vector3) -> EntityTargetObservation:
	return EntityTargetObservation.create(
		player_position,
		player_position + Vector3(8.0, 10.0, 8.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)

func _run() -> void:
	var definition := load("res://entities/definitions/stone_golem.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "Stone Golem definition was invalid")
	_expect(definition.id == &"stone_golem", "stable Stone Golem ID changed")
	_expect(is_equal_approx(definition.body_width, 1.2) and is_equal_approx(definition.body_height, 2.4), "Stone Golem body dimensions changed")
	_expect(definition.experience_reward == 30 and definition.ambient_max_active == 2, "Stone Golem reward or active cap changed")
	var world := _make_world()
	var actor := definition.actor_scene.instantiate() as StoneGolemActorType
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, FEET_Y, 0.5)
	actor.setup(81, definition, world, 8101, EntityNavigationLimits.new(32, 512, 2))
	actor.set_process(false)
	actor.on_ground = true
	actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "Stone Golem did not start dormant")
	var initial_position := actor.global_position
	var far_player := actor.global_position + Vector3(17.0, 0.0, 0.0)
	actor.tick(0.5, _observation(far_player), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT and not actor.brain.is_alerted(), "target beyond detection woke the Stone Golem")
	_expect(actor.global_position.is_equal_approx(initial_position), "dormant Stone Golem moved")
	var visible_player := actor.global_position + Vector3(8.0, 0.0, 0.0)
	actor.tick(0.5, _observation(visible_player), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
	_expect(actor.brain.state == StoneGolemBrainType.State.CHASE and actor.brain.is_alerted(), "clear nearby target did not alert the Stone Golem")
	_expect(actor.global_position.distance_to(initial_position) > 0.0, "alerted Stone Golem did not begin pursuit")
	var position_before_memory := actor.global_position
	world.restore_block_edits({Vector3i(4, 3, 0): BlockId.Type.STONE}, {})
	actor.tick(0.5, _observation(visible_player), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
	_expect(actor.brain.is_alerted(), "occluded target cleared awareness before memory elapsed")
	_expect(actor.global_position.distance_to(position_before_memory) > 0.0, "remembering Stone Golem stopped pursuing its last-seen target")
	var behavior := definition.behavior as StoneGolemBehaviorDefinition
	var position_before_expiry := actor.global_position
	actor.tick(behavior.target_memory_seconds, _observation(visible_player), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT and not actor.brain.is_alerted(), "occluded target remained alerted after memory elapsed")
	_expect(actor.global_position.is_equal_approx(position_before_expiry), "Stone Golem moved after target memory elapsed")
	world.restore_block_edits({}, {})
	actor.tick(0.5, _observation(visible_player), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
	_expect(actor.brain.is_alerted(), "restored line of sight did not alert the Stone Golem")
	var position_before_forget := actor.global_position
	var beyond_forget := actor.global_position + Vector3(behavior.forget_range + 0.001, 0.0, 0.0)
	actor.tick(0.0, _observation(beyond_forget), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT and not actor.brain.is_alerted(), "target beyond forget range did not clear awareness immediately")
	_expect(actor.global_position.is_equal_approx(position_before_forget), "Stone Golem moved after the target crossed the forget range")
	var animation := actor.animation_driver as StoneGolemAnimationDriverType
	animation.advance(0.1)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.IDLE, "dormant Stone Golem did not present idle")
	var profile := animation.animator.profile
	_expect(
		is_equal_approx(profile.landing_seconds, 0.38)
		and is_equal_approx(profile.landing_hold_seconds, 0.09)
		and is_equal_approx(profile.landing_squash, 0.11)
		and is_equal_approx(profile.landing_widen, 0.045)
		and is_equal_approx(profile.landing_rebound_stretch, 0.025),
		"Stone Golem landing tuning changed",
	)
	actor.global_position = Vector3(0.5, FEET_Y + 2.0, 0.5)
	actor.velocity = Vector3.ZERO
	actor.on_ground = false
	var saw_fall := false
	var saw_land := false
	for _frame_index in range(120):
		actor.tick(1.0 / 60.0, _observation(Vector3(32.5, FEET_Y, 0.5)), Vector3.ZERO, NavigationSearchBudget.new(2))
		animation.advance(1.0 / 60.0)
		var animation_state := animation.animator.get_current_state()
		saw_fall = saw_fall or animation_state == BlockyHumanoidAnimator.FALL
		saw_land = saw_land or animation_state == BlockyHumanoidAnimator.LAND
		if saw_land:
			break
	_expect(saw_fall, "falling Stone Golem did not present its fall state")
	_expect(saw_land, "falling Stone Golem did not consume its landing tuning")
	_expect(actor.on_ground and absf(actor.global_position.y - FEET_Y) < 0.12, "Stone Golem did not settle within the voxel floor contact tolerance")
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "falling and landing woke the dormant Stone Golem")
	actor.queue_free()
	for _frame_index in range(8):
		await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "dormant integration ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("STONE_GOLEM_DORMANT PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("STONE_GOLEM_DORMANT FAIL failures=%d" % _failures)
		quit(1)
