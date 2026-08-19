extends Node3D
class_name BlockyHumanoidAnimator

const IDLE: StringName = &"Idle"
const WALK: StringName = &"Walk"
const SPRINT: StringName = &"Sprint"
const JUMP: StringName = &"Jump"
const FALL: StringName = &"Fall"
const LAND: StringName = &"Land"
const TUNING_RIG: StringName = &"Whole Rig"
const TUNING_BODY: StringName = &"Body"
const TUNING_HEAD: StringName = &"Head"
const TUNING_LEFT_ARM: StringName = &"Left Arm"
const TUNING_RIGHT_ARM: StringName = &"Right Arm"
const TUNING_LEFT_LEG: StringName = &"Left Leg"
const TUNING_RIGHT_LEG: StringName = &"Right Leg"
const HAMMER_WINDUP_END: float = 0.465
const HAMMER_IMPACT: float = 0.59
const HAMMER_HOLD_END: float = 0.80
const HAMMER_BODY_DROP: float = 0.17

@export var profile: BlockyHumanoidAnimationProfile

@onready var rig_root: Node3D = $RigRoot as Node3D
@onready var body_secondary: Node3D = $RigRoot/BodySecondary as Node3D
@onready var body_action: Node3D = $RigRoot/BodySecondary/BodyAction as Node3D
@onready var torso_base: Node3D = $RigRoot/BodySecondary/BodyAction/TorsoBase as Node3D
@onready var head_secondary: Node3D = $RigRoot/BodySecondary/BodyAction/TorsoBase/HeadAnchor/HeadBase/HeadSecondary as Node3D
@onready var left_arm_base: Node3D = $RigRoot/BodySecondary/BodyAction/TorsoBase/LeftShoulder/LeftArmBase as Node3D
@onready var left_arm_action: Node3D = $RigRoot/BodySecondary/BodyAction/TorsoBase/LeftShoulder/LeftArmBase/LeftArmAction as Node3D
@onready var right_arm_base: Node3D = $RigRoot/BodySecondary/BodyAction/TorsoBase/RightShoulder/RightArmBase as Node3D
@onready var right_arm_action: Node3D = $RigRoot/BodySecondary/BodyAction/TorsoBase/RightShoulder/RightArmBase/RightArmAction as Node3D
@onready var left_hip: Node3D = $RigRoot/LeftHip as Node3D
@onready var right_hip: Node3D = $RigRoot/RightHip as Node3D
@onready var left_leg_locomotion: Node3D = $RigRoot/LeftHip/LeftLegLocomotion as Node3D
@onready var right_leg_locomotion: Node3D = $RigRoot/RightHip/RightLegLocomotion as Node3D
@onready var left_leg_base: Node3D = $RigRoot/LeftHip/LeftLegLocomotion/LeftLegBase as Node3D
@onready var right_leg_base: Node3D = $RigRoot/RightHip/RightLegLocomotion/RightLegBase as Node3D
@onready var left_foot_marker: Marker3D = $RigRoot/LeftHip/LeftLegLocomotion/LeftLegBase/LeftFootMarker as Marker3D
@onready var right_foot_marker: Marker3D = $RigRoot/RightHip/RightLegLocomotion/RightLegBase/RightFootMarker as Marker3D

var animation_state: ActorAnimationState
var _current_state: StringName = IDLE
var _elapsed: float = 0.0
var _walk_phase: float = 0.0
var _shaped_gait_phase: float = 0.0
var _gait_direction: Vector2 = Vector2.ZERO
var _mine_phase: float = 0.0
var _mine_blend: float = 0.0
var _mining_active: bool = false
var _place_elapsed: float = 0.0
var _placing: bool = false
var _attack_elapsed: float = 0.0
var _attack_duration: float = 0.0
var _attack_direction: int = -1
var _attack_animation_style: int = MeleeAttackActionDefinition.AnimationStyle.SWEEP
var _attack_contact_progress: float = 0.52
var _attacking: bool = false
var _held_melee_action: MeleeAttackActionDefinition
var attack_pose_weight: float = 0.0
var held_item_windup_pose_weight: float = 0.0
var held_item_pose_weight: float = 0.0
var held_item_alignment_weight: float = 0.0
var held_item_face_turn_weight: float = 0.0
var held_item_recovery_progress: float = 0.0
var _landing_elapsed: float = 0.0
var _landing_strength: float = 0.0
var _previous_vertical_speed: float = 0.0
var _was_grounded: bool = false
var _current_body_rotation: Vector3 = Vector3.ZERO
var _current_head_rotation: Vector3 = Vector3.ZERO
var _left_leg_origin: Vector3
var _right_leg_origin: Vector3
var _previous_forward_speed: float = 0.0
var _inertia_pitch: float = 0.0
var _rig_root_origin: Vector3
var _body_secondary_origin: Vector3
var _body_action_origin: Vector3
var _head_secondary_origin: Vector3
var _left_arm_action_origin: Vector3
var _right_arm_action_origin: Vector3
var _tuning_positions: Dictionary = {}
var _tuning_rotations_degrees: Dictionary = {}
var _tuning_scales: Dictionary = {}
var _has_tuning_overrides: bool = false

