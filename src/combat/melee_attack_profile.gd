extends Resource
class_name MeleeAttackProfile

@export var id: StringName
@export_range(0.01, 10.0, 0.01, "or_greater") var duration: float = 0.48
@export_range(0.0, 10.0, 0.01, "or_greater") var contact_time: float = 0.24
@export_range(0.0, 10.0, 0.01, "or_greater") var cooldown: float = 0.48
@export_range(0.01, 32.0, 0.01, "or_greater") var reach: float = 2.5

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[MeleeAttackProfile] Empty ID at %s" % source)
		valid = false
	if not is_finite(duration) or duration <= 0.0:
		push_error("[MeleeAttackProfile] Invalid duration at %s" % source)
		valid = false
	if not is_finite(contact_time) or contact_time < 0.0 or contact_time > duration:
		push_error("[MeleeAttackProfile] Invalid contact time at %s" % source)
		valid = false
	if not is_finite(cooldown) or cooldown < duration:
		push_error("[MeleeAttackProfile] Invalid cooldown at %s" % source)
		valid = false
	if not is_finite(reach) or reach <= 0.0:
		push_error("[MeleeAttackProfile] Invalid reach at %s" % source)
		valid = false
	return valid
