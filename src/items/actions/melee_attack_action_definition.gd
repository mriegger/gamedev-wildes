extends ItemActionDefinition
class_name MeleeAttackActionDefinition

@export_range(0.05, 4.0, 0.01) var attack_duration: float = 0.48

func validate(source: String) -> bool:
	if attack_duration <= 0.0:
		push_error("[MeleeAttackActionDefinition] Invalid attack duration at %s" % source)
		return false
	return true
