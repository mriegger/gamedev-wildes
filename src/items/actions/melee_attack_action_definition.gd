extends ItemActionDefinition
class_name MeleeAttackActionDefinition

@export_range(0.05, 4.0, 0.01) var attack_duration: float = 0.48
@export_range(0.05, 1.0, 0.01) var chain_input_window: float = 0.26
@export var held_position_offset: Vector3
@export var held_rotation_degrees: Vector3

func validate(source: String) -> bool:
	if attack_duration <= 0.0:
		push_error("[MeleeAttackActionDefinition] Invalid attack duration at %s" % source)
		return false
	if chain_input_window <= 0.0 or chain_input_window > attack_duration:
		push_error("[MeleeAttackActionDefinition] Invalid chain input window at %s" % source)
		return false
	if not held_position_offset.is_finite() or not held_rotation_degrees.is_finite():
		push_error("[MeleeAttackActionDefinition] Invalid held-item attack transform at %s" % source)
		return false
	return true
