extends RefCounted
class_name TutorialCalloutArbiter

var _owner: Object
var _owner_dismissal: Callable
var _priority_owner: Object

func try_acquire(owner: Object, dismissal: Callable = Callable()) -> bool:
	assert(owner != null)
	_cleanup_invalid_owners()
	if _priority_owner != null and _priority_owner != owner:
		return false
	if _owner != null and _owner != owner:
		return false
	_owner = owner
	_owner_dismissal = dismissal
	if _priority_owner == owner:
		_priority_owner = null
	return true

func request_priority(owner: Object, dismissal: Callable = Callable()) -> bool:
	assert(owner != null)
	_cleanup_invalid_owners()
	_priority_owner = owner
	if _owner == null or _owner == owner:
		return try_acquire(owner, dismissal)
	if _owner_dismissal.is_valid():
		_owner_dismissal.call()
	return false

func release(owner: Object) -> void:
	if _owner == owner:
		_owner = null
		_owner_dismissal = Callable()

func cancel_priority(owner: Object) -> void:
	if _priority_owner == owner:
		_priority_owner = null

func is_available(owner: Object) -> bool:
	_cleanup_invalid_owners()
	if _priority_owner != null and _priority_owner != owner:
		return false
	return _owner == null or _owner == owner

func _cleanup_invalid_owners() -> void:
	if _owner != null and not is_instance_valid(_owner):
		_owner = null
		_owner_dismissal = Callable()
	if _priority_owner != null and not is_instance_valid(_priority_owner):
		_priority_owner = null
