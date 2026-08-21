extends RefCounted
class_name TutorialCalloutArbiter

var _owner: Object

func try_acquire(owner: Object) -> bool:
	assert(owner != null)
	if _owner != null and not is_instance_valid(_owner):
		_owner = null
	if _owner != null and _owner != owner:
		return false
	_owner = owner
	return true

func release(owner: Object) -> void:
	if _owner == owner:
		_owner = null
