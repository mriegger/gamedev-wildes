extends ItemDefinition
class_name ArrowItemDefinition

@export var projectile_profile: ProjectileAttackProfile

func validate(source: String) -> bool:
	if held_scene == null or projectile_profile == null or not projectile_profile.validate(source):
		push_error("[ArrowItemDefinition] Invalid projectile content at %s" % source)
		return false
	var arrow_view := held_scene.instantiate()
	if not arrow_view is NockableArrowView:
		if arrow_view != null:
			arrow_view.free()
		push_error("[ArrowItemDefinition] Held scene must instantiate NockableArrowView at %s" % source)
		return false
	arrow_view.free()
	return true
