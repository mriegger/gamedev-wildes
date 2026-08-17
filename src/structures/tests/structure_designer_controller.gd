extends SceneTree

const CONTROLLER_SCENE: String = "res://structures/runtime/structure_designer_controller.tscn"

class TestVoxelSpace:
	extends VoxelSpace

	var spawn_position: Vector3 = Vector3(0.5, 0.0, 0.5)
	var solid_cells: Dictionary = {}
	var guide_floor_enabled: bool = true

	func add_solid(cell: Vector3i) -> void:
		solid_cells[cell] = true

	func clear_solids() -> void:
		solid_cells.clear()

	func get_spawn_position() -> Vector3:
		return spawn_position

	func is_solid(position: Vector3i) -> bool:
		return solid_cells.has(position) or guide_floor_enabled and position.y == -1

	func is_raycast_solid(position: Vector3i) -> bool:
		return is_solid(position)

	func is_face_targetable(block_position: Vector3i, _face_normal: Vector3i) -> bool:
		return is_raycast_solid(block_position)

	func get_highest_top(x: int, z: int) -> float:
		var highest := NO_SURFACE_Y
		if guide_floor_enabled:
			highest = 0.0
		for cell_value in solid_cells:
			var cell := cell_value as Vector3i
			if cell.x == x and cell.z == z:
				highest = maxf(highest, float(cell.y + 1))
		return highest

var _errors: Array[String] = []
var _controller: StructureDesignerController
var _space: TestVoxelSpace

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(CONTROLLER_SCENE) as PackedScene
	_expect(packed != null, "controller scene did not load")
	if packed == null:
		_finish()
		return
	_controller = packed.instantiate() as StructureDesignerController
	_expect(_controller != null, "controller scene root has the wrong type")
	if _controller == null:
		_finish()
		return
	root.add_child(_controller)
	await process_frame
	_space = TestVoxelSpace.new()
	_controller.setup(_space)
	_test_scene_and_spawn()
	_test_body_intersection()
	_test_collision_flight()
	_test_actions_and_acceleration()
	_test_mouse_look_and_capture()
	_test_centered_raycast()
	_release_actions()
	_controller.set_input_enabled(false)
	_controller.set_camera_active(false)
	_controller.queue_free()
	await process_frame
	await process_frame
	_finish()

func _test_scene_and_spawn() -> void:
	_expect(_controller.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "designer camera is not perspective")
	_expect(is_equal_approx(_controller.camera.fov, 75.0), "designer camera FOV changed")
	_expect(_controller.camera.position == Vector3.ZERO, "designer camera is not centered on the pitch pivot")
	_expect(_controller.pitch.position.is_equal_approx(Vector3(0.0, 1.62, 0.0)), "designer eye height changed")
	_expect(_controller.global_position.is_equal_approx(_space.spawn_position), "setup did not use the voxel-space spawn")
	_controller.global_position = Vector3(9.0, 9.0, 9.0)
	_controller.reset_to_spawn()
	_expect(_controller.global_position.is_equal_approx(_space.spawn_position), "spawn reset was not stable")
	_controller.set_camera_active(true)
	_expect(_controller.camera.current, "designer camera did not become current")
	_expect(_action_uses_key(&"structure_designer_descend", KEY_CTRL), "designer descend is not mapped to Ctrl")

func _test_body_intersection() -> void:
	_controller.global_position = Vector3(0.5, 0.0, 0.5)
	_expect(_controller.body_intersects_cell(Vector3i(0, 0, 0)), "body did not intersect its feet cell")
	_expect(_controller.body_intersects_cell(Vector3i(0, 1, 0)), "body did not intersect its upper cell")
	_expect(not _controller.body_intersects_cell(Vector3i(1, 0, 0)), "body intersected a separated horizontal cell")
	_expect(not _controller.body_intersects_cell(Vector3i(0, 2, 0)), "body intersected a cell above its head")
	_controller.global_position.x = 0.69
	_expect(not _controller.body_intersects_cell(Vector3i(1, 0, 0)), "body intersection included a separated boundary")
	_controller.global_position.x = 0.71
	_expect(_controller.body_intersects_cell(Vector3i(1, 0, 0)), "body intersection missed a positive overlap")

func _test_collision_flight() -> void:
	_space.clear_solids()
	_space.add_solid(Vector3i(2, 0, 0))
	_space.add_solid(Vector3i(2, 1, 0))
	_controller.global_position = Vector3(0.5, 0.0, 0.5)
	_controller.rotation = Vector3.ZERO
	_controller.apply_flight_input(Vector2.RIGHT, 0.0, false, 1.0)
	_expect(_controller.global_position.x < 1.71, "horizontal flight crossed a solid wall")
	_expect(is_zero_approx(_controller.velocity.x), "wall collision retained horizontal velocity")

	_space.clear_solids()
	_controller.global_position = Vector3(0.5, 3.0, 0.5)
	_controller.apply_flight_input(Vector2.ZERO, 0.0, false, 0.5)
	_expect(is_equal_approx(_controller.global_position.y, 3.0), "idle flight applied gravity")
	_controller.apply_flight_input(Vector2.ZERO, 1.0, false, 0.25)
	_expect(is_equal_approx(_controller.global_position.y, 4.5), "ascending flight used the wrong speed")
	_controller.apply_flight_input(Vector2.ZERO, -1.0, false, 1.0)
	_expect(is_equal_approx(_controller.global_position.y, 0.0), "descending flight crossed the guide floor")

