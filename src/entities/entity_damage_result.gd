extends RefCounted
class_name EntityDamageResult

var applied_damage: float:
	get:
		return _applied_damage
var defeated: bool:
	get:
		return _defeated

var _applied_damage: float
var _defeated: bool

func _init(p_applied_damage: float, p_defeated: bool):
	assert(is_finite(p_applied_damage) and p_applied_damage > 0.0)
	_applied_damage = p_applied_damage
	_defeated = p_defeated
