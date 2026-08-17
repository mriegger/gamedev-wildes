extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_target_observation] FAIL: %s" % message)

func _run() -> void:
	var player_position := Vector3(1.0, 2.0, 3.0)
	var camera_origin := Vector3(8.0, 9.0, 10.0)
	var observation := EntityTargetObservation.create(
		player_position,
		camera_origin,
		Vector3(0.0, 0.0, -4.0),
		Vector3(3.0, 0.0, 0.0),
	)
	_expect(observation != null, "valid plain values were rejected")
	if observation != null:
		_expect(observation.validate(), "constructed observation failed validation")
		_expect(observation.player_position == player_position, "player position changed")
		_expect(observation.camera_origin == camera_origin, "camera origin changed")
		_expect(observation.camera_forward == Vector3.FORWARD, "camera forward was not normalized")
		_expect(observation.camera_right == Vector3.RIGHT, "camera right was not normalized")

	var invalid_position := EntityTargetObservation.create(Vector3(INF, 0.0, 0.0), camera_origin, Vector3.FORWARD, Vector3.RIGHT)
	_expect(invalid_position == null, "non-finite player position was accepted")
	var invalid_direction := EntityTargetObservation.create(player_position, camera_origin, Vector3.ZERO, Vector3.RIGHT)
	_expect(invalid_direction == null, "zero camera direction was accepted")

	var camera_basis := Basis.from_euler(Vector3(0.2, 0.6, -0.1))
	var camera_transform := Transform3D(camera_basis, camera_origin)
	var horizontal_offset := 2.5
	var vertical_offset := -1.25
	var camera_observation := EntityTargetObservation.from_camera_values(
		player_position,
		camera_transform,
		horizontal_offset,
		vertical_offset,
	)
	_expect(camera_observation != null, "valid camera values were rejected")
	if camera_observation != null:
		var normalized_basis := camera_basis.orthonormalized()
		var expected_origin := camera_origin + normalized_basis.x * horizontal_offset + normalized_basis.y * vertical_offset
		_expect(camera_observation.camera_origin.is_equal_approx(expected_origin), "camera offsets did not move the effective origin")
		_expect(camera_observation.camera_forward.is_equal_approx(-normalized_basis.z), "camera forward did not use the global basis")
		_expect(camera_observation.camera_right.is_equal_approx(normalized_basis.x), "camera right did not use the global basis")

	if _failures == 0:
		print("ENTITY_TARGET_OBSERVATION PASS")
		quit(0)
	else:
		print("ENTITY_TARGET_OBSERVATION FAIL failures=%d" % _failures)
		quit(1)
