extends SceneTree

const StoneGolemBehaviorDefinitionType := preload("res://entities/stone_golem/stone_golem_behavior_definition.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")
const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_brain] FAIL: %s" % message)

func _make_observation(player_position: Vector3) -> EntityTargetObservationType:
	var observation := EntityTargetObservationType.create(
		player_position,
		player_position + Vector3(12.0, 16.0, 12.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)
	assert(observation != null)
	return observation

func _test_definition_defaults_and_resource() -> void:
	var behavior := StoneGolemBehaviorDefinitionType.new()
	_expect(behavior.validate("test"), "default behavior definition was rejected")
	_expect(is_equal_approx(behavior.movement_speed, 1.2), "movement speed changed")
	_expect(is_equal_approx(behavior.gravity, 30.0), "gravity changed")
	_expect(is_equal_approx(behavior.jump_velocity, 7.0), "jump velocity changed")
	_expect(is_equal_approx(behavior.detection_range, 16.0), "detection range changed")
	_expect(is_equal_approx(behavior.forget_range, 24.0), "forget range changed")
	_expect(is_equal_approx(behavior.target_memory_seconds, 3.0), "target memory changed")
	_expect(is_equal_approx(behavior.repath_seconds, 0.5), "repath duration changed")
	var configured_behavior := load("res://entities/stone_golem/stone_golem_behavior.tres") as StoneGolemBehaviorDefinitionType
	_expect(configured_behavior != null, "configured behavior resource did not load")
	if configured_behavior != null:
		_expect(configured_behavior.validate(configured_behavior.resource_path), "configured behavior definition was rejected")
		_expect(is_equal_approx(configured_behavior.movement_speed, 1.2), "configured movement speed changed")
		_expect(is_equal_approx(configured_behavior.gravity, 30.0), "configured gravity changed")
		_expect(is_equal_approx(configured_behavior.jump_velocity, 7.0), "configured jump velocity changed")
		_expect(is_equal_approx(configured_behavior.detection_range, 16.0), "configured detection range changed")
		_expect(is_equal_approx(configured_behavior.forget_range, 24.0), "configured forget range changed")
		_expect(is_equal_approx(configured_behavior.target_memory_seconds, 3.0), "configured target memory changed")
		_expect(is_equal_approx(configured_behavior.repath_seconds, 0.5), "configured repath duration changed")

func _test_invalid_behavior_values() -> void:
	_expect(StoneGolemBehaviorDefinitionType.is_valid_movement(1.2, 7.0, 0.5), "valid movement was rejected")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_movement(0.0, 7.0, 0.5), "zero movement speed was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_movement(INF, 7.0, 0.5), "infinite movement speed was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_movement(1.2, 0.0, 0.5), "zero jump velocity was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_movement(1.2, NAN, 0.5), "NaN jump velocity was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_movement(1.2, 7.0, 0.0), "zero repath duration was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_movement(1.2, 7.0, NAN), "NaN repath duration was accepted")
	for value in [0.0, -0.1, INF, NAN]:
		_expect(not StoneGolemBehaviorDefinitionType.is_valid_gravity(value), "invalid gravity was accepted")
	_expect(StoneGolemBehaviorDefinitionType.is_valid_gravity(30.0), "valid gravity was rejected")
	_expect(StoneGolemBehaviorDefinitionType.is_valid_awareness(16.0, 24.0, 3.0), "valid awareness was rejected")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_awareness(0.0, 24.0, 3.0), "zero detection range was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_awareness(INF, 24.0, 3.0), "infinite detection range was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_awareness(16.0, NAN, 3.0), "NaN forget range was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_awareness(16.0, 15.999, 3.0), "forget range below detection was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_awareness(16.0, 24.0, 0.0), "zero target memory was accepted")
	_expect(not StoneGolemBehaviorDefinitionType.is_valid_awareness(16.0, 24.0, NAN), "NaN target memory was accepted")

func _test_dormant_stability() -> void:
	var behavior := StoneGolemBehaviorDefinitionType.new()
	var brain := StoneGolemBrainType.new(behavior)
	_expect(brain.state == StoneGolemBrainType.State.DORMANT, "Stone Golem did not start dormant")
	var positions := [
		Vector3(0.5, 1.0, 0.5),
		Vector3(-24.5, 7.0, 96.5),
		Vector3(128.5, -2.0, -64.5),
	]
	var deltas := [0.0, 1.0 / 120.0, 0.5, 3.0]
	for position in positions:
		for delta in deltas:
			brain.advance(delta, position, _make_observation(position + Vector3(2.0, 0.0, -3.0)), false, true)
			_expect(brain.state == StoneGolemBrainType.State.DORMANT, "valid advance changed the dormant state")
			_expect(not brain.is_alerted(), "dormant stability reported an alert")

