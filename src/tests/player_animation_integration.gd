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
	animator.play_attack(attack_action.attack_duration, -1)
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
	animator.play_attack(attack_action.attack_duration, 1)
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
	animator.play_attack(attack_action.attack_duration, -1)
	_advance(animator, 5)
	animator.cancel_attack()
	_advance(animator, 1)
	_expect(not animator._attacking and is_zero_approx(animator.attack_pose_weight), "cancelled sword attack remained active")
	_expect(abs(animator.right_arm_action.rotation.z) < 0.001, "cancelled sword attack retained its sweep")

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
