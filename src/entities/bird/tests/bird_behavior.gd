extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[bird_behavior] FAIL: %s" % message)

func _run() -> void:
	var behavior := load("res://entities/bird/bird_behavior.tres") as BirdBehaviorDefinition
	_expect(behavior != null and behavior.validate(behavior.resource_path), "bird behavior definition is invalid")
	var first := BirdBrain.new(behavior, 4419)
	var second := BirdBrain.new(behavior, 4419)
	var different := BirdBrain.new(behavior, 4420)
	var found_difference := false
	for _sample in 12:
		var first_offset := first.sample_landing_offset()
		var second_offset := second.sample_landing_offset()
		var different_offset := different.sample_landing_offset()
		_expect(first_offset.is_equal_approx(second_offset), "identical seeds produced different landing offsets")
		var first_altitude := first.sample_cruise_altitude()
		var second_altitude := second.sample_cruise_altitude()
		var different_altitude := different.sample_cruise_altitude()
		_expect(first_altitude == second_altitude, "identical seeds produced different cruise altitudes")
		found_difference = found_difference or not first_offset.is_equal_approx(different_offset) or first_altitude != different_altitude
	_expect(found_difference, "different seeds produced the same sampled sequence")

	var cycle := BirdBrain.new(behavior, 9021)
	var position := Vector3(0.5, 10.0, 0.5)
	cycle.advance(0.0, position, false, true)
	_expect(cycle.state == BirdBrain.State.DESCEND, "cruise did not enter descent")
	cycle.advance(0.0, position, true, false)
	_expect(cycle.state == BirdBrain.State.GROUNDED_IDLE, "ground contact did not enter idle")
	cycle.advance(behavior.landed_idle_max_seconds, position, true, false)
	_expect(cycle.state == BirdBrain.State.GROUNDED_WALK, "idle did not enter the first walk")
	var first_goal := cycle.get_movement_goal()
	cycle.advance(behavior.grounded_walk_seconds, position, true, false)
	_expect(cycle.state == BirdBrain.State.GROUNDED_IDLE, "first walk did not return to idle")
	cycle.advance(behavior.landed_idle_max_seconds, position, true, false)
	_expect(cycle.state == BirdBrain.State.GROUNDED_WALK, "second idle did not enter a walk")
	_expect(not cycle.get_movement_goal().is_equal_approx(first_goal), "successive walks reused the same goal")
	cycle.advance(behavior.grounded_walk_seconds, position, true, false)
	_expect(cycle.state == BirdBrain.State.TAKEOFF, "second walk did not trigger takeoff")
	cycle.reject_takeoff()
	_expect(cycle.state == BirdBrain.State.GROUNDED_IDLE, "rejected takeoff did not return to idle")
	cycle.advance(behavior.landed_idle_max_seconds, position, true, false)
	cycle.advance(behavior.grounded_walk_seconds, position, true, false)
	cycle.advance(behavior.landed_idle_max_seconds, position, true, false)
	cycle.advance(behavior.grounded_walk_seconds, position, true, false)
	_expect(cycle.state == BirdBrain.State.TAKEOFF, "rejected takeoff did not retry after grounded wandering")
	cycle.advance(0.0, position, false, true)
	_expect(cycle.state == BirdBrain.State.CRUISE, "takeoff completion did not return to cruise")
	cycle.advance(0.0, position, false, true)
	_expect(cycle.state == BirdBrain.State.DESCEND, "cruise did not restart descent")
	cycle.reject_ground_contact()
	_expect(cycle.state == BirdBrain.State.CRUISE, "rejected ground contact did not resume flight")

	var rejection := BirdBrain.new(behavior, 991)
	rejection.advance(0.0, position, false, true)
	rejection.advance(0.0, position, true, false)
	rejection.advance(behavior.landed_idle_max_seconds, position, true, false)
	rejection.reject_movement_goal()
	_expect(rejection.state == BirdBrain.State.GROUNDED_IDLE, "rejected walk did not return to idle")
	rejection.reject_flight_goal()
	_expect(rejection.state == BirdBrain.State.GROUNDED_IDLE, "grounded flight rejection changed state")

	if _failures == 0:
		print("BIRD_BEHAVIOR PASS")
		quit(0)
	else:
		print("BIRD_BEHAVIOR FAIL failures=%d" % _failures)
		quit(1)