func setup(p_animation_state: ActorAnimationState):
	animation_state = p_animation_state
	assert(profile != null)
	_gait_direction = Vector2.ZERO
	_current_state = IDLE
	_left_leg_origin = left_leg_locomotion.position
	_right_leg_origin = right_leg_locomotion.position
	_was_grounded = animation_state.grounded
	_previous_vertical_speed = animation_state.local_velocity.y
	_previous_forward_speed = animation_state.local_velocity.z
	_rig_root_origin = rig_root.position
	_body_secondary_origin = body_secondary.position
	_body_action_origin = body_action.position
	_head_secondary_origin = head_secondary.position
	_left_arm_action_origin = left_arm_action.position
	_right_arm_action_origin = right_arm_action.position
	reset_tuning_transforms()

func get_tuning_parts() -> Array[StringName]:
	return [TUNING_RIG, TUNING_BODY, TUNING_HEAD, TUNING_LEFT_ARM, TUNING_RIGHT_ARM, TUNING_LEFT_LEG, TUNING_RIGHT_LEG]

func get_tuning_transform(part: StringName) -> Dictionary:
	assert(_tuning_positions.has(part))
	return {
		"position": _tuning_positions[part],
		"rotation_degrees": _tuning_rotations_degrees[part],
		"scale": _tuning_scales[part],
	}

func set_tuning_transform(part: StringName, p_position: Vector3, p_rotation_degrees: Vector3, p_scale: Vector3):
	assert(_tuning_positions.has(part))
	_tuning_positions[part] = p_position
	_tuning_rotations_degrees[part] = p_rotation_degrees
	_tuning_scales[part] = p_scale
	_refresh_tuning_overrides()

func reset_tuning_transforms():
	for part in get_tuning_parts():
		_tuning_positions[part] = Vector3.ZERO
		_tuning_rotations_degrees[part] = Vector3.ZERO
		_tuning_scales[part] = Vector3.ONE
	_has_tuning_overrides = false

func get_current_state() -> StringName:
	return _current_state

func _refresh_tuning_overrides():
	_has_tuning_overrides = false
	for part in get_tuning_parts():
		if not (_tuning_positions[part] as Vector3).is_zero_approx() or not (_tuning_rotations_degrees[part] as Vector3).is_zero_approx() or not (_tuning_scales[part] as Vector3).is_equal_approx(Vector3.ONE):
			_has_tuning_overrides = true
			return

func set_mining_active(active: bool):
	if active and not _mining_active:
		_mine_phase = 0.0
	_mining_active = active

func play_place():
	_attacking = false
	_placing = true
	_place_elapsed = 0.0

func set_held_melee_action(action: MeleeAttackActionDefinition) -> void:
	_held_melee_action = action

func prepare_held_idle_reference(action: MeleeAttackActionDefinition) -> void:
	cancel_attack()
	_placing = false
	_place_elapsed = 0.0
	_mining_active = false
	_mine_blend = 0.0
	_held_melee_action = action
	_update_actions(0.0)

func play_attack(duration: float, direction: int, animation_style: int = MeleeAttackActionDefinition.AnimationStyle.SWEEP, contact_progress: float = 0.52):
	assert(duration > 0.0)
	assert(direction == -1 or direction == 1)
	assert(animation_style >= MeleeAttackActionDefinition.AnimationStyle.SWEEP and animation_style <= MeleeAttackActionDefinition.AnimationStyle.OVERHEAD_SLAM)
	assert(animation_style != MeleeAttackActionDefinition.AnimationStyle.SWEEP or (contact_progress > MeleeAttackActionDefinition.SWEEP_WINDUP_END and contact_progress < MeleeAttackActionDefinition.SWEEP_RECOVERY_START))
	_placing = false
	_attacking = true
	_attack_elapsed = 0.0
	_attack_duration = duration
	_attack_direction = direction
	_attack_animation_style = animation_style
	_attack_contact_progress = contact_progress

func cancel_attack():
	_attacking = false
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	attack_pose_weight = 0.0
	held_item_windup_pose_weight = 0.0
	held_item_pose_weight = 0.0
	held_item_alignment_weight = 0.0
	held_item_face_turn_weight = 0.0
	held_item_recovery_progress = 0.0

func is_attacking() -> bool:
	return _attacking

func get_attack_progress() -> float:
	if not _attacking:
		return 0.0
	return clampf(_attack_elapsed / _attack_duration, 0.0, 1.0)

func prepare_preview(grounded: bool):
	_was_grounded = grounded
	_landing_strength = 0.0
	_landing_elapsed = profile.landing_seconds
	_mining_active = false
	_mine_blend = 0.0
	_placing = false
	_attacking = false
	attack_pose_weight = 0.0
	_gait_direction = Vector2(0.0, 1.0)
	held_item_windup_pose_weight = 0.0
	held_item_pose_weight = 0.0
	held_item_alignment_weight = 0.0
	held_item_face_turn_weight = 0.0
	held_item_recovery_progress = 0.0

func prepare_attack_preview() -> void:
	prepare_preview(true)
	_elapsed = 0.0
	_walk_phase = 0.0
	_shaped_gait_phase = 0.0
	_current_body_rotation = Vector3.ZERO
	_current_head_rotation = Vector3.ZERO
	_previous_forward_speed = animation_state.local_velocity.z
	_inertia_pitch = 0.0
	advance_animation(0.0)

