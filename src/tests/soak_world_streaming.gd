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
var _streaming_race_wait_frames: int = 0
var _streaming_race_position: Vector3
var _edited_chunk: Vector2i
var _forced_evictions: Array[Vector2i] = []

const SOAK_FRAMES: int = 900

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
		_game.configure_session(-1, {"seed": 1337})
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
		if _frame % 30 == 0:
			print("[soak] waiting gen frame %d orphan=%d" % [_frame, int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
		if _session_ready:
			print("[soak] world generated at frame %d" % _frame)
			if _world.voxel_model == null or _world.chunk_manager == null or _world.chunk_renderer == null:
				_fail("world not fully generated voxel=%s manager=%s renderer=%s" % [str(_world.voxel_model != null), str(_world.chunk_manager != null), str(_world.chunk_renderer != null)])
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
		print("[soak] starting soak movement at frame %d" % _frame)
		_phase = 4
	elif _phase == 4:
		_tick_soak()
		if _frame % 60 == 0:
			_log_soak()
			_assert_bounded()
			if not _errors.is_empty():
				return false
		if _frame >= 180 + SOAK_FRAMES:
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
		_streaming_race_wait_frames += 1
		var keep_distance := _world.config.render_distance + _world.config.unload_padding
		var keep_area := (keep_distance * 2 + 1) * (keep_distance * 2 + 1)
		if _streaming_queues_are_drained():
			_verify_streaming_race_sequence()
		elif _streaming_race_wait_frames > keep_area * 5:
			_fail("streaming race queues did not drain")
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
	print("[soak] streaming race sequence passed at frame %d" % _frame)

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
	print("[soak] final frame %d elapsed %d ms" % [_frame, Time.get_ticks_msec() - _start_msec])
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
	if _world:
		_world.shutdown()
	if _errors.is_empty():
		print("SOAK PASS frames=%d data_max=%d vis_max=%d terrain_max=%d orphan_max=%d edits=%d" % [_frame, _max_data_chunks, _max_visible_chunks, _max_terrain_chunks, _max_orphan, _mine_place_count])
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
