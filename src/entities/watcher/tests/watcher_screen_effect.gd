extends SceneTree

var _errors: Array[String] = []

func _expect_projected_geometry(effect: WatcherScreenEffect, player: PlayerMotor, camera: Camera3D, label: String) -> void:
	var viewport_rect := root.get_visible_rect()
	var player_position := player.get_world_bounds().get_center()
	var projected_player := camera.unproject_position(player_position)
	var expected_center := (projected_player - viewport_rect.position) / viewport_rect.size
	_expect(effect.get_aperture_center().distance_to(expected_center) < 0.0001, "Watcher aperture center was incorrect for %s" % label)
	var projected_x_axis := camera.unproject_position(player_position + Vector3.RIGHT) - projected_player
	var projected_z_axis := camera.unproject_position(player_position + Vector3.BACK) - projected_player
	var pixel_to_ground_x := effect.get_aperture_pixel_to_ground_x()
	var pixel_to_ground_z := effect.get_aperture_pixel_to_ground_z()
	var mapped_x := Vector2(pixel_to_ground_x.dot(projected_x_axis), pixel_to_ground_z.dot(projected_x_axis))
	var mapped_z := Vector2(pixel_to_ground_x.dot(projected_z_axis), pixel_to_ground_z.dot(projected_z_axis))
	_expect(mapped_x.distance_to(Vector2.RIGHT) < 0.0001, "Watcher aperture X axis was not terrain-aligned for %s" % label)
	_expect(mapped_z.distance_to(Vector2.DOWN) < 0.0001, "Watcher aperture Z axis was not terrain-aligned for %s" % label)

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var effect_scene := load("res://entities/watcher/presentation/watcher_screen_effect.tscn") as PackedScene
	var player_scene := load("res://player/player.tscn") as PackedScene
	_expect(effect_scene != null, "Watcher screen effect scene did not load")
	_expect(player_scene != null, "player scene did not load")
	if effect_scene == null or player_scene == null:
		_finish(orphan_before)
		return
	var player := player_scene.instantiate() as PlayerMotor
	var camera := Camera3D.new()
	var effect := effect_scene.instantiate() as WatcherScreenEffect
	_expect(player != null, "player did not instantiate")
	_expect(effect != null, "Watcher screen effect did not instantiate")
	if player == null or effect == null:
		camera.free()
		_finish(orphan_before)
		return
	root.add_child(player)
	player.global_position = Vector3(2.0, 1.0, -3.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 42.0
	root.add_child(camera)
	camera.global_position = Vector3(12.0, 24.0, 17.0)
	camera.look_at(player.get_world_bounds().get_center())
	camera.current = true
	root.add_child(effect)
	await process_frame
	_expect(effect.layer == 0, "Watcher screen effect was not beneath the layer-1 HUD")
	_expect(not effect.visible, "Watcher screen effect started visible")
	_expect(not effect.is_processing(), "Watcher screen effect started processing")
	var overlay := effect.get_node(^"Overlay") as ColorRect
	var shader_material := overlay.material as ShaderMaterial
	_expect(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Watcher screen effect intercepts pointer input")
	_expect(shader_material != null, "Watcher screen effect shader material was missing")
	if shader_material != null:
		_expect(is_equal_approx(float(shader_material.get_shader_parameter(&"shake_power")), 0.01), "Watcher glitch shift power changed")
		_expect(is_equal_approx(float(shader_material.get_shader_parameter(&"shake_rate")), 1.0), "Watcher glitch rate changed")
		_expect(is_equal_approx(float(shader_material.get_shader_parameter(&"shake_speed")), 5.0), "Watcher glitch speed changed")
		_expect(is_equal_approx(float(shader_material.get_shader_parameter(&"shake_block_size")), 30.5), "Watcher glitch band size changed")
		_expect(is_zero_approx(float(shader_material.get_shader_parameter(&"shake_color_rate"))), "Watcher glitch retained color separation")
		_expect(is_equal_approx(float(shader_material.get_shader_parameter(&"noise_amount")), 0.2), "Watcher noise amount changed")
		_expect(is_equal_approx(float(shader_material.get_shader_parameter(&"noise_speed")), 1.0), "Watcher noise speed changed")
	_expect(is_zero_approx(effect.get_intensity()), "Watcher screen effect started with intensity")
	_expect(is_equal_approx(WatcherScreenEffect.APERTURE_RADIUS_WORLD_UNITS, 2.5), "Watcher aperture was not two and a half blocks")
	_expect(is_equal_approx(WatcherScreenEffect.APERTURE_FEATHER_WORLD_UNITS, 0.5), "Watcher aperture feather changed")
	effect.setup(player, camera)
	effect.setup(player, camera)
	effect.set_active(true)
	_expect(effect.visible and effect.is_processing(), "Watcher screen effect did not activate")
	effect._process(WatcherScreenEffect.ONSET_SECONDS * 0.5)
	_expect(is_equal_approx(effect.get_intensity(), 0.5), "Watcher screen effect onset was not smooth")
	effect.set_active(true)
	effect._process(WatcherScreenEffect.ONSET_SECONDS * 0.5)
	_expect(is_equal_approx(effect.get_intensity(), 1.0), "idempotent activation restarted the onset")
	effect._process(600.0)
	_expect(effect.visible and effect.is_processing() and is_equal_approx(effect.get_intensity(), 1.0), "Watcher effect expired during a long encounter")
	_expect_projected_geometry(effect, player, camera, "default zoom")
	var centered_projection := effect.get_aperture_center()
	_expect(centered_projection.distance_to(Vector2(0.5, 0.5)) < 0.001, "Watcher aperture was not centered on the projected player body")
	var viewport_rect := root.get_visible_rect()
	var feet_projection := (camera.unproject_position(player.global_position) - viewport_rect.position) / viewport_rect.size
	_expect(not centered_projection.is_equal_approx(feet_projection), "Watcher aperture remained centered on the player feet")
	for zoom_size in [18.0, 42.0, 70.0]:
		camera.size = zoom_size
		effect._process(0.0)
		_expect_projected_geometry(effect, player, camera, "orthographic size %.1f" % zoom_size)
	camera.h_offset = 2.0
	camera.v_offset = 1.0
	effect._process(0.0)
	_expect_projected_geometry(effect, player, camera, "camera offsets")
	_expect(not effect.get_aperture_center().is_equal_approx(centered_projection), "Watcher aperture ignored camera offsets")
	var original_viewport_size := root.size
	root.size = Vector2i(900, 600)
	await process_frame
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.size = 42.0
	effect._process(0.0)
	_expect_projected_geometry(effect, player, camera, "resized viewport")
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.size = 21.0
	effect._process(0.0)
	_expect_projected_geometry(effect, player, camera, "horizontal orthographic scale")
	var previous_pixel_to_ground_x := effect.get_aperture_pixel_to_ground_x()
	camera.global_position = player.get_world_bounds().get_center() + Vector3(17.0, 24.0, -12.0)
	camera.look_at(player.get_world_bounds().get_center())
	effect._process(0.0)
	_expect_projected_geometry(effect, player, camera, "rotated camera")
	_expect(not effect.get_aperture_pixel_to_ground_x().is_equal_approx(previous_pixel_to_ground_x), "Watcher aperture axes ignored camera rotation")
	root.size = original_viewport_size
	effect.set_presentation_enabled(false)
	_expect(not effect.visible and not effect.is_processing() and is_zero_approx(effect.get_intensity()), "Watcher effect remained visible outside its presentation context")
	effect.set_presentation_enabled(true)
	_expect(effect.visible and effect.is_processing() and is_zero_approx(effect.get_intensity()), "Watcher effect did not restart when its presentation context returned")
	effect._process(WatcherScreenEffect.ONSET_SECONDS)
	_expect(is_equal_approx(effect.get_intensity(), 1.0), "Watcher effect did not restore its onset after a context transition")
	effect.set_active(false)
	effect._process(WatcherScreenEffect.FADE_SECONDS * 0.5)
	_expect(effect.visible and effect.is_processing(), "Watcher screen effect hid before its fade completed")
	_expect(is_equal_approx(effect.get_intensity(), 0.5), "Watcher screen effect fade was not smooth")
	effect.set_active(false)
	effect._process(WatcherScreenEffect.FADE_SECONDS * 0.5)
	_expect(is_zero_approx(effect.get_intensity()), "Watcher screen effect did not finish fading")
	_expect(not effect.visible and not effect.is_processing(), "Watcher screen effect kept rendering at zero intensity")
	effect.queue_free()
	camera.queue_free()
	player.queue_free()
	await process_frame
	_finish(orphan_before)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish(orphan_before: int) -> void:
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after <= orphan_before, "orphan count increased from %d to %d" % [orphan_before, orphan_after])
	if _errors.is_empty():
		print("WATCHER_SCREEN_EFFECT PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("WATCHER_SCREEN_EFFECT FAIL %s" % str(_errors))
		quit(1)