func advance_animation(delta: float):
	assert(animation_state != null)
	_elapsed += delta
	_update_locomotion(delta)
	_update_body(delta)
	_update_head(delta)
	_update_actions(delta)
	if _has_tuning_overrides:
		_apply_tuning_transforms()
	_previous_vertical_speed = animation_state.local_velocity.y
	_was_grounded = animation_state.grounded

func _update_locomotion(delta: float):
	var target_gait_direction = Vector2(animation_state.local_velocity.x, animation_state.local_velocity.z)
	if animation_state.speed_ratio <= 0.05 or target_gait_direction.is_zero_approx():
		_gait_direction = Vector2.ZERO
	else:
		target_gait_direction = target_gait_direction.normalized()
		var direction_response = 1.0 - exp(-profile.gait_direction_response * delta)
		_gait_direction = _gait_direction.lerp(target_gait_direction, direction_response)
	var landed = animation_state.grounded and not _was_grounded
	if landed:
		_landing_elapsed = 0.0
		_landing_strength = clamp((-_previous_vertical_speed - 2.0) / 10.0, 0.2, 1.0)
		_current_state = LAND
	if not animation_state.grounded:
		_landing_elapsed = profile.landing_seconds
		_landing_strength = 0.0
		_current_state = JUMP if animation_state.local_velocity.y > 0.2 else FALL
	elif _landing_elapsed < profile.landing_seconds and _landing_strength > 0.0:
		_landing_elapsed += delta
	else:
		_landing_strength = 0.0
		if animation_state.sprinting:
			_current_state = SPRINT
		elif animation_state.speed_ratio > 0.05:
			_current_state = WALK
		else:
			_current_state = IDLE
	var cycle_seconds = profile.sprint_cycle_seconds if animation_state.sprinting else profile.walk_cycle_seconds
	var walk_weight = animation_state.speed_ratio if animation_state.grounded else 0.0
	_walk_phase = fmod(_walk_phase + delta * TAU / cycle_seconds * walk_weight, TAU)
	var rhythm_shape = profile.sprint_rhythm_shape if animation_state.sprinting else profile.walk_rhythm_shape
	_shaped_gait_phase = _walk_phase - sin(_walk_phase * 2.0) * rhythm_shape

func _update_body(delta: float):
	var response = 1.0 - exp(-profile.motion_response * delta)
	var forward_speed = animation_state.local_velocity.z
	var speed_delta = forward_speed - _previous_forward_speed
	if abs(speed_delta) > 0.01:
		var speed_scale = max(max(abs(forward_speed), abs(_previous_forward_speed)), 1.0)
		var overshoot_degrees = profile.acceleration_overshoot_degrees if speed_delta > 0.0 else profile.braking_overshoot_degrees
		_inertia_pitch += deg_to_rad(overshoot_degrees) * speed_delta / speed_scale
		_inertia_pitch = clamp(_inertia_pitch, -deg_to_rad(profile.braking_overshoot_degrees), deg_to_rad(profile.acceleration_overshoot_degrees))
	_previous_forward_speed = forward_speed
	_inertia_pitch *= exp(-profile.inertia_recovery * delta)
	var planar_velocity = Vector2(animation_state.local_velocity.x, animation_state.local_velocity.z)
	var move_direction = planar_velocity.normalized() if planar_velocity.length_squared() > 0.0001 else Vector2.ZERO
	var side_ratio = move_direction.x * animation_state.speed_ratio
	var forward_ratio = move_direction.y * animation_state.speed_ratio
	var turn_ratio = clamp(animation_state.turn_rate / 6.0, -1.0, 1.0)
	var lean_degrees = profile.sprint_lean_degrees if animation_state.sprinting else profile.body_lean_degrees
	var locomotion_weight = animation_state.speed_ratio if animation_state.grounded else 0.0
	var weight_shift = cos(_gait_phase()) * locomotion_weight
	var target_rotation = Vector3(
		deg_to_rad(forward_ratio * lean_degrees) + _inertia_pitch,
		deg_to_rad(-weight_shift * profile.locomotion_twist_degrees),
		deg_to_rad(-side_ratio * profile.body_lean_degrees - turn_ratio * profile.turn_lean_degrees + weight_shift * profile.locomotion_sway_degrees)
	)
	_current_body_rotation = _current_body_rotation.lerp(target_rotation, response)
	rig_root.rotation = Vector3(_current_body_rotation.x, 0.0, 0.0)
	body_secondary.rotation = Vector3(0.0, _current_body_rotation.y, _current_body_rotation.z)
	body_secondary.scale = Vector3.ONE
	var bob_height = profile.sprint_bob_height if animation_state.sprinting else profile.walk_bob_height
	var passing_pose = smoothstep(0.0, 1.0, abs(sin(_gait_phase())))
	var walk_bob = passing_pose * bob_height * animation_state.speed_ratio
	var idle_bob = sin(_elapsed * TAU / profile.idle_cycle_seconds) * profile.idle_bob_height * (1.0 - animation_state.speed_ratio)
	var landing_wave = 0.0
	if _landing_strength > 0.0:
		var landing_recovery_seconds = max(profile.landing_seconds - profile.landing_hold_seconds, 0.001)
		var landing_progress = clamp((_landing_elapsed - profile.landing_hold_seconds) / landing_recovery_seconds, 0.0, 1.0)
		landing_wave = _landing_strength * exp(-3.0 * landing_progress) * cos(landing_progress * TAU)
	var anticipation = sin(animation_state.jump_anticipation * PI * 0.5)
	var takeoff_stretch = clamp(animation_state.local_velocity.y / 9.0, 0.0, 1.0) * profile.jump_stretch if not animation_state.grounded else 0.0
	var locomotion_pulse = animation_state.speed_ratio if animation_state.grounded else 0.0
	var gait_squash = (1.0 - passing_pose) * locomotion_pulse * (profile.sprint_voxel_squash if animation_state.sprinting else profile.walk_voxel_squash)
	var gait_stretch = passing_pose * locomotion_pulse * (profile.sprint_voxel_stretch if animation_state.sprinting else profile.walk_voxel_stretch)
	var gait_deformation = gait_stretch - gait_squash
	var landing_compression = max(landing_wave, 0.0) * profile.landing_squash
	var landing_rebound = max(-landing_wave, 0.0) * profile.landing_rebound_stretch
	var anticipation_compression = anticipation * profile.jump_anticipation_squash
	var vertical_stretch = takeoff_stretch + landing_rebound
	var aerial_deformation = vertical_stretch - landing_compression - anticipation_compression
	var width_expansion = max(landing_wave, 0.0) * profile.landing_widen + anticipation * profile.jump_anticipation_widen - gait_deformation * 0.55 - vertical_stretch * 0.45
	rig_root.position = _rig_root_origin + Vector3(0.0, walk_bob + idle_bob - max(landing_wave, 0.0) * 0.055 + landing_rebound * 0.4 - anticipation * profile.jump_anticipation_depth, 0.0)
	rig_root.scale = Vector3(
		1.0 + width_expansion,
		1.0 + gait_deformation + aerial_deformation,
		1.0 + width_expansion
	)
	var torso_deformation = gait_deformation * 0.30 + aerial_deformation * 0.35
	var head_deformation = gait_deformation * 0.14 + aerial_deformation * 0.18
	torso_base.scale = Vector3(1.0 - torso_deformation, 1.0 + torso_deformation, 1.0 - torso_deformation)
	head_secondary.scale = Vector3(1.0 - head_deformation, 1.0 + head_deformation, 1.0 - head_deformation)
	_update_limb_expression()
	_update_state_pose()

