extends SceneTree

const TimedMeleeContactType := preload("res://combat/timed_melee_contact.gd")

var _failures: int = 0

func _init() -> void:
	var profile := _make_profile(&"timed", 0.8, 0.4)
	var timer := TimedMeleeContactType.new()
	_expect(timer.arm(profile) == null, "nonzero contact fired while arming")
	_expect(timer.is_pending(), "armed contact was not pending")
	_expect(timer.advance(0.39) == null, "contact fired before its threshold")
	_expect(timer.advance(0.01) == profile, "contact did not fire at its exact threshold")
	_expect(not timer.is_pending(), "contact remained pending after consumption")
	_expect(timer.advance(profile.duration) == null, "one arm produced more than one contact")

	var zero_profile := _make_profile(&"zero", 0.5, 0.0)
	_expect(timer.arm(zero_profile) == zero_profile, "zero-time contact did not fire synchronously")
	_expect(not timer.is_pending(), "zero-time contact remained pending")

	var replacement := _make_profile(&"replacement", 0.7, 0.3)
	timer.arm(profile)
	_expect(timer.advance(0.3) == null, "first profile fired before rearm")
	_expect(timer.arm(replacement) == null, "replacement fired while rearming")
	_expect(timer.advance(0.29) == null, "rearm retained elapsed time from the first profile")
	_expect(timer.advance(0.01) == replacement, "rearmed profile did not fire at its own threshold")

	timer.arm(profile)
	timer.advance(0.2)
	timer.cancel()
	_expect(not timer.is_pending(), "cancel retained a pending contact")
	_expect(timer.advance(profile.duration) == null, "canceled contact fired")
	timer.arm(profile)
	_expect(timer.advance(profile.contact_time) == profile, "arming after cancel retained stale timing")

	if _failures == 0:
		print("TIMED_MELEE_CONTACT PASS")
		quit(0)
	else:
		print("TIMED_MELEE_CONTACT FAIL failures=%d" % _failures)
		quit(1)

func _make_profile(id: StringName, duration: float, contact_time: float) -> MeleeAttackProfile:
	var profile := MeleeAttackProfile.new()
	profile.id = id
	profile.duration = duration
	profile.contact_time = contact_time
	profile.cooldown = duration
	profile.reach = 1.0
	profile.base_damage = 1.0
	return profile

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[timed_melee_contact] FAIL: %s" % message)
