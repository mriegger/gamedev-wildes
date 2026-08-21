extends Resource
class_name ProjectileAttackProfile

@export var damage_type: DamageTypeDefinition
@export_range(0.01, 999999.0, 0.01, "or_greater") var base_damage: float = 1.0
@export_range(1.0, 10.0, 0.01, "or_greater") var sneak_damage_multiplier: float = 1.0
@export_range(0.0, 32.0, 0.01, "or_greater") var knockback_speed: float = 0.0
@export_range(0.001, 1.0, 0.001) var collision_radius: float = 0.05
@export_range(0.01, 200.0, 0.01, "or_greater") var gravity: float = 78.4
@export_range(0.1, 60.0, 0.1, "or_greater") var maximum_flight_seconds: float = 12.0
@export_range(0.0, 10.0, 0.01, "or_greater") var embedded_seconds: float = 1.0
@export_range(0.01, 10.0, 0.01, "or_greater") var fade_seconds: float = 0.35

func validate(source: String) -> bool:
	var valid := true
	if damage_type == null or not damage_type.validate(source):
		push_error("[ProjectileAttackProfile] Invalid damage type at %s" % source)
		valid = false
	if not is_finite(base_damage) or base_damage <= 0.0:
		push_error("[ProjectileAttackProfile] Invalid base damage at %s" % source)
		valid = false
	if not is_finite(sneak_damage_multiplier) or sneak_damage_multiplier < 1.0:
		push_error("[ProjectileAttackProfile] Invalid sneak damage multiplier at %s" % source)
		valid = false
	if not is_finite(knockback_speed) or knockback_speed < 0.0:
		push_error("[ProjectileAttackProfile] Invalid knockback speed at %s" % source)
		valid = false
	if not is_finite(collision_radius) or collision_radius <= 0.0:
		push_error("[ProjectileAttackProfile] Invalid collision radius at %s" % source)
		valid = false
	if not is_finite(gravity) or gravity <= 0.0:
		push_error("[ProjectileAttackProfile] Invalid gravity at %s" % source)
		valid = false
	if not is_finite(maximum_flight_seconds) or maximum_flight_seconds <= 0.0:
		push_error("[ProjectileAttackProfile] Invalid maximum flight duration at %s" % source)
		valid = false
	if not is_finite(embedded_seconds) or embedded_seconds < 0.0:
		push_error("[ProjectileAttackProfile] Invalid embedded duration at %s" % source)
		valid = false
	if not is_finite(fade_seconds) or fade_seconds <= 0.0:
		push_error("[ProjectileAttackProfile] Invalid fade duration at %s" % source)
		valid = false
	return valid

func calculate_damage(attacker_strength: float, target_defense: float) -> float:
	assert(is_finite(attacker_strength) and attacker_strength >= 0.0)
	assert(is_finite(target_defense) and target_defense >= 0.0)
	return maxf(1.0, base_damage + attacker_strength - target_defense)
