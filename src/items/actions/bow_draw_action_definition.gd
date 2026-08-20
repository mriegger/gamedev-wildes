extends ItemActionDefinition
class_name BowDrawActionDefinition

@export_range(0.05, 1.0, 0.01) var raise_seconds: float = 0.18
@export_range(0.1, 10.0, 0.1) var draw_seconds: float = 1.5
@export_range(0.1, 1.0, 0.01) var full_draw_distance: float = 0.48
@export var nocked_arrow_scene: PackedScene

func validate(source: String) -> bool:
	if not is_finite(raise_seconds) or raise_seconds <= 0.0:
		push_error("[BowDrawActionDefinition] Invalid raise duration at %s" % source)
		return false
	if not is_finite(draw_seconds) or draw_seconds <= 0.0:
		push_error("[BowDrawActionDefinition] Invalid draw duration at %s" % source)
		return false
	if not is_finite(full_draw_distance) or full_draw_distance <= 0.0 or full_draw_distance > 1.0:
		push_error("[BowDrawActionDefinition] Invalid full-draw distance at %s" % source)
		return false
	if nocked_arrow_scene == null:
		push_error("[BowDrawActionDefinition] Missing nocked arrow scene at %s" % source)
		return false
	var arrow_view := nocked_arrow_scene.instantiate()
	if arrow_view == null:
		push_error("[BowDrawActionDefinition] Nocked arrow scene cannot instantiate at %s" % source)
		return false
	if not arrow_view is NockableArrowView:
		arrow_view.free()
		push_error("[BowDrawActionDefinition] Nocked arrow must use NockableArrowView at %s" % source)
		return false
	var nockable_arrow := arrow_view as NockableArrowView
	var valid_nock := nockable_arrow.nock_local_position.is_finite()
	nockable_arrow.free()
	if not valid_nock:
		push_error("[BowDrawActionDefinition] Invalid nock position at %s" % source)
		return false
	return true