func _apply_tuning_transforms():
	_apply_tuning_transform(rig_root, rig_root, TUNING_RIG, _rig_root_origin, true)
	_apply_tuning_transform(body_secondary, body_secondary, TUNING_BODY, _body_secondary_origin, false)
	_apply_tuning_transform(head_secondary, head_secondary, TUNING_HEAD, _head_secondary_origin, false)
	_apply_tuning_transform(left_arm_action, left_arm_action, TUNING_LEFT_ARM, _left_arm_action_origin, false)
	_apply_tuning_transform(right_arm_action, right_arm_action, TUNING_RIGHT_ARM, _right_arm_action_origin, false)
	_apply_tuning_transform(left_leg_locomotion, left_leg_base, TUNING_LEFT_LEG, _left_leg_origin, true)
	_apply_tuning_transform(right_leg_locomotion, right_leg_base, TUNING_RIGHT_LEG, _right_leg_origin, true)

func _apply_tuning_transform(transform_node: Node3D, scale_node: Node3D, part: StringName, origin: Vector3, preserve_generated_position: bool):
	var generated_position = transform_node.position if preserve_generated_position else origin
	transform_node.position = generated_position + (_tuning_positions[part] as Vector3)
	var tuning_rotation = _tuning_rotations_degrees[part] as Vector3
	transform_node.rotation += Vector3(deg_to_rad(tuning_rotation.x), deg_to_rad(tuning_rotation.y), deg_to_rad(tuning_rotation.z))
	scale_node.scale *= _tuning_scales[part] as Vector3

func _update_limb_expression():
	var locomotion_weight = animation_state.speed_ratio if animation_state.grounded else 0.0
	var gait_phase = _gait_phase()
	var stride = cos(gait_phase)
	var stride_strength = abs(stride) * locomotion_weight
	var leg_travel = profile.sprint_leg_travel if animation_state.sprinting else profile.walk_leg_travel
	var leg_lift = profile.sprint_leg_lift if animation_state.sprinting else profile.walk_leg_lift
	var reach_degrees = profile.sprint_leg_reach_degrees if animation_state.sprinting else profile.walk_leg_reach_degrees
	var push_degrees = profile.sprint_leg_push_degrees if animation_state.sprinting else profile.walk_leg_push_degrees
	var compression = profile.sprint_leg_compression if animation_state.sprinting else profile.walk_leg_compression
	var stretch_distance = profile.sprint_limb_stretch if animation_state.sprinting else profile.walk_limb_stretch
	var gait_direction = Vector3(_gait_direction.x, 0.0, _gait_direction.y)
	var rig_inverse = rig_root.transform.affine_inverse()
	_update_leg_locomotion(left_leg_locomotion, left_leg_base, left_hip, left_foot_marker, _left_leg_origin, rig_inverse, gait_direction, gait_phase, leg_travel, leg_lift, reach_degrees, push_degrees, compression, stretch_distance, locomotion_weight)
	_update_leg_locomotion(right_leg_locomotion, right_leg_base, right_hip, right_foot_marker, _right_leg_origin, rig_inverse, gait_direction, gait_phase + PI, leg_travel, leg_lift, reach_degrees, push_degrees, compression, stretch_distance, locomotion_weight)
	var limb_stretch = 1.0 + stretch_distance * stride_strength
	left_arm_action.scale = Vector3(1.0, limb_stretch, 1.0)
	right_arm_action.scale = left_arm_action.scale

