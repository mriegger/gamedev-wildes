extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[player_animation] starting")
	call_deferred("_run")

func _run():
	var packed = load("res://player/visuals/player_visual.tscn") as PackedScene
	if packed == null:
		_fail("failed to load player visual")
		return
	var animator = packed.instantiate() as BlockyHumanoidAnimator
	root.add_child(animator)
	await process_frame
	var state = ActorAnimationState.new()
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	animator.setup(state)
	var torso_mesh = (animator.get_node("RigRoot/BodySecondary/BodyAction/TorsoBase/Torso") as MeshInstance3D).mesh as BoxMesh
	var head_mesh = (animator.get_node("RigRoot/BodySecondary/BodyAction/TorsoBase/HeadAnchor/HeadBase/HeadSecondary/Head") as MeshInstance3D).mesh as BoxMesh
	var arm_mesh = (animator.get_node("RigRoot/BodySecondary/BodyAction/TorsoBase/LeftShoulder/LeftArmBase/LeftArmAction/LeftArm") as MeshInstance3D).mesh as BoxMesh
	var leg_mesh = (animator.get_node("RigRoot/LeftHip/LeftLegLocomotion/LeftLegBase/LeftLeg") as MeshInstance3D).mesh as BoxMesh
	_expect(torso_mesh.size.is_equal_approx(Vector3(0.45, 0.675, 0.225)), "torso proportions changed")
	_expect(head_mesh.size.is_equal_approx(Vector3(0.45, 0.45, 0.45)), "head proportions changed")
	_expect(arm_mesh.size.is_equal_approx(Vector3(0.225, 0.675, 0.225)), "rigid arm proportions changed")
	_expect(leg_mesh.size.is_equal_approx(Vector3(0.225, 0.675, 0.225)), "rigid leg proportions changed")
	_expect(is_equal_approx(leg_mesh.size.y + torso_mesh.size.y + head_mesh.size.y, 1.8), "visual height no longer matches collision height")
	_expect(is_equal_approx(animator.profile.gait_direction_response, 12.0), "gait direction response default changed")
	var left_leg = animator.get_node("RigRoot/LeftHip/LeftLegLocomotion") as Node3D
	var right_leg = animator.get_node("RigRoot/RightHip/RightLegLocomotion") as Node3D
	var left_leg_origin = left_leg.position
	var right_leg_origin = right_leg.position
	_advance(animator, 12)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.IDLE, "idle state was not selected")
	var idle_y = animator.rig_root.position.y
	_advance(animator, 18)
	_expect(not is_equal_approx(idle_y, animator.rig_root.position.y), "idle body motion did not advance")

	state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 1)
	var initial_direction_response = 1.0 - exp(-animator.profile.gait_direction_response / 60.0)
	_expect(animator._gait_direction.distance_to(Vector2(0.0, initial_direction_response)) < 0.0001, "gait direction did not use frame-rate-independent exponential response")
	var max_walk_foot_lift = 0.0
	var max_walk_detachment = 0.0
	var max_walk_stretch = 1.0
	var max_walk_bob = 0.0
	var max_walk_leg_deformation_difference = 0.0
	var max_walk_body_twist = 0.0
	var min_walk_rig_height = 1.0
	var max_walk_rig_height = 1.0
	var max_walk_rig_width = 1.0
	var min_walk_stance_height = INF
	var max_walk_stance_height = -INF
	for _frame in range(44):
		_advance(animator, 1)
		var foot = _leg_foot(animator.left_foot_marker)
		var cycle = fposmod(animator._gait_phase() / TAU, 1.0)
		max_walk_foot_lift = max(max_walk_foot_lift, foot.y)
		max_walk_detachment = max(max_walk_detachment, left_leg.position.distance_to(left_leg_origin))
		if cycle < animator.profile.gait_push_pose:
			min_walk_stance_height = min(min_walk_stance_height, foot.y)
			max_walk_stance_height = max(max_walk_stance_height, foot.y)
		max_walk_stretch = max(max_walk_stretch, animator.left_leg_base.scale.y)
		max_walk_bob = max(max_walk_bob, animator.rig_root.position.y)
		max_walk_leg_deformation_difference = max(max_walk_leg_deformation_difference, abs(animator.left_leg_base.scale.y - animator.right_leg_base.scale.y))
		max_walk_body_twist = max(max_walk_body_twist, abs(animator.body_secondary.rotation.y))
		min_walk_rig_height = min(min_walk_rig_height, animator.rig_root.scale.y)
		max_walk_rig_height = max(max_walk_rig_height, animator.rig_root.scale.y)
		max_walk_rig_width = max(max_walk_rig_width, animator.rig_root.scale.x)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.WALK, "walk state was not selected")
	_expect(abs(left_leg.rotation.x - right_leg.rotation.x) > 0.2, "walk legs did not oppose")
	_expect(max_walk_bob > 0.05, "walk bob was not applied")
	_expect(max_walk_stretch > 1.02, "walk stride did not stretch the leg")
	_expect(max_walk_detachment > 0.20, "walk leg root did not detach from the hip")
	_expect(max_walk_foot_lift > 0.16 and max_walk_foot_lift < 0.20, "walk recovery did not lift the foot height=%.3f" % max_walk_foot_lift)
	_expect(max_walk_stance_height - min_walk_stance_height < 0.002, "walk stance foot did not trace a flat path")
	_expect(max_walk_leg_deformation_difference > 0.02, "walk legs still deformed in perfect synchronization")
	_expect(max_walk_body_twist > deg_to_rad(1.5), "walk body did not transfer weight between steps")
	_expect(min_walk_rig_height < 0.96, "walk contact did not squash the voxel rig")
	_expect(max_walk_rig_height > 1.01, "walk passing pose did not rebound from the squash")
	_expect(max_walk_rig_width > 1.02, "walk contact did not widen the voxel rig")
	_expect(abs(animator._gait_phase() - animator._walk_phase) > 0.03, "walk cadence was not shaped")
	_expect(is_equal_approx(left_leg.position.x, left_leg_origin.x), "walk moved the left leg sideways")
	_expect(is_equal_approx(right_leg.position.x, right_leg_origin.x), "walk moved the right leg sideways")
	var left_marker_origin = animator.left_foot_marker.position
	var right_marker_origin = animator.right_foot_marker.position
	animator.left_foot_marker.position.y = -0.50
	animator.right_foot_marker.position.y = -0.50
	var min_long_leg_stance_height = INF
	var max_long_leg_stance_height = -INF
	for _frame in range(44):
		_advance(animator, 1)
		var cycle = fposmod(animator._gait_phase() / TAU, 1.0)
		if cycle < animator.profile.gait_push_pose:
			var foot_height = animator.left_foot_marker.global_position.y
			min_long_leg_stance_height = min(min_long_leg_stance_height, foot_height)
			max_long_leg_stance_height = max(max_long_leg_stance_height, foot_height)
	_expect(max_long_leg_stance_height - min_long_leg_stance_height < 0.002, "alternate leg proportion did not preserve the planted foot path")
	animator.left_foot_marker.position = left_marker_origin
	animator.right_foot_marker.position = right_marker_origin
	state.set_motion(Vector3(0.0, 0.0, 8.0), 1.0, true, true, 0.0, 0.0, false, Vector3.ZERO)
	var max_leg_arc = 0.0
	var max_leg_stretch = 1.0
	var min_leg_scale = 1.0
	var max_leg_detachment = 0.0
	var max_foot_lift = 0.0
	var min_foot_reach = INF
	var max_foot_reach = -INF
	var min_stance_height = INF
	var max_stance_height = -INF
	var max_rotation_asymmetry = 0.0
	var max_arm_arc = 0.0
	var max_torso_deformation = 0.0
	var min_sprint_rig_height = 1.0
	var max_sprint_rig_height = 1.0
	var max_sprint_rig_width = 1.0
	for _frame in range(30):
		_advance(animator, 1)
		var foot = _leg_foot(animator.left_foot_marker)
		var cycle = fposmod(animator._gait_phase() / TAU, 1.0)
		max_leg_arc = max(max_leg_arc, abs(left_leg.rotation.x - right_leg.rotation.x))
		max_leg_stretch = max(max_leg_stretch, animator.left_leg_base.scale.y)
		min_leg_scale = min(min_leg_scale, animator.left_leg_base.scale.y)
		max_leg_detachment = max(max_leg_detachment, left_leg.position.distance_to(left_leg_origin))
		max_foot_lift = max(max_foot_lift, foot.y)
		min_foot_reach = min(min_foot_reach, foot.z)
		max_foot_reach = max(max_foot_reach, foot.z)
		if cycle < animator.profile.gait_push_pose:
			min_stance_height = min(min_stance_height, foot.y)
			max_stance_height = max(max_stance_height, foot.y)
		max_rotation_asymmetry = max(max_rotation_asymmetry, abs(abs(left_leg.rotation.x) - abs(right_leg.rotation.x)))
		var left_arm_angle = animator.left_arm_base.rotation.x + animator.left_arm_action.rotation.x
		var right_arm_angle = animator.right_arm_base.rotation.x + animator.right_arm_action.rotation.x
		max_arm_arc = max(max_arm_arc, abs(left_arm_angle - right_arm_angle))
		max_torso_deformation = max(max_torso_deformation, animator.torso_base.scale.distance_to(Vector3.ONE))
		min_sprint_rig_height = min(min_sprint_rig_height, animator.rig_root.scale.y)
		max_sprint_rig_height = max(max_sprint_rig_height, animator.rig_root.scale.y)
		max_sprint_rig_width = max(max_sprint_rig_width, animator.rig_root.scale.x)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.SPRINT, "sprint state was not selected")
	_expect(is_equal_approx(left_leg.position.x, left_leg_origin.x), "sprint moved the left leg sideways")
	_expect(is_equal_approx(right_leg.position.x, right_leg_origin.x), "sprint moved the right leg sideways")
	_expect(max_leg_detachment > 0.35, "sprint leg root did not detach far enough from the hip")
	_expect(max_foot_lift > 0.36 and max_foot_lift < 0.42, "sprint recovery did not lift the foot height=%.3f" % max_foot_lift)
	_expect(max_foot_reach - min_foot_reach > 0.90, "sprint foot path did not overreach the rigid leg length reach=%.3f" % (max_foot_reach - min_foot_reach))
	_expect(max_stance_height - min_stance_height < 0.002, "sprint stance foot did not trace a flat path")
	_expect(max_leg_arc > deg_to_rad(55.0) and max_leg_arc < deg_to_rad(75.0), "sprint leg arc did not match the exported range arc=%.2f" % rad_to_deg(max_leg_arc))
	_expect(max_rotation_asymmetry > deg_to_rad(10.0), "sprint legs still used a symmetric pendulum swing")
	_expect(max_arm_arc > deg_to_rad(120.0), "sprint arm opposition was not exaggerated")
	_expect(max_leg_stretch > 1.01, "sprint stride did not stretch the leg")
	_expect(min_leg_scale < 0.90, "sprint recovery did not shorten the rigid leg")
	_expect(max_torso_deformation > 0.01, "sprint did not squash the torso")
	_expect(min_sprint_rig_height < 0.94, "sprint steps did not squash the voxel rig")
	_expect(max_sprint_rig_height > 1.02, "sprint passing pose did not rebound from the squash")
	_expect(max_sprint_rig_width > 1.04, "sprint steps did not widen the voxel rig")
	_expect(animator.rig_root.rotation.x > deg_to_rad(6.0), "sprint rig did not lean into velocity angle=%.2f" % rad_to_deg(animator.rig_root.rotation.x))
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	var min_brake_lean = INF
	for _frame in range(18):
		_advance(animator, 1)
		min_brake_lean = min(min_brake_lean, animator.rig_root.rotation.x)
	_expect(min_brake_lean < deg_to_rad(-1.0), "stopping did not rock the rig backward")
	_expect(left_leg.position.is_equal_approx(left_leg_origin), "left leg did not recover after sprinting")
	_expect(right_leg.position.is_equal_approx(right_leg_origin), "right leg did not recover after sprinting")
	_expect(left_leg.rotation.is_equal_approx(Vector3.ZERO), "left leg rotation did not recover after sprinting")
	_expect(right_leg.rotation.is_equal_approx(Vector3.ZERO), "right leg rotation did not recover after sprinting")
	_expect(animator.left_leg_base.scale.is_equal_approx(Vector3.ONE), "leg scale did not recover after sprinting")
	var original_profile = animator.profile
	animator.profile = animator.profile.duplicate(true) as BlockyHumanoidAnimationProfile
	animator.profile.walk_limb_stretch = 0.0
	animator.profile.landing_hold_seconds = animator.profile.landing_seconds
	state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 8)
	_expect(animator.left_leg_base.scale.is_finite() and animator.left_leg_locomotion.position.is_finite(), "zero limb stretch produced a non-finite gait transform")
	state.set_motion(Vector3(0.0, -8.0, 0.0), 0.0, false, false, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 2)
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 2)
	_expect(animator.rig_root.scale.is_finite(), "equal landing hold and duration produced a non-finite rig transform")
	animator.profile = original_profile

	state.set_motion(Vector3(4.0, 0.0, 3.0), 1.0, false, true, 0.0, 5.0, false, Vector3.ZERO)
	_advance(animator, 12)
	_expect(abs(animator.body_secondary.rotation.z) > deg_to_rad(4.0), "turn and strafe lean was not applied")
	_run_directional_gait_checks(animator, state, left_leg_origin, right_leg_origin)

	var min_jump_anticipation = 0.0
	var min_jump_anticipation_scale = 1.0
	var max_jump_anticipation_width = 1.0
	for frame in range(7):
		state.set_motion(Vector3(0.0, 0.0, 2.0), 0.35, false, true, float(frame + 1) / 8.0, 0.0, false, Vector3.ZERO)
		_advance(animator, 1)
		min_jump_anticipation = min(min_jump_anticipation, animator.rig_root.position.y)
		min_jump_anticipation_scale = min(min_jump_anticipation_scale, animator.rig_root.scale.y)
		max_jump_anticipation_width = max(max_jump_anticipation_width, animator.rig_root.scale.x)
	_expect(min_jump_anticipation < -0.04, "jump did not visually anticipate with a crouch")
	_expect(min_jump_anticipation_scale < 0.88, "jump anticipation did not squash the voxel rig")
	_expect(max_jump_anticipation_width > 1.05, "jump anticipation did not widen the voxel rig")
	_expect(animator.torso_base.scale.y < 0.96, "jump anticipation did not squash the torso")
	_expect(animator.head_secondary.scale.y < 0.98, "jump anticipation did not squash the head")
	state.set_motion(Vector3(0.0, 8.0, 2.0), 0.35, false, false, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 8)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.JUMP, "jump state was not selected")
	_expect(animator.rig_root.scale.y > 1.07, "jump stretch was not applied")
	_expect(animator.rig_root.scale.x < 0.97, "jump stretch did not narrow the voxel rig")
	_expect(animator.torso_base.scale.y > 1.02, "jump stretch did not reach the torso")
	_expect(animator.head_secondary.scale.y > 1.01, "jump stretch did not reach the head")
	state.set_motion(Vector3(0.0, -8.0, 2.0), 0.35, false, false, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 8)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.FALL, "fall state was not selected")
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 1)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.LAND, "landing state was not selected")
	_expect(animator.rig_root.scale.y < 0.89, "landing squash was not applied")
	_expect(animator.rig_root.scale.x > 1.05, "landing squash did not widen the voxel rig")
	_expect(animator.torso_base.scale.y < 0.97, "landing squash did not reach the torso")
	_expect(animator.head_secondary.scale.y < 0.99, "landing squash did not reach the head")
	var landing_contact_scale = animator.rig_root.scale.y
	_advance(animator, 2)
	_expect(animator.rig_root.scale.y <= landing_contact_scale + 0.002, "landing compression was not held long enough to read")
	var max_landing_rebound_scale = 1.0
	for _frame in range(12):
		_advance(animator, 1)
		max_landing_rebound_scale = max(max_landing_rebound_scale, animator.rig_root.scale.y)
	_expect(max_landing_rebound_scale > 1.005, "landing squash did not rebound")
	_advance(animator, 10)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.IDLE, "landing did not recover to idle")
	_expect(animator.rig_root.scale.distance_to(Vector3.ONE) < 0.001, "landing scale did not recover")
	_expect(animator.torso_base.scale.distance_to(Vector3.ONE) < 0.001, "torso scale did not recover after landing")
	_expect(animator.head_secondary.scale.distance_to(Vector3.ONE) < 0.001, "head scale did not recover after landing")
	state.set_motion(Vector3(0.0, -8.0, 0.0), 0.0, false, false, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 10)
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 8)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.LAND, "repeat landing state was not selected")
	state.set_motion(Vector3(0.0, 8.0, 0.0), 0.0, false, false, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 8)
	_expect(animator.get_current_state() == BlockyHumanoidAnimator.JUMP, "landing could not transition directly into another jump")

	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, true, Vector3(10.0, 8.0, 1.0))
	_advance(animator, 30)
	_expect(animator.head_secondary.rotation.y > deg_to_rad(40.0), "head did not track the target")
	_expect(animator.head_secondary.rotation.y <= deg_to_rad(animator.profile.head_yaw_limit_degrees + 0.5), "head exceeded its yaw limit")
	_expect(animator.head_secondary.rotation.x < 0.0, "head did not pitch toward the elevated target")

	state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	animator.set_mining_active(true)
	_advance(animator, 11)
	_expect(abs(animator.right_arm_action.rotation.x) > deg_to_rad(45.0), "mining swing was not applied")
	_expect(abs(left_leg.rotation.x - right_leg.rotation.x) > 0.1, "mining replaced lower-body locomotion")
	animator.set_mining_active(false)
	_advance(animator, 20)
	animator.play_place()
	_advance(animator, 5)
	_expect(animator._placing, "placement one-shot ended too early")
	_expect(abs(animator.right_arm_action.rotation.x) > deg_to_rad(50.0), "placement gesture was not applied")
	_advance(animator, 12)
	_expect(not animator._placing, "placement one-shot did not end")
	_expect(abs(animator.right_arm_base.rotation.x + animator.right_arm_action.rotation.x) <= deg_to_rad(animator.profile.walk_arm_swing_degrees + 1.0), "placement arm did not return to locomotion")

	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 12)
	var attack_action := load("res://items/actions/definitions/copper_sword_melee.tres") as MeleeAttackActionDefinition
	var attack_rest_height: float = animator.rig_root.position.y
	var first_windup_sweep := 0.0
	var first_strike_sweep := 0.0
	var max_off_hand_sweep := 0.0
	var max_attack_lean := 0.0
	var max_attack_twist := 0.0
	var max_attack_leg_brace := 0.0
	var min_attack_arm_pitch := 0.0
	var min_attack_height := INF
	animator.play_attack(attack_action.attack_profile.duration, -1)
	for frame in range(29):
		_advance(animator, 1)
		if frame == 5:
			first_windup_sweep = animator.right_arm_action.rotation.z
		elif frame == 15:
			first_strike_sweep = animator.right_arm_action.rotation.z
		max_off_hand_sweep = max(max_off_hand_sweep, abs(animator.left_arm_action.rotation.z))
		max_attack_lean = max(max_attack_lean, animator.body_action.rotation.x)
		max_attack_twist = max(max_attack_twist, abs(animator.body_action.rotation.y))
		max_attack_leg_brace = max(max_attack_leg_brace, abs(animator.left_leg_base.rotation.x - animator.right_leg_base.rotation.x))
		min_attack_arm_pitch = min(min_attack_arm_pitch, animator.right_arm_action.rotation.x)
		min_attack_height = min(min_attack_height, animator.rig_root.position.y)
	_expect(first_windup_sweep > deg_to_rad(45.0) and first_strike_sweep < -deg_to_rad(68.0), "single sword hit did not sweep left to right")
	_expect(max_off_hand_sweep < 0.001, "off-hand joined the sword swing")
	_expect(max_attack_lean < 0.001, "sword attack unexpectedly leaned forward")
	_expect(max_attack_twist > deg_to_rad(55.0), "sword attack did not apply the tuned body twist")
	_expect(max_attack_leg_brace < 0.001, "sword attack unexpectedly braced the legs")
	_expect(min_attack_arm_pitch < -deg_to_rad(110.0), "sword attack did not apply the tuned arm pitch")
	_expect(min_attack_height > attack_rest_height - 0.03, "sword attack unexpectedly added a crouch")
	_expect(not animator._attacking, "sword attack one-shot did not end")
	var return_windup_sweep := 0.0
	var return_strike_sweep := 0.0
	animator.play_attack(attack_action.attack_profile.duration, 1)
	for frame in range(29):
		_advance(animator, 1)
		if frame == 5:
			return_windup_sweep = animator.right_arm_action.rotation.z
		elif frame == 15:
			return_strike_sweep = animator.right_arm_action.rotation.z
	_expect(return_windup_sweep < -deg_to_rad(45.0) and return_strike_sweep > deg_to_rad(68.0), "chained sword hit did not sweep right to left")
	_expect(abs(animator.left_arm_action.rotation.z) < 0.001, "off-hand joined the reversed sword swing")
	_expect(not animator._attacking, "reversed sword attack one-shot did not end")
	_advance(animator, 2)
	_expect(abs(animator.body_action.rotation.x) < 0.001, "sword attack body lean did not recover")
	animator.play_attack(attack_action.attack_profile.duration, -1)
	_advance(animator, 5)
	animator.cancel_attack()
	_advance(animator, 1)
	_expect(not animator._attacking and is_zero_approx(animator.attack_pose_weight), "cancelled sword attack remained active")
	_expect(abs(animator.right_arm_action.rotation.z) < 0.001, "cancelled sword attack retained its sweep")

	var hammer_item := load("res://items/definitions/copper_hammer.tres") as ItemDefinition
	var hammer_action := hammer_item.primary_action as MeleeAttackActionDefinition
	animator.rotation.y = deg_to_rad(37.0)
	var held_item_view := animator.get_node("RigRoot/BodySecondary/BodyAction/TorsoBase/RightShoulder/RightArmBase/RightArmAction/RightHandSocket") as HeldItemView
	held_item_view.show_preview_item(hammer_item)
	animator.set_held_melee_action(hammer_action)
	state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 8)
	held_item_view.set_attack_pose(animator.held_item_pose_weight, animator.right_arm_action.rotation.x, hammer_action, animator.held_item_windup_pose_weight)
	var walking_hammer_head := held_item_view.held_node.get_node("Head") as MeshInstance3D
	var left_hand_position: Vector3 = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
	var right_hand_position: Vector3 = animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
	_expect(animator.left_arm_action.rotation.x < animator.right_arm_action.rotation.x - deg_to_rad(8.0), "walking hammer pose did not hold the left hand higher than the right")
	_expect(abs(animator.left_arm_action.rotation.z) < deg_to_rad(5.0) and abs(animator.right_arm_action.rotation.z) < deg_to_rad(5.0), "walking hammer pose leaned the arms too far inward")
	_expect(Vector2(left_hand_position.x, left_hand_position.z).distance_to(Vector2(right_hand_position.x, right_hand_position.z)) > 0.5, "walking hammer pose did not keep the hands apart")
	_expect(left_hand_position.y > right_hand_position.y, "walking hammer pose did not place the left hand above the right")
	_expect(left_hand_position.distance_to(walking_hammer_head.global_position) < right_hand_position.distance_to(walking_hammer_head.global_position), "walking hammer pose did not place the left hand closer to the hammer head")
	var hammer_head_from_grip: Vector3 = walking_hammer_head.global_position - held_item_view.global_position
	_expect(hammer_head_from_grip.y > 0.0 and hammer_head_from_grip.y < Vector2(hammer_head_from_grip.x, hammer_head_from_grip.z).length(), "walking hammer was not held at a slight angle above horizontal")
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 12)
	held_item_view.set_attack_pose(animator.held_item_pose_weight, animator.right_arm_action.rotation.x, hammer_action, animator.held_item_windup_pose_weight)
	var hammer_rest_height: float = animator.rig_root.position.y
	var minimum_hammer_pitch := 0.0
	var impact_hammer_pitch := 0.0
	var maximum_hammer_lean := 0.0
	var minimum_hammer_height := INF
	var maximum_hammer_head_height := -INF
	var impact_hammer_head_height := INF
	var impact_striking_face_height := INF
	var impact_arm_pitch_difference := INF
	var previous_hammer_pitch: float = animator.right_arm_action.rotation.x
	var maximum_pitch_step: float = 0.0
	var overhead_hammer_basis := Basis.IDENTITY
	var maximum_mid_swing_up_dot := -1.0
	var impact_hammer_basis := Basis.IDENTITY
	var impact_hammer_head_position := Vector3.ZERO
	var impact_grip_position := Vector3.ZERO
	var impact_left_hand_position := Vector3.ZERO
	var impact_right_hand_position := Vector3.ZERO
	var impact_hold_start_pitch := 0.0
	var impact_hold_end_pitch := 0.0
	var recovery_midpoint_hammer_head_height := -INF
	var overhead_hand_distance := INF
	var impact_hand_distance := INF
	var hold_end_hand_distance := INF
	var recovery_midpoint_hand_distance := 0.0
	var recovery_midpoint_alignment_weight := 0.0
	var recovery_midpoint_pose_weight := 0.0
	var recovery_midpoint_linear_error := INF
	var maximum_recovery_grip_step := 0.0
	var maximum_recovery_rotation_step := 0.0
	var maximum_recovery_grip_step_progress := 0.0
	var maximum_recovery_rotation_step_progress := 0.0
	var maximum_aligned_grip_to_hands := 0.0
	var previous_hammer_grip_position := held_item_view.global_position
	var previous_hammer_rotation := held_item_view.held_node.global_transform.basis.orthonormalized().get_rotation_quaternion()
	var overhead_captured := false
	var impact_captured := false
	var hold_end_captured := false
	var recovery_midpoint_captured := false
	held_item_view.capture_attack_idle_transform(animator.right_arm_base.global_transform)
	animator.play_attack(hammer_action.attack_profile.duration, -1, hammer_action.animation_style)
	var hammer_attack_frames := ceili(hammer_action.attack_profile.duration * 60.0) + 2
	for _frame in range(hammer_attack_frames):
		_advance(animator, 1)
		if not is_zero_approx(animator.held_item_recovery_progress):
			held_item_view.begin_linear_attack_recovery(animator.global_transform)
		held_item_view.set_attack_pose(animator.held_item_pose_weight, animator.right_arm_action.rotation.x, hammer_action, animator.held_item_windup_pose_weight)
		held_item_view.align_overhead_striking_face(animator.held_item_alignment_weight, animator.held_item_face_turn_weight, hammer_action, animator.global_transform.basis.z)
		held_item_view.anchor_two_handed_grip(
			animator.held_item_alignment_weight,
			animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0)),
			animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
		)
		held_item_view.apply_linear_attack_recovery(animator.held_item_recovery_progress, animator.global_transform, animator.right_arm_base.global_transform)
		var hammer_head := held_item_view.held_node.get_node("Head") as MeshInstance3D
		var hammer_basis := held_item_view.held_node.global_transform.basis.orthonormalized()
		var hammer_rotation := hammer_basis.get_rotation_quaternion()
		var attack_progress: float = animator._attack_elapsed / hammer_action.attack_profile.duration
		if attack_progress >= BlockyHumanoidAnimator.HAMMER_WINDUP_END and attack_progress <= BlockyHumanoidAnimator.HAMMER_HOLD_END:
			var aligned_left_hand: Vector3 = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
			var aligned_right_hand: Vector3 = animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
			var aligned_hand_midpoint: Vector3 = (aligned_left_hand + aligned_right_hand) * 0.5
			maximum_aligned_grip_to_hands = maxf(maximum_aligned_grip_to_hands, held_item_view.global_position.distance_to(aligned_hand_midpoint))
		if attack_progress >= BlockyHumanoidAnimator.HAMMER_HOLD_END:
			var recovery_grip_step := held_item_view.global_position.distance_to(previous_hammer_grip_position)
			var recovery_rotation_step := hammer_rotation.angle_to(previous_hammer_rotation)
			if recovery_grip_step > maximum_recovery_grip_step:
				maximum_recovery_grip_step = recovery_grip_step
				maximum_recovery_grip_step_progress = attack_progress
			if recovery_rotation_step > maximum_recovery_rotation_step:
				maximum_recovery_rotation_step = recovery_rotation_step
				maximum_recovery_rotation_step_progress = attack_progress
		previous_hammer_grip_position = held_item_view.global_position
		previous_hammer_rotation = hammer_rotation
		maximum_pitch_step = maxf(maximum_pitch_step, abs(animator.right_arm_action.rotation.x - previous_hammer_pitch))
		previous_hammer_pitch = animator.right_arm_action.rotation.x
		minimum_hammer_pitch = minf(minimum_hammer_pitch, animator.right_arm_action.rotation.x)
		maximum_hammer_lean = maxf(maximum_hammer_lean, animator.body_action.rotation.x)
		minimum_hammer_height = minf(minimum_hammer_height, animator.rig_root.position.y)
		maximum_hammer_head_height = maxf(maximum_hammer_head_height, hammer_head.global_position.y)
		if not overhead_captured and attack_progress >= BlockyHumanoidAnimator.HAMMER_WINDUP_END - 0.005:
			overhead_captured = true
			overhead_hammer_basis = hammer_basis
			overhead_hand_distance = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0)).distance_to(animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0)))
		if attack_progress >= BlockyHumanoidAnimator.HAMMER_WINDUP_END and attack_progress <= BlockyHumanoidAnimator.HAMMER_IMPACT:
			maximum_mid_swing_up_dot = maxf(maximum_mid_swing_up_dot, hammer_basis.y.dot(Vector3.UP))
		if not impact_captured and attack_progress >= BlockyHumanoidAnimator.HAMMER_IMPACT + 0.01:
			impact_captured = true
			impact_hammer_pitch = animator.right_arm_action.rotation.x
			impact_hammer_head_height = hammer_head.global_position.y
			impact_hammer_basis = hammer_basis
			impact_hammer_head_position = hammer_head.global_position
			var hammer_head_mesh := hammer_head.mesh as BoxMesh
			impact_striking_face_height = (hammer_head.global_position + hammer_basis.x * hammer_head_mesh.size.x * 0.5).y
			impact_grip_position = held_item_view.global_position
			impact_left_hand_position = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
			impact_right_hand_position = animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
			impact_arm_pitch_difference = abs(animator.left_arm_action.rotation.x - animator.right_arm_action.rotation.x)
			impact_hand_distance = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0)).distance_to(animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0)))
			impact_hold_start_pitch = animator.right_arm_action.rotation.x
		if not hold_end_captured and attack_progress >= BlockyHumanoidAnimator.HAMMER_HOLD_END - 0.01:
			hold_end_captured = true
			impact_hold_end_pitch = animator.right_arm_action.rotation.x
			hold_end_hand_distance = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0)).distance_to(animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0)))
		var recovery_midpoint := BlockyHumanoidAnimator.HAMMER_HOLD_END + (1.0 - BlockyHumanoidAnimator.HAMMER_HOLD_END) * 0.5
		if not recovery_midpoint_captured and attack_progress >= recovery_midpoint:
			recovery_midpoint_captured = true
			recovery_midpoint_hammer_head_height = hammer_head.global_position.y
			recovery_midpoint_hand_distance = animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0)).distance_to(animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0)))
			recovery_midpoint_alignment_weight = animator.held_item_alignment_weight
			recovery_midpoint_pose_weight = animator.held_item_pose_weight
			var midpoint_relative: Transform3D = animator.global_transform.affine_inverse() * held_item_view.global_transform
			var idle_midpoint_global: Transform3D = animator.right_arm_base.global_transform * held_item_view._attack_idle_relative_transform
			var idle_midpoint_relative: Transform3D = animator.global_transform.affine_inverse() * idle_midpoint_global
			var expected_midpoint: Vector3 = held_item_view._recovery_start_relative_transform.origin.lerp(idle_midpoint_relative.origin, animator.held_item_recovery_progress)
			recovery_midpoint_linear_error = midpoint_relative.origin.distance_to(expected_midpoint)
	_expect(minimum_hammer_pitch < -deg_to_rad(155.0), "hammer slam did not raise both hands overhead")
	_expect(maximum_pitch_step < deg_to_rad(30.0), "hammer slam snapped between animation poses")
	_expect(overhead_hammer_basis.x.dot(Vector3.UP) > 0.999, "hammer striking face did not point straight up overhead")
	_expect(overhead_hammer_basis.y.dot(-animator.global_transform.basis.z.normalized()) > 0.999, "overhead hammer head did not extend behind the player's hands")
	_expect(overhead_hand_distance < 0.12, "hammer hands did not come together overhead distance=%.2f" % overhead_hand_distance)
	_expect(maximum_mid_swing_up_dot > 0.95, "hammer head did not travel over the hands during the swing up_dot=%.2f" % maximum_mid_swing_up_dot)
	_expect(impact_hammer_pitch > -deg_to_rad(45.0), "hammer slam did not drive the hands toward the ground")
	_expect(impact_hammer_basis.x.dot(Vector3.DOWN) > 0.999, "hammer striking face was not flat against the ground at impact")
	_expect(impact_hammer_basis.y.dot(animator.global_transform.basis.z.normalized()) > 0.999, "impact hammer handle was not aligned with the player")
	_expect((impact_hammer_head_position - impact_grip_position).dot(animator.global_transform.basis.z.normalized()) > 0.0, "hammer head did not land in front of the player")
	_expect(abs(impact_hold_start_pitch - impact_hold_end_pitch) < 0.001, "hammer did not pause briefly against the ground")
	_expect(impact_arm_pitch_difference < 0.001, "hammer slam arms did not move together at impact")
	_expect(impact_hand_distance < 0.12 and hold_end_hand_distance < 0.12, "hammer hands separated before pickup impact=%.2f hold=%.2f" % [impact_hand_distance, hold_end_hand_distance])
	_expect(impact_grip_position.distance_to(impact_left_hand_position) < 0.001 and impact_grip_position.distance_to(impact_right_hand_position) < 0.001, "hammer grip floated away from the joined hands at impact")
	_expect(maximum_aligned_grip_to_hands < 0.001, "hammer grip separated from the hands during its aligned swing")
	_expect(maximum_hammer_lean > deg_to_rad(20.0), "hammer slam did not lean into the impact")
	_expect(minimum_hammer_height < hammer_rest_height - 0.1, "hammer slam did not crouch at impact")
	_expect(maximum_hammer_head_height > 1.8, "hammer head did not rise above the player height=%.2f" % maximum_hammer_head_height)
	_expect(absf(impact_striking_face_height - 0.04) < 0.03, "hammer striking face did not meet the shockwave plane face=%.3f" % impact_striking_face_height)
	var impact_head_offset: Vector3 = impact_hammer_head_position - animator.global_position
	impact_head_offset.y = 0.0
	_expect(absf(impact_head_offset.length() - hammer_action.attack_profile.impact_origin_forward_offset) < 0.02, "hammer combat origin does not match the rendered head contact offset rendered=%.3f configured=%.3f" % [impact_head_offset.length(), hammer_action.attack_profile.impact_origin_forward_offset])
	_expect(recovery_midpoint_hammer_head_height > impact_hammer_head_height + 0.25, "hammer recovery did not lift the head clear of the ground impact=%.2f midpoint=%.2f" % [impact_hammer_head_height, recovery_midpoint_hammer_head_height])
	_expect(recovery_midpoint_hand_distance > 0.2, "hammer hands did not separate during the direct return distance=%.2f" % recovery_midpoint_hand_distance)
	_expect(is_zero_approx(recovery_midpoint_alignment_weight) and abs(recovery_midpoint_pose_weight - 0.5) < 0.08, "hammer recovery did not linearly interpolate the authored local pose")
	_expect(recovery_midpoint_linear_error < 0.01, "hammer grip did not follow its straight recovery path error=%.3f" % recovery_midpoint_linear_error)
	var recovery_frame_count := hammer_action.attack_profile.duration * (1.0 - BlockyHumanoidAnimator.HAMMER_HOLD_END) * 60.0
	var idle_endpoint_global: Transform3D = animator.right_arm_base.global_transform * held_item_view._attack_idle_relative_transform
	var idle_endpoint_relative: Transform3D = animator.global_transform.affine_inverse() * idle_endpoint_global
	var expected_recovery_grip_step := held_item_view._recovery_start_relative_transform.origin.distance_to(idle_endpoint_relative.origin) / recovery_frame_count
	_expect(maximum_recovery_grip_step < expected_recovery_grip_step * 2.0, "hammer grip exceeded its linear step with moving hand target step=%.2f expected=%.2f progress=%.2f" % [maximum_recovery_grip_step, expected_recovery_grip_step, maximum_recovery_grip_step_progress])
	_expect(maximum_recovery_rotation_step < deg_to_rad(25.0), "hammer recovery snapped the held model angle=%.1f progress=%.2f" % [rad_to_deg(maximum_recovery_rotation_step), maximum_recovery_rotation_step_progress])
	_expect(not animator._attacking, "hammer slam one-shot did not end")
	var hammer_scale_before_repeats := held_item_view.scale
	for _attack_index in range(5):
		held_item_view.capture_attack_idle_transform(animator.right_arm_base.global_transform)
		animator.play_attack(hammer_action.attack_profile.duration, -1, hammer_action.animation_style)
		for _frame in range(hammer_attack_frames):
			_advance(animator, 1)
			if not is_zero_approx(animator.held_item_recovery_progress):
				held_item_view.begin_linear_attack_recovery(animator.global_transform)
			held_item_view.set_attack_pose(animator.held_item_pose_weight, animator.right_arm_action.rotation.x, hammer_action, animator.held_item_windup_pose_weight)
			held_item_view.align_overhead_striking_face(animator.held_item_alignment_weight, animator.held_item_face_turn_weight, hammer_action, animator.global_transform.basis.z)
			held_item_view.anchor_two_handed_grip(
				animator.held_item_alignment_weight,
				animator.left_arm_action.to_global(Vector3(0.0, -0.675, 0.0)),
				animator.right_arm_action.to_global(Vector3(0.0, -0.675, 0.0))
			)
			held_item_view.apply_linear_attack_recovery(animator.held_item_recovery_progress, animator.global_transform, animator.right_arm_base.global_transform)
	_expect(held_item_view.scale.is_equal_approx(hammer_scale_before_repeats), "repeated hammer attacks compounded the held model scale")
	animator.set_held_melee_action(null)
	_advance(animator, 2)
	_expect(abs(animator.left_arm_action.rotation.z) < 0.001 and abs(animator.right_arm_action.rotation.z) < 0.001, "hammer two-handed pose did not clear")

	await _run_crowd_smoke(packed)
	animator.queue_free()
	await process_frame
	await process_frame
	var orphan_after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan count ended at %d" % orphan_after)
	if _errors.is_empty():
		print("PLAYER_ANIMATION PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("PLAYER_ANIMATION FAIL %s" % str(_errors))
		quit(1)

func _run_directional_gait_checks(animator: BlockyHumanoidAnimator, state: ActorAnimationState, left_leg_origin: Vector3, right_leg_origin: Vector3):
	var left_leg = animator.left_leg_locomotion
	var right_leg = animator.right_leg_locomotion
	var directions: Array[Vector2] = [
		Vector2(0.0, 1.0),
		Vector2(0.0, -1.0),
		Vector2(1.0, 0.0),
		Vector2(-1.0, 0.0),
		Vector2(1.0, 1.0).normalized(),
		Vector2(-1.0, 1.0).normalized(),
		Vector2(1.0, -1.0).normalized(),
		Vector2(-1.0, -1.0).normalized(),
	]
	for sprinting in [false, true]:
		var speed: float = 8.0 if sprinting else 5.5
		var travel: float = animator.profile.sprint_leg_travel if sprinting else animator.profile.walk_leg_travel
		var lift: float = animator.profile.sprint_leg_lift if sprinting else animator.profile.walk_leg_lift
		var mode = "sprint" if sprinting else "walk"
		for direction in directions:
			state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
			_advance(animator, 1)
			_expect(animator._gait_direction.is_zero_approx(), "%s gait direction did not reset at rest" % mode)
			state.set_motion(Vector3(direction.x * speed, 0.0, direction.y * speed), 1.0, sprinting, true, 0.0, 0.0, false, Vector3.ZERO)
			_advance(animator, 60)
			_expect(animator._gait_direction.distance_to(direction) < 0.001, "%s gait did not settle toward %s" % [mode, direction])
			_expect(abs(animator._gait_direction.length() - 1.0) < 0.001, "%s diagonal blend lost full stride amplitude direction=%s" % [mode, direction])
			var left_min = INF
			var left_max = -INF
			var right_min = INF
			var right_max = -INF
			var max_lift = -INF
			var min_stance_height = INF
			var max_stance_height = -INF
			var min_opposition_product = INF
			var max_x_rotation = 0.0
			var max_z_rotation = 0.0
			for _frame in range(80):
				_advance(animator, 1)
				var left_foot = animator.left_foot_marker.global_position
				var right_foot = animator.right_foot_marker.global_position
				var left_projection = Vector2(left_foot.x, left_foot.z).dot(direction)
				var right_projection = Vector2(right_foot.x, right_foot.z).dot(direction)
				left_min = min(left_min, left_projection)
				left_max = max(left_max, left_projection)
				right_min = min(right_min, right_projection)
				right_max = max(right_max, right_projection)
				max_lift = max(max_lift, left_foot.y)
				var cycle = fposmod(animator._gait_phase() / TAU, 1.0)
				if cycle < animator.profile.gait_push_pose:
					min_stance_height = min(min_stance_height, left_foot.y)
					max_stance_height = max(max_stance_height, left_foot.y)
				var left_displacement = Vector2(left_leg.position.x - left_leg_origin.x, left_leg.position.z - left_leg_origin.z).dot(direction)
				var right_displacement = Vector2(right_leg.position.x - right_leg_origin.x, right_leg.position.z - right_leg_origin.z).dot(direction)
				min_opposition_product = min(min_opposition_product, left_displacement * right_displacement)
				max_x_rotation = max(max_x_rotation, abs(left_leg.rotation.x))
				max_z_rotation = max(max_z_rotation, abs(left_leg.rotation.z))
			var left_range = left_max - left_min
			var right_range = right_max - right_min
			_expect(abs(left_range - travel * 2.0) < 0.015, "%s gait did not use full travel toward %s range=%.3f" % [mode, direction, left_range])
			_expect(abs(left_range - right_range) < 0.002, "%s leg paths were not mirrored toward %s" % [mode, direction])
			_expect(abs(max_lift - lift) < 0.005, "%s recovery lift changed toward %s height=%.3f" % [mode, direction, max_lift])
			_expect(max_stance_height - min_stance_height < 0.002, "%s stance height changed toward %s" % [mode, direction])
			_expect(min_opposition_product < -0.05, "%s legs lost half-cycle opposition toward %s" % [mode, direction])
			if abs(direction.x) > 0.5:
				_expect(max_z_rotation > deg_to_rad(20.0), "%s lateral gait did not rotate around its directional axis toward %s" % [mode, direction])
			if abs(direction.y) > 0.5:
				_expect(max_x_rotation > deg_to_rad(19.0), "%s longitudinal gait did not rotate around its directional axis toward %s" % [mode, direction])
	state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 60)
	state.set_motion(Vector3(5.5, 0.0, 0.0), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 1)
	var direction_response = 1.0 - exp(-animator.profile.gait_direction_response / 60.0)
	var expected_quarter_turn = Vector2(direction_response, 1.0 - direction_response)
	_expect(animator._gait_direction.distance_to(expected_quarter_turn) < 0.001, "90 degree gait transition did not use exponential smoothing direction=%s" % animator._gait_direction)
	_expect(animator._gait_direction.length() < 0.9, "90 degree gait transition normalized before settling")
	_advance(animator, 60)
	_expect(animator._gait_direction.distance_to(Vector2(1.0, 0.0)) < 0.001, "90 degree gait transition did not settle")
	state.set_motion(Vector3(-5.5, 0.0, 0.0), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	var minimum_reversal_strength = INF
	var crossed_zero = false
	var previous_x = animator._gait_direction.x
	for _frame in range(8):
		_advance(animator, 1)
		minimum_reversal_strength = min(minimum_reversal_strength, animator._gait_direction.length())
		if previous_x > 0.0 and animator._gait_direction.x < 0.0:
			crossed_zero = true
		previous_x = animator._gait_direction.x
	_expect(crossed_zero and minimum_reversal_strength < 0.11, "180 degree gait reversal did not contract through zero strength=%.3f" % minimum_reversal_strength)
	_advance(animator, 60)
	var attack_foot_min = INF
	var attack_foot_max = -INF
	var max_attack_leg_rotation = 0.0
	animator.play_attack(0.48, -1)
	for _frame in range(29):
		_advance(animator, 1)
		var foot_projection = -animator.left_foot_marker.global_position.x
		attack_foot_min = min(attack_foot_min, foot_projection)
		attack_foot_max = max(attack_foot_max, foot_projection)
		max_attack_leg_rotation = max(max_attack_leg_rotation, abs(left_leg.rotation.z - right_leg.rotation.z))
	_expect(max_attack_leg_rotation > deg_to_rad(30.0), "moving attack replaced directional lower-body rotation")
	_expect(attack_foot_max - attack_foot_min > 0.45, "moving attack stopped the directional foot path")
	state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
	_advance(animator, 1)
	_expect(animator._gait_direction.is_zero_approx(), "stopping did not reset the gait direction")

func _run_crowd_smoke(packed: PackedScene):
	var crowd = Node3D.new()
	root.add_child(crowd)
	var animators: Array[BlockyHumanoidAnimator] = []
	for index in range(100):
		var animator = packed.instantiate() as BlockyHumanoidAnimator
		animator.position = Vector3(index % 10, 0.0, index / 10)
		crowd.add_child(animator)
		animators.append(animator)
	await process_frame
	for index in range(animators.size()):
		var state = ActorAnimationState.new()
		state.set_motion(Vector3(0.0, 0.0, 5.5), 1.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
		animators[index].setup(state)
	var first_torso = animators[0].get_node("RigRoot/BodySecondary/BodyAction/TorsoBase/Torso") as MeshInstance3D
	var second_torso = animators[1].get_node("RigRoot/BodySecondary/BodyAction/TorsoBase/Torso") as MeshInstance3D
	_expect(first_torso.mesh == second_torso.mesh, "crowd torso meshes were duplicated")
	_expect(animators[0].profile == animators[1].profile, "crowd profiles were duplicated")
	var node_count_before = _count_nodes(crowd)
	var start_msec = Time.get_ticks_msec()
	for _frame in range(60):
		for animator in animators:
			animator.advance_animation(1.0 / 60.0)
	var elapsed_msec = Time.get_ticks_msec() - start_msec
	_expect(_count_nodes(crowd) == node_count_before, "crowd update changed its node count")
	_expect(elapsed_msec < 2000, "crowd animation exceeded the generous regression budget elapsed_ms=%d" % elapsed_msec)
	print("[player_animation] crowd actors=100 frames=60 elapsed_ms=%d" % elapsed_msec)
	crowd.queue_free()
	await process_frame

func _advance(animator: BlockyHumanoidAnimator, frames: int):
	for _frame in range(frames):
		animator.advance_animation(1.0 / 60.0)

func _leg_foot(foot_marker: Marker3D) -> Vector3:
	return foot_marker.global_position

func _count_nodes(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count

func _expect(condition: bool, message: String):
	if not condition:
		_fail(message)

func _fail(message: String):
	print("[player_animation] ERROR: %s" % message)
	print("FAIL: %s" % message)
	_errors.append(message)
