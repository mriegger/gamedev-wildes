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
	_expect(is_equal_approx(behavior.gravity, 30.0), "gravity changed")
	var configured_behavior := load("res://entities/stone_golem/stone_golem_behavior.tres") as StoneGolemBehaviorDefinitionType
	_expect(configured_behavior != null, "configured behavior resource did not load")
	if configured_behavior != null:
		_expect(configured_behavior.validate(configured_behavior.resource_path), "configured behavior definition was rejected")
		_expect(is_equal_approx(configured_behavior.gravity, 30.0), "configured gravity changed")

func _test_invalid_behavior_values() -> void:
	for value in [0.0, -0.1, INF, NAN]:
		_expect(not StoneGolemBehaviorDefinitionType.is_valid_gravity(value), "invalid gravity was accepted")
	_expect(StoneGolemBehaviorDefinitionType.is_valid_gravity(30.0), "valid gravity was rejected")

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
			brain.advance(delta, position, _make_observation(position + Vector3(2.0, 0.0, -3.0)))
			_expect(brain.state == StoneGolemBrainType.State.DORMANT, "valid advance changed the dormant state")

func _run() -> void:
	_test_definition_defaults_and_resource()
	_test_invalid_behavior_values()
	_test_dormant_stability()
	if _failures == 0:
		print("STONE_GOLEM_BRAIN PASS")
		quit(0)
	else:
		print("STONE_GOLEM_BRAIN FAIL failures=%d" % _failures)
		quit(1)