func _update_leg_locomotion(locomotion: Node3D, leg_base: Node3D, hip: Node3D, foot_marker: Marker3D, origin: Vector3, rig_inverse: Transform3D, gait_direction: Vector3, phase: float, travel: float, lift: float, reach_degrees: float, push_degrees: float, compression: float, stretch_distance: float, weight: float):
	var cycle = fposmod(phase / TAU, 1.0)
	var progress: float
	var forward_offset: float
	var vertical_offset = 0.0
	var rotation_degrees: float
	var leg_deformation: float
	var stance = cycle < profile.gait_push_pose
	if cycle < profile.gait_contact_hold:
		forward_offset = travel
		rotation_degrees = -reach_degrees
		leg_deformation = -compression
	elif cycle < profile.gait_down_pose:
		progress = _pose_ease((cycle - profile.gait_contact_hold) / (profile.gait_down_pose - profile.gait_contact_hold))
		forward_offset = lerp(travel, travel * 0.45, progress)
		rotation_degrees = lerp(-reach_degrees, -reach_degrees * 0.18, progress)
		leg_deformation = lerp(-compression, -stretch_distance * 0.35, progress)
	elif cycle < profile.gait_push_pose:
		progress = _pose_ease((cycle - profile.gait_down_pose) / (profile.gait_push_pose - profile.gait_down_pose))
		forward_offset = lerp(travel * 0.45, -travel, progress)
		rotation_degrees = lerp(-reach_degrees * 0.18, push_degrees, progress)
		leg_deformation = lerp(-stretch_distance * 0.35, stretch_distance, progress)
	elif cycle < profile.gait_passing_pose:
		progress = _pose_ease((cycle - profile.gait_push_pose) / (profile.gait_passing_pose - profile.gait_push_pose))
		forward_offset = lerp(-travel, 0.0, progress)
		vertical_offset = lerp(0.0, lift, progress)
		rotation_degrees = lerp(push_degrees, profile.leg_follow_through_degrees, progress)
		leg_deformation = lerp(stretch_distance, -compression, progress)
	else:
		progress = _pose_ease((cycle - profile.gait_passing_pose) / (1.0 - profile.gait_passing_pose))
		forward_offset = lerp(0.0, travel, progress)
		vertical_offset = lerp(lift, 0.0, progress)
		rotation_degrees = lerp(profile.leg_follow_through_degrees, -reach_degrees, progress)
		leg_deformation = lerp(-compression, -compression * 0.45, progress)
	var leg_stretch = leg_deformation * weight
	leg_base.scale = Vector3(1.0 - leg_stretch * 0.35, 1.0 + leg_stretch, 1.0 - leg_stretch * 0.35)
	var direction_strength = gait_direction.length()
	var rotation_axis = Vector3.UP.cross(gait_direction).normalized() if direction_strength > 0.0001 else Vector3.RIGHT
	var leg_rotation = deg_to_rad(rotation_degrees) * weight * direction_strength
	var leg_rotation_basis = Basis(Quaternion(rotation_axis, leg_rotation))
	locomotion.basis = leg_rotation_basis
	var foot_height = 0.0 if stance else vertical_offset
	var target_in_visual = Vector3(hip.position.x, foot_height, hip.position.z) + gait_direction * forward_offset
	var target_in_rig = rig_inverse * target_in_visual
	var target_from_hip = target_in_rig - hip.position
	if direction_strength > 0.0001:
		var planar_direction = gait_direction / direction_strength
		var planar_distance = Vector3(target_from_hip.x, 0.0, target_from_hip.z).dot(planar_direction)
		target_from_hip.x = planar_direction.x * planar_distance
		target_from_hip.z = planar_direction.z * planar_distance
	else:
		target_from_hip.x = 0.0
		target_from_hip.z = 0.0
	var foot_from_center = leg_rotation_basis * (foot_marker.position * leg_base.scale)
	var target_position = target_from_hip - foot_from_center
	locomotion.position = origin.lerp(target_position, weight)

func _update_state_pose():
	var torso_rotation = Vector3.ZERO
	var left_leg_rotation = 0.0
	var right_leg_rotation = 0.0
	match _current_state:
		IDLE:
			var idle_wave = sin(_elapsed * TAU / profile.idle_cycle_seconds)
			torso_rotation.x = deg_to_rad(profile.idle_torso_pitch_degrees * (0.5 + idle_wave * 0.5))
			torso_rotation.z = deg_to_rad(profile.idle_torso_sway_degrees * idle_wave)
		JUMP:
			torso_rotation.x = -deg_to_rad(profile.jump_torso_pitch_degrees)
			left_leg_rotation = -deg_to_rad(profile.jump_leg_split_degrees)
			right_leg_rotation = deg_to_rad(profile.jump_leg_split_degrees)
		FALL:
			torso_rotation.x = deg_to_rad(profile.fall_torso_pitch_degrees)
			left_leg_rotation = deg_to_rad(profile.fall_leg_split_degrees)
			right_leg_rotation = -deg_to_rad(profile.fall_leg_split_degrees)
		LAND:
			var landing_weight = _landing_pose_weight()
			torso_rotation.x = deg_to_rad(profile.landing_torso_pitch_degrees) * landing_weight
			left_leg_rotation = deg_to_rad(profile.landing_leg_pitch_degrees) * landing_weight
			right_leg_rotation = left_leg_rotation
	torso_base.rotation = torso_rotation
	left_leg_base.rotation = Vector3(left_leg_rotation, 0.0, 0.0)
	right_leg_base.rotation = Vector3(right_leg_rotation, 0.0, 0.0)

