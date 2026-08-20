extends SceneTree

const NavigationCompassType := preload("res://ui/hud/navigation_compass.gd")

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var compass := NavigationCompassType.new()
	compass.size = Vector2(460.0, 62.0)
	var camera := Camera3D.new()
	var tracked := Node3D.new()
	root.add_child(camera)
	root.add_child(tracked)
	root.add_child(compass)
	await process_frame
	compass.setup(camera, tracked)
	_expect(compass.visible and compass.is_processing(), "setup did not activate the compass")
	_expect(not compass._has_target, "compass started with an unconfigured target")
	_expect(is_equal_approx(compass._get_heading_degrees(), 0.0), "identity camera did not face canonical north")
	compass.set_target_position(Vector3(10.0, 0.0, 0.0))
	_expect(is_equal_approx(compass._get_relative_bearing(Vector3(10.0, 0.0, 0.0)), 90.0), "east target was not right of north-facing camera")
	camera.rotation.y = -PI * 0.5
	_expect(is_equal_approx(compass._get_heading_degrees(), 90.0), "rotated camera did not face canonical east")
	_expect(is_zero_approx(compass._get_relative_bearing(Vector3(10.0, 0.0, 0.0))), "east target was not centered for east-facing camera")
	camera.rotation.y = PI
	_expect(is_equal_approx(compass._get_heading_degrees(), 180.0), "rotated camera did not face canonical south")
	camera.rotation.y = PI * 0.5
	_expect(is_equal_approx(compass._get_heading_degrees(), 270.0), "rotated camera did not face canonical west")
	tracked.position = Vector3(10.0, 0.0, 0.0)
	_expect(is_zero_approx(compass._get_relative_bearing(Vector3(10.0, 0.0, 0.0))), "target at the tracked position did not center")
	compass.clear_target()
	_expect(not compass._has_target, "cleared dungeon target remained active")
	compass.set_enemy_positions(PackedVector3Array([Vector3(15.0, 0.0, 0.0)]))
	_expect(compass._enemy_positions == PackedVector3Array([Vector3(15.0, 0.0, 0.0)]), "enemy positions were not retained")
	_expect(is_zero_approx(compass._get_enemy_marker_alpha(25.0)), "enemy marker was visible at the outer radius")
	_expect(is_equal_approx(compass._get_enemy_marker_alpha(15.0), 0.5), "enemy marker opacity did not ramp linearly")
	_expect(is_equal_approx(compass._get_enemy_marker_alpha(5.0), 1.0), "enemy marker did not reach full compass opacity at five blocks")
	_expect(is_equal_approx(compass._get_enemy_marker_alpha(2.0), 1.0), "nearby enemy marker exceeded full compass opacity")
	compass.set_menu_open(true)
	compass._process(compass.MENU_FADE_SECONDS)
	_expect(is_zero_approx(compass.self_modulate.a), "open menu did not fade out the compass")
	compass.set_menu_open(false)
	compass._process(compass.MENU_FADE_SECONDS)
	_expect(is_equal_approx(compass.self_modulate.a, 1.0), "closed menu did not fade in the compass")
	compass.set_available(false)
	compass._process(compass.MENU_FADE_SECONDS)
	_expect(is_zero_approx(compass.self_modulate.a), "unavailable compass did not fade out")
	compass.set_available(true)
	compass._process(compass.MENU_FADE_SECONDS)
	_expect(is_equal_approx(compass.self_modulate.a, 1.0), "available compass did not fade in")
	compass.free()
	camera.free()
	tracked.free()
	if _failures == 0:
		print("NAVIGATION_COMPASS PASS")
		quit(0)
	else:
		print("NAVIGATION_COMPASS FAIL failures=%d" % _failures)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("[navigation_compass] FAIL: %s" % message)
