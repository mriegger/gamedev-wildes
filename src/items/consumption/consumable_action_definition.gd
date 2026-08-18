extends ItemActionDefinition
class_name ConsumableActionDefinition

@export_range(0.0, 1.0, 0.01) var health_restore_fraction: float

func validate(source: String) -> bool:
	if not is_finite(health_restore_fraction) or health_restore_fraction <= 0.0 or health_restore_fraction > 1.0:
		push_error("[ConsumableActionDefinition] Invalid health restore fraction at %s" % source)
		return false
	return true