func _pose_ease(value: float) -> float:
	var clamped_value = clamp(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - clamped_value, 3.0)

func _gait_phase() -> float:
	return _shaped_gait_phase

func _landing_pose_weight() -> float:
	if _current_state != LAND:
		return 0.0
	return _landing_strength * (1.0 - clamp(_landing_elapsed / max(profile.landing_seconds, 0.001), 0.0, 1.0))

func _update_head(delta: float):
	var look_direction = animation_state.local_look_direction
	if not animation_state.has_look_target:
		look_direction = Vector3(animation_state.local_velocity.x, 0.0, animation_state.local_velocity.z)
		if look_direction.length_squared() < 0.001:
			look_direction = Vector3(0.0, 0.0, 1.0)
	var flat_length = Vector2(look_direction.x, look_direction.z).length()
	var target_yaw = clamp(
		atan2(look_direction.x, look_direction.z),
		-deg_to_rad(profile.head_yaw_limit_degrees),
		deg_to_rad(profile.head_yaw_limit_degrees)
	)
	var target_pitch = clamp(
		-atan2(look_direction.y, max(flat_length, 0.001)),
		-deg_to_rad(profile.head_up_limit_degrees),
		deg_to_rad(profile.head_down_limit_degrees)
	)
	if not animation_state.has_look_target and animation_state.speed_ratio < 0.05:
		target_yaw += sin(_elapsed * 0.73) * deg_to_rad(profile.idle_head_degrees)
		target_pitch += sin(_elapsed * 0.51 + 1.2) * deg_to_rad(profile.idle_head_degrees * 0.45)
	elif animation_state.grounded:
		var gait_phase = _gait_phase()
		target_yaw -= _current_body_rotation.y * 0.45
		target_pitch += sin(gait_phase * 2.0 - 0.35) * deg_to_rad(1.25) * animation_state.speed_ratio
	var response = 1.0 - exp(-profile.head_response * delta)
	_current_head_rotation.x = lerp_angle(_current_head_rotation.x, target_pitch, response)
	_current_head_rotation.y = lerp_angle(_current_head_rotation.y, target_yaw, response)
	_current_head_rotation.z = lerp_angle(_current_head_rotation.z, -_current_body_rotation.z * 0.35, response)
	head_secondary.rotation = _current_head_rotation

