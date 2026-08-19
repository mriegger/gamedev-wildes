extends Resource
class_name MeleeAttackProfile

@export var id: StringName
@export_range(0.01, 10.0, 0.01, "or_greater") var duration: float = 0.48
@export_range(0.0, 10.0, 0.01, "or_greater") var contact_time: float = 0.24
@export_range(0.0, 10.0, 0.01, "or_greater") var cooldown: float = 0.48
@export_range(0.01, 32.0, 0.01, "or_greater") var reach: float = 2.5
@export_range(0.01, 999999.0, 0.01, "or_greater") var base_damage: float = 1.0
@export_range(0.01, 10.0, 0.01, "or_greater") var damage_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01, "or_greater") var radial_damage_center_multiplier: float = 1.0
@export_range(0.01, 10.0, 0.01, "or_greater") var radial_damage_edge_multiplier: float = 1.0
@export_range(0.0, 360.0, 0.1) var sweep_degrees: float = 0.0
@export_range(0.0, 32.0, 0.01, "or_greater") var knockback_speed: float = 0.0
@export_range(0.0, 8.0, 0.01, "or_greater") var impact_origin_forward_offset: float = 0.0
@export var acquire_targets_on_contact: bool = false

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
	if not is_finite(damage_multiplier) or damage_multiplier <= 0.0:
		push_error("[MeleeAttackProfile] Invalid damage multiplier at %s" % source)
		valid = false
	if not is_finite(radial_damage_center_multiplier) or radial_damage_center_multiplier <= 0.0:
		push_error("[MeleeAttackProfile] Invalid radial center damage multiplier at %s" % source)
		valid = false
	if not is_finite(radial_damage_edge_multiplier) or radial_damage_edge_multiplier <= 0.0:
		push_error("[MeleeAttackProfile] Invalid radial edge damage multiplier at %s" % source)
		valid = false
	if not is_valid_sweep_degrees(sweep_degrees):
		push_error("[MeleeAttackProfile] Invalid sweep at %s" % source)
		valid = false
	if not is_finite(knockback_speed) or knockback_speed < 0.0:
		push_error("[MeleeAttackProfile] Invalid knockback speed at %s" % source)
		valid = false
	if not is_finite(impact_origin_forward_offset) or impact_origin_forward_offset < 0.0:
		push_error("[MeleeAttackProfile] Invalid impact origin offset at %s" % source)
		valid = false
	return valid

static func is_valid_sweep_degrees(value: float) -> bool:
	return is_finite(value) and value >= 0.0 and value <= 360.0

func requires_planar_aim() -> bool:
	return sweep_degrees > 0.0 and sweep_degrees < 360.0

func calculate_damage(attacker_strength: float, target_defense: float) -> float:
	assert(is_finite(attacker_strength) and attacker_strength >= 0.0)
	assert(is_finite(target_defense) and target_defense >= 0.0)
	return maxf(1.0, (base_damage + attacker_strength - target_defense) * damage_multiplier)

func calculate_damage_at_distance(attacker_strength: float, target_defense: float, distance_from_center: float) -> float:
	assert(is_finite(distance_from_center) and distance_from_center >= 0.0)
	var distance_ratio := clampf(distance_from_center / reach, 0.0, 1.0)
	var radial_multiplier := lerpf(radial_damage_center_multiplier, radial_damage_edge_multiplier, distance_ratio)
	return maxf(1.0, calculate_damage(attacker_strength, target_defense) * radial_multiplier)
