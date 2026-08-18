extends RefCounted
class_name TimedMeleeContact

var _profile: MeleeAttackProfile
var _elapsed: float = 0.0
var _pending: bool = false

func arm(profile: MeleeAttackProfile) -> MeleeAttackProfile:
	assert(profile != null)
	_profile = profile
	_elapsed = 0.0
	_pending = true
	if is_zero_approx(profile.contact_time):
		return _consume()
	return null

func advance(delta: float) -> MeleeAttackProfile:
	assert(is_finite(delta) and delta >= 0.0)
	if not _pending:
		return null
	var previous_elapsed := _elapsed
	_elapsed = minf(_elapsed + delta, _profile.duration)
	if previous_elapsed < _profile.contact_time and _elapsed >= _profile.contact_time:
		return _consume()
	return null

func cancel() -> void:
	_profile = null
	_elapsed = 0.0
	_pending = false

func is_pending() -> bool:
	return _pending

func _consume() -> MeleeAttackProfile:
	var profile := _profile
	cancel()
	return profile