func _test_awareness_transitions() -> void:
	var behavior := StoneGolemBehaviorDefinitionType.new()
	var brain := StoneGolemBrainType.new(behavior)
	var self_position := Vector3(0.5, 2.0, 0.5)
	var outside_detection := self_position + Vector3(behavior.detection_range + 0.001, 0.0, 0.0)
	brain.advance(0.0, self_position, _make_observation(outside_detection), true, true)
	_expect(brain.state == StoneGolemBrainType.State.DORMANT and not brain.is_alerted(), "visible target beyond detection range caused an alert")
	var detection_boundary := self_position + Vector3(behavior.detection_range, 0.0, 0.0)
	brain.advance(0.0, self_position, _make_observation(detection_boundary), true, true)
	_expect(brain.state == StoneGolemBrainType.State.CHASE and brain.is_alerted(), "clear target at the detection boundary did not alert")
	var hidden_position := self_position + Vector3(20.0, 0.0, 0.0)
	_expect(brain.get_movement_goal().is_equal_approx(detection_boundary), "clear target did not become the movement goal")
	var cached_visible_position := self_position + Vector3(8.0, 0.0, 4.0)
	brain.advance(0.1, self_position, _make_observation(cached_visible_position), true, false)
	_expect(brain.is_alerted(), "cached visibility stopped Stone Golem pursuit")
	_expect(brain.get_movement_goal().is_equal_approx(detection_boundary), "cached visible position replaced the freshly sampled movement goal")
	brain.advance(behavior.target_memory_seconds - 0.001, self_position, _make_observation(hidden_position), false, true)
	_expect(brain.is_alerted(), "hidden target exhausted memory before three seconds")
	_expect(brain.get_movement_goal().is_equal_approx(detection_boundary), "hidden target position replaced the last-seen goal")
	brain.advance(0.0, self_position, _make_observation(detection_boundary), true, true)
	brain.advance(behavior.target_memory_seconds, self_position, _make_observation(hidden_position), false, true)
	_expect(brain.state == StoneGolemBrainType.State.DORMANT and not brain.is_alerted(), "hidden target remained alerted at three seconds")
	brain.advance(0.0, self_position, _make_observation(detection_boundary), true, true)
	brain.advance(2.75, self_position, _make_observation(hidden_position), false, true)
	_expect(brain.is_alerted(), "target memory expired before refresh")
	var refreshed_position := self_position + Vector3(8.0, 0.0, 0.0)
	brain.advance(0.0, self_position, _make_observation(refreshed_position), true, true)
	brain.advance(2.75, self_position, _make_observation(hidden_position), false, true)
	_expect(brain.get_movement_goal().is_equal_approx(refreshed_position), "clear target did not refresh the movement goal")
	_expect(brain.is_alerted(), "clear target did not refresh memory")
	var forget_boundary := self_position + Vector3(behavior.forget_range, 0.0, 0.0)
	brain.advance(0.0, self_position, _make_observation(outside_detection), true, true)
	_expect(brain.get_movement_goal().is_equal_approx(refreshed_position), "visible target outside detection replaced the last-seen goal")
	brain.advance(0.0, self_position, _make_observation(forget_boundary), false, true)
	_expect(brain.is_alerted(), "target at the forget boundary was forgotten")
	_expect(brain.get_movement_goal().is_equal_approx(refreshed_position), "forget boundary changed the retained movement goal")
	var beyond_forget := self_position + Vector3(behavior.forget_range + 0.001, 0.0, 0.0)
	brain.advance(0.0, self_position, _make_observation(beyond_forget), false, true)
	_expect(brain.state == StoneGolemBrainType.State.DORMANT and not brain.is_alerted(), "target beyond the forget range was not forgotten immediately")

func _run() -> void:
	_test_definition_defaults_and_resource()
	_test_invalid_behavior_values()
	_test_dormant_stability()
	_test_awareness_transitions()
	if _failures == 0:
		print("STONE_GOLEM_BRAIN PASS")
		quit(0)
	else:
		print("STONE_GOLEM_BRAIN FAIL failures=%d" % _failures)
		quit(1)
