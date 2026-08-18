extends SceneTree
const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")
const StoneGolemLandingDustType := preload("res://entities/stone_golem/stone_golem_landing_dust.gd")

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
	actor.brain._slam_cooldown_remaining = INF
	actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
	var landing_dust := actor.get_node(^"LandingDust") as StoneGolemLandingDustType
	_expect(landing_dust != null, "production Stone Golem landing dust was missing")
	_expect(landing_dust.one_shot and landing_dust.amount == 26, "landing dust was not a bounded one-shot burst")
	_expect(not landing_dust.emitting and not landing_dust.local_coords, "landing dust did not start inactive in world space")
	_expect(landing_dust.get_play_count() == 0, "landing dust played before a slam landing")
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
	_expect(
		is_equal_approx(profile.walk_cycle_seconds, 1.05)
		and is_equal_approx(profile.walk_leg_travel, 0.26)
		and is_equal_approx(profile.walk_leg_lift, 0.1)
		and is_equal_approx(profile.walk_arm_swing_degrees, 26.0)
		and is_equal_approx(profile.gait_direction_response, 8.0),
		"Stone Golem heavy gait tuning changed",
	)
	actor.max_speed = 1.2
	actor.velocity = Vector3(0.0, 0.0, 1.2)
	animation.advance(profile.walk_cycle_seconds * 0.2)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.WALK, "moving Stone Golem did not present its heavy walk")
	var left_swing := animation.animator.left_leg_locomotion.rotation.x
	var right_swing := animation.animator.right_leg_locomotion.rotation.x
	_expect(maxf(absf(left_swing), absf(right_swing)) > deg_to_rad(2.0), "heavy walk did not produce its tuned leg swing")
	_expect(left_swing * right_swing < 0.0, "heavy walk legs did not retain opposed swing phases")
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

	var punch_profile := load("res://combat/profiles/stone_golem_punch.tres") as MeleeAttackProfile
	animation.play_attack(punch_profile.duration)
	actor._timed_melee_contact.arm(punch_profile)
	animation.advance(0.1)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.PUNCH, "punch presentation fixture did not start")
	_expect(animation.animator.rig_root.position.z > animation.animator._rig_root_origin.z + 0.04, "heavy punch did not drive the body forward")
	_expect(animation.animator.right_arm_action.rotation.x < -deg_to_rad(35.0), "heavy punch did not commit the striking arm")
	actor.play_hit(Vector3.LEFT)
	animation.advance(StoneGolemAnimationDriverType.HIT_SECONDS * 0.5)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.HIT, "received hit did not overlay the active punch")
	_expect(animation.animator.head_secondary.rotation.z > deg_to_rad(10.0), "hit reaction did not snap the head away from impact")
	_expect(animation.animator.rig_root.scale.y < 0.95, "hit reaction did not compress the heavy body")
	_expect(actor._timed_melee_contact.is_pending(), "received hit cancelled pending punch contact")
	animation.advance(StoneGolemAnimationDriverType.HIT_SECONDS * 0.5)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.PUNCH, "punch presentation did not resume after hit reaction")
	_expect(actor._timed_melee_contact.is_pending(), "resumed punch lost pending gameplay contact")
	actor._timed_melee_contact.cancel()

	animation.set_alerted(true)
	animation.play_slam_windup(0.6)
	animation.advance(0.3)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.SLAM_WINDUP, "slam windup presentation was not distinct")
	_expect(animation.left_eye_material.emission_enabled and animation.right_eye_material.emission_enabled, "slam windup cleared alerted eyes")
	_expect(animation.animator.rig_root.scale.y < 0.95, "slam windup did not compress the Stone Golem")
	_expect(animation.animator.left_leg_base.rotation.x < 0.0 and animation.animator.right_leg_base.rotation.x > 0.0, "slam windup did not brace opposite legs")
	animation.play_slam_airborne(0.8)
	animation.advance(0.2)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.SLAM_AIRBORNE, "slam airborne presentation was not distinct")
	_expect(animation.animator.rig_root.scale.y > 1.05, "slam airborne pose did not stretch upward")
	_expect(animation.animator.left_arm_action.rotation.x < -deg_to_rad(90.0), "slam airborne pose did not raise both fists")
	animation.play_slam_recovery(0.75)
	animation.advance(0.2)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.SLAM_RECOVERY, "slam recovery presentation was not distinct")
	_expect(animation.animator.rig_root.scale.y < 0.9, "slam recovery did not squash on impact")
	_expect(animation.animator.left_leg_base.rotation.x < -deg_to_rad(10.0) and animation.animator.right_leg_base.rotation.x < -deg_to_rad(10.0), "slam recovery did not absorb impact through both legs")
	animation.cancel_slam()
	animation.advance(0.0)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.IDLE, "cancelled slam presentation did not return to idle")
	_expect(animation.left_eye_material.emission_enabled and animation.right_eye_material.emission_enabled, "slam presentation changed alerted eye state")
	actor.begin_death_retirement()
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.DEATH, "death retirement did not select the death pose")
	animation.advance(StoneGolemAnimationDriverType.DEATH_SECONDS * 0.5)
	_expect(absf(animation.animator.left_arm_action.rotation.z) > deg_to_rad(60.0), "death pose did not splay the heavy left arm")
	_expect(animation.animator.left_leg_base.rotation.x < -deg_to_rad(15.0), "death pose did not buckle the legs")
	_expect(not animation.left_eye_material.emission_enabled and not animation.right_eye_material.emission_enabled, "death pose retained alerted eyes")

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
