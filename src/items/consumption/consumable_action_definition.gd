extends ItemActionDefinition
class_name ConsumableActionDefinition

@export_range(0.0, 1.0, 0.01) var health_restore_fraction: float
@export var can_consume_at_full_health: bool = false
@export var output_item_id: StringName
@export_range(0, 99) var output_count: int

func validate(source: String) -> bool:
	var valid := true
	if not is_finite(health_restore_fraction) or health_restore_fraction <= 0.0 or health_restore_fraction > 1.0:
		push_error("[ConsumableActionDefinition] Invalid health restore fraction at %s" % source)
		valid = false
	if output_item_id.is_empty() and output_count != 0:
		push_error("[ConsumableActionDefinition] Output count requires an output item ID at %s" % source)
		valid = false
	elif not output_item_id.is_empty() and output_count < 1:
		push_error("[ConsumableActionDefinition] Invalid output count at %s" % source)
		valid = false
	return valid
