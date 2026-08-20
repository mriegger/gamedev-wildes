extends RefCounted
class_name ProjectileOutcome

var contact: ProjectileContact:
	get:
		return _contact
var source_item_id: StringName:
	get:
		return _source_item_id
var applied_damage: float:
	get:
		return _applied_damage
var target_defeated: bool:
	get:
		return _target_defeated
var damage_response: int:
	get:
		return _damage_response

var _contact: ProjectileContact
var _source_item_id: StringName
var _applied_damage: float
var _target_defeated: bool
var _damage_response: int

func _init(
	p_contact: ProjectileContact,
	p_source_item_id: StringName,
	p_applied_damage: float,
	p_target_defeated: bool,
	p_damage_response: int,
) -> void:
	assert(p_contact != null)
	assert(not p_source_item_id.is_empty())
	assert(is_finite(p_applied_damage) and p_applied_damage > 0.0)
	assert(DamageAffinityDefinition.is_valid_response(p_damage_response))
	_contact = p_contact
	_source_item_id = p_source_item_id
	_applied_damage = p_applied_damage
	_target_defeated = p_target_defeated
	_damage_response = p_damage_response
