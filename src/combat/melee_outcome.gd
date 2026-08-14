extends RefCounted
class_name MeleeOutcome

var contact: MeleeContact:
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

var _contact: MeleeContact
var _source_item_id: StringName
var _applied_damage: float
var _target_defeated: bool

func _init(
	p_contact: MeleeContact,
	p_source_item_id: StringName,
	p_applied_damage: float,
	p_target_defeated: bool,
):
	assert(p_contact != null)
	assert(is_finite(p_applied_damage) and p_applied_damage > 0.0)
	_contact = p_contact
	_source_item_id = p_source_item_id
	_applied_damage = p_applied_damage
	_target_defeated = p_target_defeated
