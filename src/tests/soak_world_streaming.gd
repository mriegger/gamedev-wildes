extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _game: Game = null
var _world: WorldController = null
var _player: PlayerMotor = null
var _hud: HUD = null
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

const SOAK_FRAMES: int = 900
const MOVE_SPEED: float = 18.0
const CHUNK_SIZE: int = 20

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
		_game.current_save_data = {}
		_game.current_slot_id = -1
		var world_node: WorldController = _game.get_node_or_null("World") as WorldController
		if world_node:
			world_node.auto_generate_on_ready = true
			world_node.seed_override = 1337
			world_node.pending_save_data = {}
			if world_node.config == null:
				world_node._ensure_config_loaded()
			if world_node.config:
				world_node.config = world_node.config.duplicate() as WorldConfig
				world_node.config.seed_value = 1337
				var jitter = RandomNumberGenerator.new()
				jitter.seed = 1337
				world_node.config.base_height = 8.5 + jitter.randf_range(-0.8, 1.5)
				world_node.config.meadow_radius = 22.0 + jitter.randf_range(-2.0, 6.0)
				world_node.config.tree_density = 0.01 + jitter.randf_range(-0.003, 0.008)
				world_node.config.continentalness_frequency = clamp(0.0018 + jitter.randf_range(-0.0004, 0.0006), 0.0005, 0.01)
				world_node.config.erosion_frequency = clamp(0.0045 + jitter.randf_range(-0.001, 0.0015), 0.001, 0.015)
				world_node.config.peaks_valleys_frequency = clamp(0.018 + jitter.randf_range(-0.003, 0.004), 0.005, 0.04)
		root.add_child(_game)
		print("[soak] game added frame %d" % _frame)
		_phase = 1
	elif _phase == 1 and _frame == 10:
		_world = _game.get_node_or_null("World") as WorldController
		_player = _game.get_node_or_null("Player") as PlayerMotor
		_hud = _game.get_node_or_null("HUD") as HUD
		if _world == null or _player == null:
			_fail("world or player null after add")
			return false
		print("[soak] waiting for world generation has_generated=%s" % str(_world._has_generated))
		_phase = 2
	elif _phase == 2:
		if _frame % 30 == 0:
			print("[soak] waiting gen frame %d has_generated=%s orphan=%d" % [_frame, str(_world._has_generated) if _world else "null", int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])
		if _world and _world._has_generated:
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
	var t: float = float(_frame) * 0.02
	var radius: float = 60.0 + 20.0 * sin(float(_frame) * 0.002)
	var x: float = cos(t) * radius
	var z: float = sin(t * 0.9) * radius
	var y: float = _player.global_position.y
	if _world and _world.voxel_model:
		var vm: VoxelWorld = _world.voxel_model
		var key = Vector2i(int(floor(x / float(CHUNK_SIZE))), int(floor(z / float(CHUNK_SIZE))))
		if vm.height_map_dict.has(Vector2i(int(x), int(z))):
			var h = vm.height_map_dict[Vector2i(int(x), int(z))] as int
			y = float(h) + 2.5
		else:
			y = 12.0
	_player.global_position = Vector3(x, y, z)
	if _world and _world.chunk_manager and _player:
		_world.chunk_manager.tick(0.016, _player.global_position)
	var do_mine: bool = _frame % 22 == 0
	var do_place: bool = _frame % 33 == 0
	if do_mine or do_place:
		_do_mine_place(do_mine, do_place)

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
	if _world and _world.chunk_renderer:
		var async_pending: int = _world.chunk_renderer._async_pending.size() if "_async_pending" in _world.chunk_renderer else 0
		if async_pending > 100:
			_warn("async_pending high %d" % async_pending)
		if async_pending > 150:
			_fail("async_pending unbounded %d" % async_pending)
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
	if _world and _world.chunk_manager:
		_world.chunk_manager.shutdown()
	if _world and _world.chunk_renderer:
		_world.chunk_renderer.shutdown()
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
