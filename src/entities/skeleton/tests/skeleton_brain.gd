extends SceneTree

const SkeletonBehaviorDefinitionType := preload("res://entities/skeleton/skeleton_behavior_definition.gd")
const SkeletonBrainType := preload("res://entities/skeleton/skeleton_brain.gd")

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[skeleton_brain] FAIL: %s" % message)

func _test_definition_defaults() -> void:
	var behavior := SkeletonBehaviorDefinitionType.new()
	_expect(behavior.validate("test"), "default behavior definition was rejected")
	_expect(is_equal_approx(behavior.roam_speed, 2.4), "roam speed changed")
	_expect(is_equal_approx(behavior.gravity, 30.0), "gravity changed")
	_expect(is_equal_approx(behavior.jump_velocity, 7.0), "jump velocity changed")
	_expect(is_equal_approx(behavior.detection_range, 30.0), "detection range changed")
	_expect(is_equal_approx(behavior.roam_radius, 30.0), "roam radius changed")
	_expect(is_equal_approx(behavior.roam_goal_seconds, 4.0), "roam goal duration changed")
	_expect(is_equal_approx(behavior.repath_seconds, 0.5), "repath duration changed")

func _test_deterministic_drifting_roam() -> void:
	var behavior := SkeletonBehaviorDefinitionType.new()
	var origin := Vector3(2.5, 7.0, 3.5)
	var first := SkeletonBrainType.new(behavior, 451)
	var second := SkeletonBrainType.new(behavior, 451)
	var distant_player := origin + Vector3(31.0, 0.0, 0.0)
	first.advance(0.0, origin, distant_player, false)
	second.advance(0.0, origin, distant_player, false)
	_expect(first.state == SkeletonBrainType.State.ROAM, "skeleton did not start roaming")
	_expect(first.get_movement_goal().is_equal_approx(second.get_movement_goal()), "same seed produced different roam goals")
	_expect(is_equal_approx(first.get_movement_goal().y, origin.y), "roam goal changed elevation")
	var first_distance := Vector2(first.get_movement_goal().x - origin.x, first.get_movement_goal().z - origin.z).length()
	_expect(first_distance >= behavior.roam_radius * 0.35 and first_distance <= behavior.roam_radius, "initial roam goal exceeded its configured radius")

	var drift_position := Vector3(102.5, 7.0, -96.5)
	distant_player = drift_position + Vector3(31.0, 0.0, 0.0)
	first.advance(behavior.roam_goal_seconds, drift_position, distant_player, false)
	second.advance(behavior.roam_goal_seconds, drift_position, distant_player, false)
	_expect(first.get_movement_goal().is_equal_approx(second.get_movement_goal()), "drifting roam sequence was not deterministic")
	var drift_distance := Vector2(first.get_movement_goal().x - drift_position.x, first.get_movement_goal().z - drift_position.z).length()
	_expect(drift_distance >= behavior.roam_radius * 0.35 and drift_distance <= behavior.roam_radius, "next roam goal was not centered on the current position")
	_expect(Vector2(first.get_movement_goal().x - origin.x, first.get_movement_goal().z - origin.z).length() > behavior.roam_radius, "roam territory remained anchored to its starting position")

	var rejected_goal := first.get_movement_goal()
	first.reject_movement_goal(drift_position)
	_expect(not first.get_movement_goal().is_equal_approx(rejected_goal), "rejected roam goal was retained")
	var replacement_distance := Vector2(first.get_movement_goal().x - drift_position.x, first.get_movement_goal().z - drift_position.z).length()
	_expect(replacement_distance >= behavior.roam_radius * 0.35 and replacement_distance <= behavior.roam_radius, "replacement roam goal exceeded its configured radius")

func _test_detection_states() -> void:
	var behavior := SkeletonBehaviorDefinitionType.new()
	var brain := SkeletonBrainType.new(behavior, 810)
	var self_position := Vector3(4.5, 7.0, -2.5)
	brain.advance(0.0, self_position, self_position + Vector3(30.01, 0.0, 0.0), true)
	_expect(brain.state == SkeletonBrainType.State.ROAM, "hidden position outside detection range stopped roaming")
	_expect(not brain.is_player_in_detection_range(self_position, self_position + Vector3(30.01, 100.0, 0.0)), "horizontal detection accepted a player beyond 30 blocks")
	brain.advance(0.0, self_position, self_position + Vector3(30.0, 0.0, 0.0), false)
	_expect(brain.state == SkeletonBrainType.State.SEARCH_COVER, "exposed position inside detection range did not search for cover")
	brain.advance(0.0, self_position, self_position + Vector3(20.0, 100.0, 0.0), false)
	_expect(brain.state == SkeletonBrainType.State.SEARCH_COVER, "vertical separation incorrectly changed horizontal detection")
	brain.advance(0.0, self_position, self_position + Vector3(20.0, 0.0, 0.0), true)
	_expect(brain.state == SkeletonBrainType.State.HIDE, "occluded position inside detection range did not hide")
	brain.advance(0.0, self_position, self_position + Vector3(20.0, 0.0, 0.0), false)
	_expect(brain.state == SkeletonBrainType.State.SEARCH_COVER, "newly exposed hiding position did not resume cover search")
	brain.advance(0.0, self_position, self_position + Vector3(31.0, 0.0, 0.0), true)
	_expect(brain.state == SkeletonBrainType.State.ROAM, "player leaving detection range did not restore roaming")

func _run() -> void:
	_test_definition_defaults()
	_test_deterministic_drifting_roam()
	_test_detection_states()
	if _failures == 0:
		print("SKELETON_BRAIN PASS")
		quit(0)
	else:
		print("SKELETON_BRAIN FAIL failures=%d" % _failures)
		quit(1)
