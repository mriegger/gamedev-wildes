extends Resource
class_name MeleeAttackProfile

@export var id: StringName
@export_range(0.01, 10.0, 0.01, "or_greater") var duration: float = 0.48
@export_range(0.0, 10.0, 0.01, "or_greater") var contact_time: float = 0.24
@export_range(0.0, 10.0, 0.01, "or_greater") var cooldown: float = 0.48
@export_range(0.01, 32.0, 0.01, "or_greater") var reach: float = 2.5
@export_range(0.01, 999999.0, 0.01, "or_greater") var base_damage: float = 1.0
@export_range(0.0, 360.0, 0.1) var sweep_degrees: float = 0.0

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
	if not is_finite(base_damage) or base_damage <= 0.0:
		push_error("[MeleeAttackProfile] Invalid base damage at %s" % source)
		valid = false
	if not is_valid_sweep_degrees(sweep_degrees):
		push_error("[MeleeAttackProfile] Invalid sweep at %s" % source)
		valid = false
	return valid

static func is_valid_sweep_degrees(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 360.0

func calculate_damage(attacker_strength: float, target_defense: float) -> float:
	assert(is_finite(attacker_strength) and attacker_strength >= 0.0)
	assert(is_finite(target_defense) and target_defense >= 0.0)
	return maxf(1.0, base_damage + attacker_strength - target_defense)
