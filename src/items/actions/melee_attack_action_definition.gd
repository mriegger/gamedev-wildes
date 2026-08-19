extends ItemActionDefinition
class_name MeleeAttackActionDefinition

enum AnimationStyle {
	SWEEP,
	OVERHEAD_SLAM,
}

@export var attack_profile: MeleeAttackProfile
@export_range(0.05, 1.0, 0.01) var chain_input_window: float = 0.26
@export var animation_style: AnimationStyle = AnimationStyle.SWEEP
@export var two_handed_pose: bool = false
@export var two_handed_left_arm_rotation_degrees: Vector3 = Vector3(-58.0, 0.0, 12.0)
@export var two_handed_right_arm_rotation_degrees: Vector3 = Vector3(-58.0, 0.0, -12.0)
@export var held_rest_position_offset: Vector3
@export var held_rest_rotation_degrees: Vector3
@export var held_windup_rotation_degrees: Vector3
@export var held_position_offset: Vector3
@export var held_rotation_degrees: Vector3
@export var compensate_attack_arm_pitch: bool = true
@export var align_overhead_striking_face: bool = false
@export_range(0.0, 32.0, 0.01, "or_greater") var impact_effect_radius: float = 0.0

func validate(source: String) -> bool:
	if attack_profile == null or not attack_profile.validate(source):
		push_error("[MeleeAttackActionDefinition] Invalid attack profile at %s" % source)
		return false
	if chain_input_window <= 0.0 or chain_input_window > attack_profile.duration:
		push_error("[MeleeAttackActionDefinition] Invalid chain input window at %s" % source)
		return false
	if animation_style < AnimationStyle.SWEEP or animation_style > AnimationStyle.OVERHEAD_SLAM:
		push_error("[MeleeAttackActionDefinition] Invalid animation style at %s" % source)
		return false
	if (
		not two_handed_left_arm_rotation_degrees.is_finite()
		or not two_handed_right_arm_rotation_degrees.is_finite()
		or not held_rest_position_offset.is_finite()
		or not held_rest_rotation_degrees.is_finite()
		or not held_windup_rotation_degrees.is_finite()
		or not held_position_offset.is_finite()
		or not held_rotation_degrees.is_finite()
	):
		push_error("[MeleeAttackActionDefinition] Invalid held-item attack transform at %s" % source)
		return false
	if not is_finite(impact_effect_radius) or impact_effect_radius < 0.0:
		push_error("[MeleeAttackActionDefinition] Invalid impact effect radius at %s" % source)
		return false
	return true