func _test_actions_and_acceleration() -> void:
	_space.clear_solids()
	_controller.rotation = Vector3.ZERO
	_controller.pitch.rotation = Vector3.ZERO
	_controller.set_mouse_capture_enabled(false)
	_controller.set_input_enabled(true)

	_controller.global_position = Vector3(0.5, 3.0, 0.5)
	Input.action_press(&"move_forward")
	_controller._physics_process(0.1)
	Input.action_release(&"move_forward")
	_expect(_controller.global_position.z < 0.5, "W did not move the controller forward")

	_controller.global_position = Vector3(0.5, 3.0, 0.5)
	Input.action_press(&"jump")
	_controller._physics_process(0.1)
	Input.action_release(&"jump")
	_expect(_controller.global_position.y > 3.0, "Space did not move the controller upward")

	_controller.global_position = Vector3(0.5, 3.0, 0.5)
	Input.action_press(&"structure_designer_descend")
	_controller._physics_process(0.1)
	Input.action_release(&"structure_designer_descend")
	_expect(_controller.global_position.y < 3.0, "Ctrl did not move the controller downward")

	_controller.global_position = Vector3(0.5, 3.0, 0.5)
	Input.action_press(&"move_forward")
	_controller._physics_process(0.1)
	Input.action_release(&"move_forward")
	var normal_distance := 0.5 - _controller.global_position.z
	_controller.global_position = Vector3(0.5, 3.0, 0.5)
	Input.action_press(&"move_forward")
	Input.action_press(&"sprint")
	_controller._physics_process(0.1)
	Input.action_release(&"move_forward")
	Input.action_release(&"sprint")
	var accelerated_distance := 0.5 - _controller.global_position.z
	_expect(accelerated_distance > normal_distance, "Shift did not accelerate flight")
	_controller.set_input_enabled(false)

func _test_mouse_look_and_capture() -> void:
	_controller.rotation = Vector3.ZERO
	_controller.pitch.rotation = Vector3.ZERO
	_controller.set_mouse_capture_enabled(true)
	_controller.set_input_enabled(true)
	_expect(_controller._mouse_capture_enabled, "enabled controller did not request mouse capture")
	if DisplayServer.get_name() != "headless":
		_expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "enabled controller did not capture the mouse")
	_controller.apply_mouse_look(Vector2(100.0, 50.0))
	_expect(_controller.rotation.y < 0.0, "horizontal mouse motion did not change yaw")
	_expect(_controller.pitch.rotation.x < 0.0, "vertical mouse motion did not change pitch")
	_controller.apply_mouse_look(Vector2(0.0, 100000.0))
	_expect(is_equal_approx(_controller.pitch.rotation.x, -StructureDesignerController.MAX_PITCH_RADIANS), "pitch was not clamped")
	var yaw_before := _controller.rotation.y
	var pitch_before := _controller.pitch.rotation.x
	_controller.set_mouse_capture_enabled(false)
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "capture disable did not release the mouse")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(40.0, -40.0)
	_controller._unhandled_input(motion)
	_expect(is_equal_approx(_controller.rotation.y, yaw_before) and is_equal_approx(_controller.pitch.rotation.x, pitch_before), "released mouse still changed the view")
	_controller.set_input_enabled(false)
	_expect(not _controller._input_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "input disable did not stop and release the controller")

func _test_centered_raycast() -> void:
	_space.clear_solids()
	_controller.global_position = Vector3(0.5, 0.0, 0.5)
	_controller.rotation = Vector3.ZERO
	_controller.pitch.rotation = Vector3.ZERO
	_space.add_solid(Vector3i(0, 1, -6))
	var hit := _controller.get_centered_raycast()
	_expect(hit != null and hit.target_cell == Vector3i(0, 1, -6), "center ray did not reach the six-block target")
	if hit != null:
		_expect(hit.placement_cell == Vector3i(0, 1, -5), "center ray returned the wrong placement cell")
		_expect(hit.face_normal == Vector3i.BACK, "center ray returned the wrong face normal")
	_space.clear_solids()
	_space.add_solid(Vector3i(0, 1, -7))
	_expect(_controller.get_centered_raycast() == null, "center ray exceeded six blocks")

func _action_uses_key(action: StringName, key: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == key or key_event.physical_keycode == key:
				return true
	return false

func _release_actions() -> void:
	for action in [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"structure_designer_descend", &"sprint"]:
		Input.action_release(action)

func _finish() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _errors.is_empty():
		print("STRUCTURE_DESIGNER_CONTROLLER PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
