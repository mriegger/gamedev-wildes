extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _game: Game = null
var _world: WorldController = null
var _player: PlayerMotor = null
var _errors: Array[String] = []
var _orphan_before: int = 0
var _start_msec: int = 0
var _mine_place_count: int = 0
var _max_data_chunks: int = 0
var _max_visible_chunks: int = 0
var _max_terrain_chunks: int = 0
var _max_orphan: int = 0
var _last_log_frame: int = 0
var _done: bool = false
var _session_ready: bool = false
var _streaming_race_started: bool = false
var _streaming_race_verified: bool = false
var _texture_pipeline_verified: bool = false
var _lighting_pipeline_verified: bool = false
var _item_round_trip_verified: bool = false
var _streaming_race_started_msec: int = 0
var _movement_frames: int = 0
var _sprint_input_start_msec: int = 0
var _sprint_camera_size: float = 0.0
var _jump_input_start_msec: int = 0
var _jump_start_y: float = 0.0
var _panel_toggle_msec: int = 0
var _streaming_race_position: Vector3
var _edited_chunk: Vector2i
var _forced_evictions: Array[Vector2i] = []

const MOVEMENT_FRAMES: int = 900
const STREAMING_RACE_TIMEOUT_MSEC: int = 30000

func _init() -> void:
	print("[soak] starting headless game soak")
	_orphan_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("[soak] orphan before %d" % _orphan_before)
	_start_msec = Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if _done:
		return false
	_frame += 1
	if _phase == 0 and _frame == 2:
		var packed: PackedScene = load("res://game/game.tscn") as PackedScene
		if packed == null:
			_fail("failed to load game.tscn")
			return false
		_game = packed.instantiate() as Game
		if _game == null:
			_fail("game instantiate null")
			return false
		_game.configure_session(-1, {"seed": 1337, "time_of_day": 16.25})
		_game.session_ready.connect(_on_session_ready)
		root.add_child(_game)
		print("[soak] game added frame %d" % _frame)
		_phase = 1
	elif _phase == 1 and _frame == 10:
		_world = _game.get_node_or_null("World") as WorldController
		_player = _game.get_node_or_null("Player") as PlayerMotor
		if _world == null or _player == null:
			_fail("world or player null after add")
			return false
		print("[soak] waiting for world generation")
		_phase = 2
	elif _phase == 2:
		var loading_clock := _game.get_node("Environment/GameClock") as GameClock
		if not _session_ready and not is_equal_approx(loading_clock.time_of_day, 16.25):
			_fail("clock changed while loading: %.6f" % loading_clock.time_of_day)
			return false
		if _frame % 30 == 0:
			print("[soak] waiting gen frame %d orphan=%d" % [_frame, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
		if _session_ready:
			print("[soak] world generated at frame %d" % _frame)
			var ready_clock := _game.get_node("Environment/GameClock") as GameClock
			if absf(ready_clock.time_of_day - 16.25) > 0.01:
				_fail("clock did not start from saved time: %.6f" % ready_clock.time_of_day)
				return false
			if _world.voxel_model == null or _world.chunk_manager == null or _world.chunk_renderer == null:
				_fail("world not fully generated voxel=%s manager=%s renderer=%s" % [str(_world.voxel_model != null), str(_world.chunk_manager != null), str(_world.chunk_renderer != null)])
				return false
			if not _verify_texture_pipeline():
				return false
			if not _verify_side_face_ao():
				return false
			if not _verify_lighting_pipeline():
				return false
			var spawn = _world.voxel_model.get_spawn_position()
			_player.global_position = spawn + Vector3(0, 2, 0)
			print("[soak] spawn %s player %s" % [str(spawn), str(_player.global_position)])
			_phase = 3
		elif _frame > 600:
			_fail("world generation timeout at frame %d" % _frame)
			return false
	elif _phase == 3:
		if _frame < 180:
			return false
		if _game.animation_tuning_panel != null:
			_fail("animation tuning panel was initialized before F10 requested it")
			return false
		_push_key(KEY_F10, true)
		_panel_toggle_msec = Time.get_ticks_msec()
		_phase = 30
	elif _phase == 30:
		if _game.animation_tuning_panel == null or not _game.animation_tuning_panel.is_open():
			if Time.get_ticks_msec() - _panel_toggle_msec >= 1000:
				_fail("F10 did not open the animation tuning panel")
			return false
		if (_game.animation_tuning_panel.get_node("Panel") as Panel).size.x > 420.0:
			_fail("animation tuning panel obscures too much of the character view")
			return false
		_push_key(KEY_F10, false)
		_panel_toggle_msec = Time.get_ticks_msec()
		_phase = 300
	elif _phase == 300:
		if Time.get_ticks_msec() - _panel_toggle_msec < 50:
			return false
		_push_key(KEY_F10, true)
		_panel_toggle_msec = Time.get_ticks_msec()
		_phase = 301
	elif _phase == 301:
		if Time.get_ticks_msec() - _panel_toggle_msec < 50:
			return false
		if _game.animation_tuning_panel.is_open():
			if Time.get_ticks_msec() - _panel_toggle_msec >= 1000:
				_fail("F10 did not close the animation tuning panel")
			return false
		_push_key(KEY_F10, false)
		_push_key(KEY_W, true)
		_push_key(KEY_SHIFT, true)
		_sprint_camera_size = _game.camera_rig.camera.size
		_sprint_input_start_msec = Time.get_ticks_msec()
		_phase = 31
	elif _phase == 31:
		var sprint_state = _player.animation_driver.animator.get_current_state()
		var planar_speed = Vector2(_player.velocity.x, _player.velocity.z).length()
		if not _player.is_sprinting or not is_equal_approx(planar_speed, _player.sprint_speed) or sprint_state != BlockyHumanoidAnimator.SPRINT:
			if Time.get_ticks_msec() - _sprint_input_start_msec >= 1000:
				_verify_sprint_input()
			return false
		if not _verify_sprint_input():
			return false
		_push_key(KEY_SPACE, true)
		_jump_input_start_msec = Time.get_ticks_msec()
		_jump_start_y = _player.global_position.y
		_phase = 32
	elif _phase == 32:
		if _player.velocity.y > 0.0:
			_fail("jump launched before its anticipation pose")
			return false
		if _player.jump_anticipation <= 0.0 or not _player.on_ground:
			if Time.get_ticks_msec() - _jump_input_start_msec >= 1000:
				_fail("jump anticipation pose was not observed")
			return false
		_push_key(KEY_SPACE, false)
		_phase = 33
	elif _phase == 33:
		if _player.velocity.y <= 0.0:
			if Time.get_ticks_msec() - _jump_input_start_msec >= 1500:
				_fail("jump did not launch after its anticipation pose velocity_y=%.3f start_y=%.3f current_y=%.3f anticipation=%.3f grounded=%s" % [_player.velocity.y, _jump_start_y, _player.global_position.y, _player.jump_anticipation, str(_player.on_ground)])
			return false
		if _player.global_position.y <= _jump_start_y:
			return false
		if _player.animation_driver.animator.get_current_state() != BlockyHumanoidAnimator.JUMP:
			if Time.get_ticks_msec() - _jump_input_start_msec >= 1500:
				_fail("anticipated jump did not enter the jump animation state=%s velocity_y=%.3f grounded=%s anticipation=%.3f" % [str(_player.animation_driver.animator.get_current_state()), _player.velocity.y, str(_player.on_ground), _player.jump_anticipation])
			return false
		if not _verify_item_block_round_trip():
			return false
		print("[soak] starting streaming race at frame %d" % _frame)
		_phase = 4
	elif _phase == 4:
		_tick_soak()
		if _frame % 60 == 0:
			_log_soak()
			_assert_bounded()
			if not _errors.is_empty():
				return false
		if _movement_frames >= MOVEMENT_FRAMES:
			_phase = 5
	elif _phase == 5:
		_log_soak()
		_assert_bounded()
		_check_final()
		_phase = 6
	return false

func _tick_soak() -> void:
	if not _streaming_race_started:
		_start_streaming_race_sequence()
		return
	if not _streaming_race_verified:
		_player.global_position = _streaming_race_position
		var elapsed_msec := Time.get_ticks_msec() - _streaming_race_started_msec
		if _streaming_queues_are_drained():
			_verify_streaming_race_sequence()
		elif elapsed_msec > STREAMING_RACE_TIMEOUT_MSEC:
			var manager := _world.chunk_manager
			_fail(
				"streaming race queues did not drain elapsed=%dms pending=%d data_load=%d mesh_load=%d data_unload=%d requested_meshes=%d requested_terrain=%d rebuilding=%d" % [
					elapsed_msec,
					_world.chunk_scheduler.pending_count(),
					manager._data_load_queue.size(),
					manager._mesh_load_queue.size(),
					manager._data_unload_queue.size(),
					manager._requested_meshes.size(),
					manager._requested_terrain.size(),
					manager._rebuilding_meshes.size(),
				]
			)
		return
	var t: float = float(_frame) * 0.02
	var radius: float = 60.0 + 20.0 * sin(float(_frame) * 0.002)
	var x: float = _streaming_race_position.x + cos(t) * radius
	var z: float = _streaming_race_position.z + sin(t * 0.9) * radius
	var y: float = _player.global_position.y
	if _world and _world.voxel_model:
		var vm: VoxelWorld = _world.voxel_model
		if vm.height_map_dict.has(Vector2i(int(x), int(z))):
			var h = vm.height_map_dict[Vector2i(int(x), int(z))] as int
			y = float(h) + 2.5
		else:
			y = 12.0
	_player.global_position = Vector3(x, y, z)
	var do_mine: bool = _frame % 22 == 0
	var do_place: bool = _frame % 33 == 0
	if do_mine or do_place:
		_do_mine_place(do_mine, do_place)
	_movement_frames += 1

func _verify_texture_pipeline() -> bool:
	var texture_set := _world.block_texture_set
	if texture_set == null or texture_set.texture_array == null:
		_fail("block texture array missing")
		return false
	if _world.terrain_material.get_shader_parameter("terrain_textures") != texture_set.texture_array:
		_fail("terrain material texture array mismatch")
		return false
	var layer_count := texture_set.texture_array.get_layers()
	for block_id in range(BlockId.Type.COUNT):
		if not BlockId.is_chunk_cube(block_id):
			continue
		for layer in [texture_set.top_layers[block_id], texture_set.side_layers[block_id], texture_set.bottom_layers[block_id]]:
			if layer < 0 or layer >= layer_count:
				_fail("texture layer out of bounds for block %d" % block_id)
				return false
	var checked_mesh := false
	for instance in _world.chunk_renderer._terrain_instances.values():
		var terrain_instance := instance as MeshInstance3D
		var mesh := terrain_instance.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
		var layers := arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array
		if vertices.is_empty():
			continue
		if uvs.size() != vertices.size() or layers.size() != vertices.size():
			_fail("terrain texture attributes do not match vertex count")
			return false
		for index in range(0, layers.size(), 4):
			if index + 3 >= layers.size():
				_fail("terrain face texture layers are incomplete")
				return false
			if layers[index].x != layers[index + 1].x or layers[index].x != layers[index + 2].x or layers[index].x != layers[index + 3].x:
				_fail("terrain face texture layer is not constant")
				return false
		checked_mesh = true
		break
	if not checked_mesh:
		_fail("no terrain mesh available for texture verification")
		return false
	_texture_pipeline_verified = true
	return true

func _verify_side_face_ao() -> bool:
	for instance in _world.chunk_renderer._terrain_instances.values():
		var terrain_instance := instance as MeshInstance3D
		var mesh := terrain_instance.mesh as ArrayMesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var arrays := mesh.surface_get_arrays(0)
		var normals := arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		var colors := arrays[Mesh.ARRAY_COLOR] as PackedColorArray
		for index in range(0, normals.size(), 4):
			if index + 3 >= normals.size() or abs(normals[index].y) > 0.5:
				continue
			var first := colors[index].r
			if not is_equal_approx(colors[index + 1].r, first) or not is_equal_approx(colors[index + 2].r, first) or not is_equal_approx(colors[index + 3].r, first):
				return true
	_fail("no side-face ambient occlusion found")
	return false

func _verify_lighting_pipeline() -> bool:
	if int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")) < 2:
		_fail("directional shadow filtering quality is too low")
		return false
	if bool(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/16_bits")):
		_fail("directional shadows are using low-precision depth")
		return false
	if not bool(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_taa")):
		_fail("temporal antialiasing is disabled")
		return false
	var game_environment := _game.game_environment
	var world_environment := game_environment.get_node("WorldEnvironment") as WorldEnvironment
	var environment := world_environment.environment
	if environment.tonemap_mode != Environment.TONE_MAPPER_ACES:
		_fail("lighting pipeline is not using ACES tonemapping")
		return false
	if environment.adjustment_contrast > 1.1 or environment.adjustment_saturation > 1.1:
		_fail("lighting color grading is too aggressive")
		return false
	if environment.ssao_enabled:
		_fail("dynamic SSAO should be replaced by baked terrain AO")
		return false
	var sun := game_environment.get_node("Sun") as DirectionalLight3D
	var values := game_environment.get_node("DayNightValues") as DayNightValues
	var clock := game_environment.get_node("GameClock") as GameClock
	var sunset_start := values.profile.get_interpolated(17.0).sky
	var sunset_end := values.profile.get_interpolated(18.0).sky
	var sunset_quarter := values.profile.get_interpolated(17.25).sky
	if not sunset_quarter.is_equal_approx(sunset_start.lerp(sunset_end, 0.25)):
		_fail("sunset profile does not interpolate linearly")
		return false
	for hour in [0.0, 6.0, 12.0, 18.0]:
		values.apply(hour)
		if not is_equal_approx(sun.shadow_bias, 0.03):
			_fail("sun shadow depth bias changes with time")
			return false
	values.apply(clock.time_of_day)
	if sun.directional_shadow_mode != DirectionalLight3D.SHADOW_ORTHOGONAL:
		_fail("sun is not using stable orthogonal shadows")
		return false
	if sun.directional_shadow_max_distance > 128.01:
		_fail("sun shadow coverage is too broad for stable texel density")
		return false
	if sun.shadow_blur < 0.99:
		_fail("sun shadow filtering is too sharp")
		return false
	if not is_equal_approx(sun.shadow_bias, 0.03):
		_fail("sun shadow depth bias is not fixed at 0.03")
		return false
	if sun.shadow_normal_bias < 0.99 or sun.shadow_normal_bias > 1.61:
		_fail("sun shadow normal bias differs from the acne-free range")
		return false
	if not sun.shadow_reverse_cull_face:
		_fail("sun shadows are not using the acne-free reverse-face path")
		return false
	if not _world.terrain_material.shader.code.contains("cull_disabled"):
		_fail("terrain shadow casting differs from the acne-free baseline")
		return false
	var debug_panel := game_environment.get_node("DebugClockPanel") as DebugClockPanel
	var original_time := clock.time_of_day
	var debug_panel_was_visible := debug_panel.visible
	clock.set_time_of_day(12.345)
	debug_panel.visible = true
	debug_panel._update_ui()
	if not is_equal_approx(clock.time_of_day, 12.345):
		_fail("debug time display fed a rounded slider value back into the clock")
		return false
	debug_panel.visible = debug_panel_was_visible
	clock.set_time_of_day(original_time)
	var original_opacity := sun.shadow_opacity
	var original_bias := sun.shadow_bias
	var original_normal_bias := sun.shadow_normal_bias
	var original_blur := sun.shadow_blur
	var original_distance := sun.directional_shadow_max_distance
	var original_fade := sun.directional_shadow_fade_start
	debug_panel.opacity_slider.value = 0.42
	debug_panel.bias_slider.value = 0.077
	debug_panel.normal_bias_slider.value = 0.33
	debug_panel.blur_slider.value = 1.5
	debug_panel.distance_slider.value = 96.0
	debug_panel.fade_slider.value = 0.70
	debug_panel.reverse_cull.button_pressed = false
	debug_panel.shadow_enabled.button_pressed = false
	if not is_equal_approx(sun.shadow_opacity, 0.42) or not is_equal_approx(sun.shadow_bias, 0.077) or not is_equal_approx(sun.shadow_normal_bias, 0.33):
		_fail("live shadow bias controls are not applied")
		return false
	if not is_equal_approx(sun.shadow_blur, 1.5) or not is_equal_approx(sun.directional_shadow_max_distance, 96.0) or not is_equal_approx(sun.directional_shadow_fade_start, 0.70):
		_fail("live shadow coverage controls are not applied")
		return false
	if sun.shadow_reverse_cull_face or sun.shadow_enabled:
		_fail("live shadow toggle controls are not applied")
		return false
	debug_panel.reset_shadows.pressed.emit()
	if not is_equal_approx(sun.shadow_opacity, original_opacity) or not is_equal_approx(sun.shadow_bias, original_bias) or not is_equal_approx(sun.shadow_normal_bias, original_normal_bias):
		_fail("shadow reset did not restore profile values")
		return false
	if not is_equal_approx(sun.shadow_blur, original_blur) or not is_equal_approx(sun.directional_shadow_max_distance, original_distance) or not is_equal_approx(sun.directional_shadow_fade_start, original_fade):
		_fail("shadow reset did not restore coverage values")
		return false
	if not sun.shadow_reverse_cull_face or not sun.shadow_enabled:
		_fail("shadow reset did not restore toggles")
		return false
	var shadow_center := _world.chunk_manager._last_player_chunk
	var shadow_distance := _world.config.shadow_render_distance
	var shadow_casters := 0
	for coord in _world.chunk_renderer._terrain_instances:
		var instance := _world.chunk_renderer._terrain_instances[coord] as MeshInstance3D
		if instance.mesh == null:
			continue
		var offset := (coord as Vector2i) - shadow_center
		var should_cast := maxi(abs(offset.x), abs(offset.y)) <= shadow_distance
		var casts := instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts != should_cast:
			_fail("terrain chunk shadow radius mismatch")
			return false
		if casts:
			shadow_casters += 1
	var shadow_limit := (shadow_distance * 2 + 1) * (shadow_distance * 2 + 1)
	if shadow_casters > shadow_limit:
		_fail("too many terrain chunks cast dynamic shadows")
		return false
	for hour in [8.0, 12.0, 17.0]:
		var day_state := values.profile.get_interpolated(hour)
		if not is_equal_approx(day_state.sun_energy, 0.70):
			_fail("daytime sun energy mismatch")
			return false
	var noon := values.profile.get_interpolated(12.0)
	var noon_ambient := noon.ambient_energy
	var noon_sun := noon.sun_energy
	if not is_equal_approx(noon_ambient, 0.30) or not is_equal_approx(noon_sun, 0.70):
		_fail("noon lighting energy mismatch")
		return false
	var midnight := values.profile.get_interpolated(0.0)
	if noon_sun <= noon_ambient * 2.0:
		_fail("day lighting lacks directional contrast")
		return false
	if midnight.ambient_energy < 0.17 or midnight.sun_energy < 0.28:
		_fail("night lighting is below the visibility floor")
		return false
	var expected_ao: Array[float] = [1.0, 0.90, 0.78, 0.62]
	for index in range(expected_ao.size()):
		if not is_equal_approx(_world.chunk_mesher.ao_table[index], expected_ao[index]):
			_fail("terrain AO curve mismatch")
			return false
	_lighting_pipeline_verified = true
	return true

func _verify_item_block_round_trip() -> bool:
	var inventory := _game.inventory_model
	var grass_item := inventory.item_catalog.get_item_for_block(BlockId.Type.GRASS)
	var key_two := InputEventKey.new()
	key_two.keycode = KEY_2
	key_two.pressed = true
	root.push_input(key_two, true)
	if inventory.selected_slot != 1:
		_fail("hotbar key input did not select slot 1")
		return false
	var key_one := InputEventKey.new()
	key_one.keycode = KEY_1
	key_one.pressed = true
	root.push_input(key_one, true)
	if inventory.selected_slot != 0:
		_fail("hotbar key input did not restore slot 0")
		return false
	var before = inventory.get_slot(0)
	if before == null or before["item_id"] != grass_item.id:
		_fail("starter grass item missing")
		return false
	var before_count := int(before["count"])
	var voxel_world := _world.voxel_model
	var base_x := int(floor(_player.global_position.x))
	var base_z := int(floor(_player.global_position.z))
	var placement: Variant = null
	for offset in range(2, 9):
		var x := base_x + offset
		var y := voxel_world.get_highest_solid_y(x, base_z) + 1
		var candidate := Vector3i(x, y, base_z)
		if voxel_world.get_block_id_at(candidate) == BlockId.Type.AIR:
			placement = candidate
			break
	if placement == null:
		_fail("no position available for item round trip")
		return false
	var placed_pos := placement as Vector3i
	_player.interactor._commit_place(placed_pos)
	if voxel_world.get_block_id_at(placed_pos) != BlockId.Type.GRASS:
		_fail("selected item did not place grass block")
		return false
	if not _player.animation_driver.animator._placing:
		_fail("successful placement did not trigger player animation")
		return false
	if int(inventory.get_slot(0)["count"]) != before_count - 1:
		_fail("placing block did not consume item")
		return false
	_player.interactor._commit_mine(placed_pos)
	if voxel_world.get_block_id_at(placed_pos) != BlockId.Type.AIR:
		_fail("placed grass block was not mined")
		return false
	if int(inventory.get_slot(0)["count"]) != before_count:
		_fail("mined block did not restore grass item")
		return false
	_item_round_trip_verified = true
	return true

func _verify_sprint_input() -> bool:
	var planar_speed = Vector2(_player.velocity.x, _player.velocity.z).length()
	var sprint_state = _player.animation_driver.animator.get_current_state()
	var sprint_active = _player.is_sprinting
	_push_key(KEY_SHIFT, false)
	_push_key(KEY_W, false)
	if not sprint_active:
		_fail("shift movement input did not activate sprinting")
		return false
	if not is_equal_approx(planar_speed, _player.sprint_speed):
		_fail("sprint speed mismatch %.3f expected %.3f" % [planar_speed, _player.sprint_speed])
		return false
	if sprint_state != BlockyHumanoidAnimator.SPRINT:
		_fail("shift movement input did not enter sprint animation")
		return false
	if not is_equal_approx(_game.camera_rig.camera.size, _sprint_camera_size):
		_fail("shift sprint input changed camera zoom")
		return false
	return true

func _push_key(keycode: Key, pressed: bool):
	var event = InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	root.push_input(event, true)

func _start_streaming_race_sequence() -> void:
	_streaming_race_started = true
	var vm := _world.voxel_model
	var surface_x := int(floor(_player.global_position.x))
	var surface_z := int(floor(_player.global_position.z))
	var edit_pos := Vector3i(surface_x, vm.get_highest_solid_y(surface_x, surface_z) + 1, surface_z)
	var edit := vm.try_place_block(edit_pos, BlockId.Type.DIRT)
	if not edit.is_success():
		_fail("streaming race edit failed at %s" % str(edit_pos))
		return
	_edited_chunk = ChunkCoord.world_to_chunk_vec3i(edit_pos, _world.config.chunk_size)
	_world.chunk_manager.tick(_player.global_position)
	var span := float(_world.config.chunk_size * (_world.config.render_distance + _world.config.unload_padding + 3))
	var targets: Array[Vector3] = [
		Vector3(span, 24.0, 0.0),
		Vector3(-span, 24.0, span),
		Vector3(span, 24.0, -span),
		Vector3(span * 2.0, 24.0, span * 2.0),
	]
	for target in targets:
		_world.chunk_manager.tick(target)
	_streaming_race_position = targets[-1]
	_player.global_position = _streaming_race_position
	if _world.chunk_renderer._mesh_cache.has(_edited_chunk):
		_fail("edited chunk entered cache after cancellation")
		return
	_streaming_race_started_msec = Time.get_ticks_msec()

func _streaming_queues_are_drained() -> bool:
	var manager := _world.chunk_manager
	return (
		_world.chunk_scheduler.pending_count() == 0
		and manager._data_load_queue.is_empty()
		and manager._mesh_load_queue.is_empty()
		and manager._data_unload_queue.is_empty()
		and manager._requested_meshes.is_empty()
		and manager._requested_terrain.is_empty()
		and manager._rebuilding_meshes.is_empty()
	)

func _verify_streaming_race_sequence() -> void:
	var manager := _world.chunk_manager
	for coord in manager.data_chunks.keys():
		if not manager._keep_set.has(coord):
			_fail("data chunk outside keep set after rapid teleport: %s" % str(coord))
			return
	if _world.chunk_renderer._mesh_cache.has(_edited_chunk):
		_fail("stale edited mesh was cached after unload")
		return
	var vm := _world.voxel_model
	var eviction_target: Variant = null
	for coord in _world.chunk_renderer._mesh_cache.keys():
		if vm.generated_terrain_chunks.has(coord):
			eviction_target = coord
			break
	if eviction_target == null:
		_fail("no cached generated chunk available for eviction check")
		return
	var target := eviction_target as Vector2i
	var reordered_lru: Dictionary = {target: true}
	vm._terrain_lru_mutex.lock()
	for coord in vm._terrain_chunk_lru.keys():
		if coord != target:
			reordered_lru[coord] = true
	vm._terrain_chunk_lru = reordered_lru
	vm._terrain_lru_mutex.unlock()
	var previous_limit := vm.max_terrain_cache_chunks
	vm.max_terrain_cache_chunks = reordered_lru.size() - 1
	_forced_evictions.clear()
	vm.terrain_chunk_evicted.connect(_on_forced_terrain_evicted)
	var eviction_count := vm.prune_terrain_cache(1)
	vm.terrain_chunk_evicted.disconnect(_on_forced_terrain_evicted)
	vm.max_terrain_cache_chunks = previous_limit
	if eviction_count != 1 or _forced_evictions != [target]:
		_fail("forced terrain eviction did not remove target %s: %s" % [str(target), str(_forced_evictions)])
		return
	if vm.generated_terrain_chunks.has(target) or _world.chunk_renderer._mesh_cache.has(target):
		_fail("terrain eviction retained data or cached mesh for %s" % str(target))
		return
	_streaming_race_verified = true
	print("[soak] streaming race sequence passed at frame %d elapsed=%dms" % [_frame, Time.get_ticks_msec() - _streaming_race_started_msec])

func _on_forced_terrain_evicted(coord: Vector2i) -> void:
	_forced_evictions.append(coord)

func _do_mine_place(do_mine: bool, do_place: bool) -> void:
	if _world == null or _world.voxel_model == null:
		return
	var vm: VoxelWorld = _world.voxel_model
	var base: Vector3i = Vector3i(int(floor(_player.global_position.x)), int(floor(_player.global_position.y)) - 1, int(floor(_player.global_position.z)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var p = base + Vector3i(dx, 0, dz)
			if do_mine and vm.is_breakable(p):
				var edits: Array = vm.try_mine_block(p)
				if not edits.is_empty():
					_mine_place_count += 1
					break
			if do_place:
				var above = p + Vector3i(0, 1, 0)
				if not vm.is_occupied(above) and vm.is_occupied(p):
					var edit: BlockEdit = vm.try_place_block(above, BlockId.Type.DIRT)
					if edit != null and edit.is_success():
						_mine_place_count += 1
						break
		if _mine_place_count > 0 and _frame % 33 == 0:
			break

func _log_soak() -> void:
	var data_chunks: int = 0
	var visible_chunks: int = 0
	var terrain_chunks: int = 0
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var node_count: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	if _world and _world.chunk_manager:
		data_chunks = _world.chunk_manager.data_chunks.size()
		visible_chunks = _world.chunk_manager.visible_chunks.size()
	if _world and _world.voxel_model:
		terrain_chunks = _world.voxel_model.generated_terrain_chunks.size()
	_max_data_chunks = max(_max_data_chunks, data_chunks)
	_max_visible_chunks = max(_max_visible_chunks, visible_chunks)
	_max_terrain_chunks = max(_max_terrain_chunks, terrain_chunks)
	_max_orphan = max(_max_orphan, orphan)
	if _frame - _last_log_frame >= 60:
		_last_log_frame = _frame
		var elapsed: int = Time.get_ticks_msec() - _start_msec
		print("[soak] frame %d elapsed %d ms pos %s data %d vis %d terrain %d orphan %d nodes %d edits %d" % [_frame, elapsed, str(_player.global_position), data_chunks, visible_chunks, terrain_chunks, orphan, node_count, _mine_place_count])

func _assert_bounded() -> void:
	var cfg: WorldConfig = _world.config if _world else null
	var render_dist: int = cfg.render_distance if cfg else 4
	var unload_pad: int = cfg.unload_padding if cfg else 2
	var keep_dist: int = render_dist + unload_pad
	var keep_area: int = (keep_dist * 2 + 1) * (keep_dist * 2 + 1)
	var visible_area: int = (render_dist * 2 + 1) * (render_dist * 2 + 1)
	var data_limit: int = keep_area + 40
	var terrain_limit: int = keep_area * 3 + 260
	var visible_limit: int = visible_area + 10
	var data_chunks: int = _world.chunk_manager.data_chunks.size() if _world and _world.chunk_manager else 0
	var visible_chunks: int = _world.chunk_manager.visible_chunks.size() if _world and _world.chunk_manager else 0
	var terrain_chunks: int = _world.voxel_model.generated_terrain_chunks.size() if _world and _world.voxel_model else 0
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	if data_chunks > keep_area + 20:
		_warn("data_chunks high %d keep=%d" % [data_chunks, keep_area])
	if data_chunks > data_limit:
		_fail("data_chunks unbounded %d > %d keep=%d" % [data_chunks, data_limit, keep_area])
		return
	if visible_chunks > visible_area + 5:
		_warn("visible_chunks high %d" % visible_chunks)
	if visible_chunks > visible_limit:
		_fail("visible_chunks unbounded %d > %d" % [visible_chunks, visible_limit])
		return
	if terrain_chunks > keep_area * 2 + 200:
		_warn("terrain_chunks high %d" % terrain_chunks)
	if terrain_chunks > terrain_limit:
		_fail("terrain_chunks unbounded %d > %d" % [terrain_chunks, terrain_limit])
		return
	if orphan != 0:
		_warn("orphan nodes %d at frame %d" % [orphan, _frame])
		_fail("orphan nodes %d at frame %d" % [orphan, _frame])
		return
	var previews: Array = []
	_find_drag_previews(root, previews)
	if not previews.is_empty():
		_warn("leaked DragPreview during soak %s" % str(previews))
		_fail("leaked DragPreview during soak %s" % str(previews))
		return
	if _world and _world.chunk_scheduler:
		var async_pending: int = _world.chunk_scheduler.pending_count()
		var pending_limit: int = keep_area + 20
		if async_pending > keep_area:
			_warn("async_pending high %d" % async_pending)
		if async_pending > pending_limit:
			_fail("async_pending unbounded %d > %d" % [async_pending, pending_limit])
			return

func _find_drag_previews(node: Node, out: Array) -> void:
	if node.name.contains("DragPreview"):
		out.append(node)
	for c in node.get_children():
		_find_drag_previews(c, out)

func _check_final() -> void:
	if _done:
		return
	_done = true
	print("[soak] final frame %d movement_frames=%d elapsed %d ms" % [_frame, _movement_frames, Time.get_ticks_msec() - _start_msec])
	_log_soak()
	print("[soak] max data %d vis %d terrain %d orphan %d edits %d" % [_max_data_chunks, _max_visible_chunks, _max_terrain_chunks, _max_orphan, _mine_place_count])
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var previews: Array = []
	_find_drag_previews(root, previews)
	if orphan != 0:
		_fail("final orphan %d" % orphan)
		return
	if not previews.is_empty():
		_fail("final leaked preview %s" % str(previews))
		return
	if not _streaming_race_verified:
		_fail("streaming race sequence was not verified")
		return
	if not _texture_pipeline_verified or not _lighting_pipeline_verified or not _item_round_trip_verified:
		_fail("texture, lighting, or item round-trip verification missing")
		return
	if _world:
		_world.shutdown()
	if _errors.is_empty():
		print("SOAK PASS frames=%d movement_frames=%d data_max=%d vis_max=%d terrain_max=%d orphan_max=%d edits=%d" % [_frame, _movement_frames, _max_data_chunks, _max_visible_chunks, _max_terrain_chunks, _max_orphan, _mine_place_count])
		quit(0)
	else:
		print("SOAK FAIL %s" % str(_errors))
		quit(1)

func _warn(msg: String) -> void:
	print("[soak] %s" % msg)

func _error(msg: String) -> void:
	print("[soak] ERROR: %s" % msg)

func _fail(msg: String) -> void:
	_error(msg)
	print("FAIL: %s" % msg)
	_errors.append(msg)
	quit(1)

func _on_session_ready():
	_session_ready = true