func _update_actions(delta: float):
	var response = 1.0 - exp(-profile.motion_response * delta)
	attack_pose_weight = 0.0
	held_item_windup_pose_weight = 0.0
	held_item_pose_weight = 0.0
	held_item_alignment_weight = 0.0
	held_item_face_turn_weight = 0.0
	held_item_recovery_progress = 0.0
	if animation_state.sprinting:
		_placing = false
	var attack_active := _attacking
	var attack_progress := 0.0
	if attack_active:
		_attack_elapsed += delta
		attack_progress = clamp(_attack_elapsed / _attack_duration, 0.0, 1.0)
	_mine_blend = lerp(_mine_blend, 1.0 if _mining_active and not _placing and not attack_active and not animation_state.sprinting else 0.0, response)
	if _mining_active:
		_mine_phase = fmod(_mine_phase + delta / profile.mine_cycle_seconds, 1.0)
	var right_rotation = Vector3.ZERO
	var left_rotation = Vector3.ZERO
	var body_rotation = Vector3.ZERO
	body_action.position = _body_action_origin
	left_arm_base.rotation = Vector3.ZERO
	right_arm_base.rotation = Vector3.ZERO
	match _current_state:
		IDLE:
			var idle_arm_wave = sin(_elapsed * TAU / profile.idle_cycle_seconds)
			left_rotation.x = deg_to_rad(profile.idle_arm_swing_degrees * idle_arm_wave)
			right_rotation.x = -left_rotation.x
		JUMP:
			left_rotation = Vector3(deg_to_rad(profile.jump_arm_pitch_degrees), 0.0, -deg_to_rad(profile.jump_arm_spread_degrees))
			right_rotation = Vector3(deg_to_rad(profile.jump_arm_pitch_degrees), 0.0, deg_to_rad(profile.jump_arm_spread_degrees))
		FALL:
			left_rotation = Vector3(deg_to_rad(profile.fall_arm_pitch_degrees), 0.0, -deg_to_rad(profile.fall_arm_spread_degrees))
			right_rotation = Vector3(deg_to_rad(profile.fall_arm_pitch_degrees), 0.0, deg_to_rad(profile.fall_arm_spread_degrees))
		LAND:
			var landing_arm_pitch = deg_to_rad(profile.landing_arm_pitch_degrees) * _landing_pose_weight()
			left_rotation.x = landing_arm_pitch
			right_rotation.x = landing_arm_pitch
	if _mine_blend > 0.001 and not attack_active:
		var mine_degrees = _mine_swing_degrees(_mine_phase)
		right_rotation.x = deg_to_rad(mine_degrees) * _mine_blend
		left_rotation.x = deg_to_rad(-12.0 * clamp(-mine_degrees / 120.0, 0.0, 1.0)) * _mine_blend
		body_rotation.y = deg_to_rad(-6.0 * clamp(-mine_degrees / 120.0, 0.0, 1.0)) * _mine_blend
	if _placing and not attack_active and not animation_state.sprinting:
		_place_elapsed += delta
		var place_progress = clamp(_place_elapsed / profile.place_seconds, 0.0, 1.0)
		var place_degrees = _place_swing_degrees(place_progress)
		var place_weight = clamp(-place_degrees / 75.0, 0.0, 1.0)
		right_rotation.x = deg_to_rad(place_degrees)
		right_rotation.z = deg_to_rad(-8.0 * place_weight)
		body_rotation.y = deg_to_rad(-8.0 * place_weight)
		if _place_elapsed >= profile.place_seconds:
			_placing = false
	if attack_active:
		attack_pose_weight = sin(attack_progress * PI)
		if _attack_animation_style == MeleeAttackActionDefinition.AnimationStyle.OVERHEAD_SLAM:
			var arm_pitch := deg_to_rad(_overhead_slam_arm_pitch_degrees(attack_progress))
			var inward_angle := deg_to_rad(_overhead_slam_inward_angle_degrees(attack_progress))
			left_rotation = Vector3(arm_pitch, 0.0, inward_angle)
			right_rotation = Vector3(arm_pitch, 0.0, -inward_angle)
			if attack_progress >= HAMMER_HOLD_END:
				var recovery_progress := (attack_progress - HAMMER_HOLD_END) / (1.0 - HAMMER_HOLD_END)
				var left_idle := _held_melee_action.two_handed_left_arm_rotation_degrees
				var right_idle := _held_melee_action.two_handed_right_arm_rotation_degrees
				left_rotation = Vector3(
					deg_to_rad(lerp(-26.0, left_idle.x, recovery_progress)),
					deg_to_rad(lerp(0.0, left_idle.y, recovery_progress)),
					deg_to_rad(lerp(30.0, left_idle.z, recovery_progress))
				)
				right_rotation = Vector3(
					deg_to_rad(lerp(-26.0, right_idle.x, recovery_progress)),
					deg_to_rad(lerp(0.0, right_idle.y, recovery_progress)),
					deg_to_rad(lerp(-30.0, right_idle.z, recovery_progress))
				)
			held_item_windup_pose_weight = _overhead_slam_windup_weight(attack_progress)
			held_item_alignment_weight = _overhead_slam_alignment_weight(attack_progress)
			held_item_face_turn_weight = _overhead_slam_face_turn_weight(attack_progress)
			if attack_progress >= HAMMER_HOLD_END:
				held_item_recovery_progress = (attack_progress - HAMMER_HOLD_END) / (1.0 - HAMMER_HOLD_END)
			var impact_weight := _overhead_slam_impact_weight(attack_progress)
			held_item_pose_weight = impact_weight
			body_rotation.x = deg_to_rad(24.0) * impact_weight
			body_action.position.y -= HAMMER_BODY_DROP * impact_weight
			left_leg_base.rotation.x -= deg_to_rad(12.0) * impact_weight
			right_leg_base.rotation.x += deg_to_rad(12.0) * impact_weight
			rig_root.position.y -= 0.14 * impact_weight
		else:
			held_item_pose_weight = attack_pose_weight
			var sweep_degrees := _attack_sweep_degrees(attack_progress) * float(_attack_direction)
			right_rotation = Vector3(
				deg_to_rad(profile.attack_right_arm_pitch_degrees * attack_pose_weight),
				0.0,
				deg_to_rad(sweep_degrees)
			)
			body_rotation.x = deg_to_rad(profile.attack_body_lean_degrees * attack_pose_weight)
			body_rotation.y = deg_to_rad(profile.attack_body_twist_degrees * sweep_degrees / profile.attack_follow_through_degrees)
			left_leg_base.rotation.x -= deg_to_rad(profile.attack_leg_brace_degrees * attack_pose_weight * _attack_direction)
			right_leg_base.rotation.x += deg_to_rad(profile.attack_leg_brace_degrees * attack_pose_weight * _attack_direction)
			rig_root.position.y -= profile.attack_crouch_depth * attack_pose_weight
		if _attack_elapsed >= _attack_duration:
			_attacking = false
	if _uses_two_handed_pose() and not attack_active and _mine_blend <= 0.001 and not _placing:
		var hold_wave := sin(_elapsed * 4.0) * 1.5
		var left_hold := _held_melee_action.two_handed_left_arm_rotation_degrees
		var right_hold := _held_melee_action.two_handed_right_arm_rotation_degrees
		left_hold.x += hold_wave
		right_hold.x += hold_wave
		left_rotation = Vector3(deg_to_rad(left_hold.x), deg_to_rad(left_hold.y), deg_to_rad(left_hold.z))
		right_rotation = Vector3(deg_to_rad(right_hold.x), deg_to_rad(right_hold.y), deg_to_rad(right_hold.z))
	elif animation_state.grounded and animation_state.speed_ratio > 0.05 and _mine_blend <= 0.001 and not _placing and not attack_active:
		var swing_degrees = profile.sprint_arm_swing_degrees if animation_state.sprinting else profile.walk_arm_swing_degrees
		var arm_wave = _held_wave(_gait_phase() - profile.secondary_motion_lag) * animation_state.speed_ratio
		var left_target = deg_to_rad(swing_degrees * arm_wave)
		var right_target = -left_target
		left_rotation = Vector3(left_target, 0.0, deg_to_rad(-3.0 * animation_state.speed_ratio))
		right_rotation = Vector3(right_target, 0.0, deg_to_rad(3.0 * animation_state.speed_ratio))
	left_arm_action.rotation = left_rotation
	right_arm_action.rotation = right_rotation
	body_action.rotation = body_rotation

func _held_wave(phase: float) -> float:
	var wave = cos(phase)
	return sign(wave) * pow(abs(wave), 0.42)

func _mine_swing_degrees(progress: float) -> float:
	if progress < 0.18:
		return lerp(0.0, 28.0, _pose_ease(progress / 0.18))
	if progress < 0.42:
		return lerp(28.0, -120.0, _pose_ease((progress - 0.18) / 0.24))
	if progress < 0.58:
		return -120.0
	return lerp(-120.0, 0.0, _pose_ease((progress - 0.58) / 0.42))

func _place_swing_degrees(progress: float) -> float:
	if progress < 0.18:
		return lerp(0.0, 18.0, _pose_ease(progress / 0.18))
	if progress < 0.42:
		return lerp(18.0, -75.0, _pose_ease((progress - 0.18) / 0.24))
	if progress < 0.62:
		return -75.0
	return lerp(-75.0, 0.0, _pose_ease((progress - 0.62) / 0.38))

func _attack_sweep_degrees(progress: float) -> float:
	if progress < MeleeAttackActionDefinition.SWEEP_WINDUP_END:
		return lerp(0.0, -profile.attack_windup_degrees, _pose_ease(progress / MeleeAttackActionDefinition.SWEEP_WINDUP_END))
	if progress < _attack_contact_progress:
		var strike_progress := (progress - MeleeAttackActionDefinition.SWEEP_WINDUP_END) / (_attack_contact_progress - MeleeAttackActionDefinition.SWEEP_WINDUP_END)
		return lerp(-profile.attack_windup_degrees, profile.attack_follow_through_degrees, _pose_ease(strike_progress))
	if progress < MeleeAttackActionDefinition.SWEEP_RECOVERY_START:
		return profile.attack_follow_through_degrees
	var recovery_progress := (progress - MeleeAttackActionDefinition.SWEEP_RECOVERY_START) / (1.0 - MeleeAttackActionDefinition.SWEEP_RECOVERY_START)
	return lerp(profile.attack_follow_through_degrees, 0.0, _pose_ease(recovery_progress))

func _overhead_slam_arm_pitch_degrees(progress: float) -> float:
	if progress < HAMMER_WINDUP_END:
		return lerp(-52.0, -162.0, smoothstep(0.0, 1.0, progress / HAMMER_WINDUP_END))
	if progress < HAMMER_IMPACT:
		return lerp(-162.0, -26.0, smoothstep(0.0, 1.0, (progress - HAMMER_WINDUP_END) / (HAMMER_IMPACT - HAMMER_WINDUP_END)))
	if progress < HAMMER_HOLD_END:
		return -26.0
	return -26.0

func _overhead_slam_inward_angle_degrees(progress: float) -> float:
	if progress < HAMMER_WINDUP_END:
		return lerp(3.0, 30.0, smoothstep(0.0, 1.0, progress / HAMMER_WINDUP_END))
	return 30.0

func _overhead_slam_windup_weight(progress: float) -> float:
	if progress < HAMMER_WINDUP_END:
		return smoothstep(0.0, 1.0, progress / HAMMER_WINDUP_END)
	if progress < HAMMER_IMPACT:
		return 1.0 - smoothstep(0.0, 1.0, (progress - HAMMER_WINDUP_END) / (HAMMER_IMPACT - HAMMER_WINDUP_END))
	return 0.0

func _overhead_slam_impact_weight(progress: float) -> float:
	if progress < HAMMER_WINDUP_END:
		return 0.0
	if progress < HAMMER_IMPACT:
		return smoothstep(0.0, 1.0, (progress - HAMMER_WINDUP_END) / (HAMMER_IMPACT - HAMMER_WINDUP_END))
	if progress < HAMMER_HOLD_END:
		return 1.0
	return 1.0 - (progress - HAMMER_HOLD_END) / (1.0 - HAMMER_HOLD_END)

func _overhead_slam_alignment_weight(progress: float) -> float:
	if progress < HAMMER_WINDUP_END:
		return smoothstep(0.0, 1.0, progress / HAMMER_WINDUP_END)
	if progress < HAMMER_HOLD_END or is_equal_approx(progress, HAMMER_HOLD_END):
		return 1.0
	return 0.0

func _overhead_slam_face_turn_weight(progress: float) -> float:
	if progress < HAMMER_WINDUP_END:
		return 0.0
	if progress < HAMMER_IMPACT:
		return smoothstep(0.0, 1.0, (progress - HAMMER_WINDUP_END) / (HAMMER_IMPACT - HAMMER_WINDUP_END))
	return 1.0

func _uses_two_handed_pose() -> bool:
	return _held_melee_action != null and _held_melee_action.two_handed_pose
