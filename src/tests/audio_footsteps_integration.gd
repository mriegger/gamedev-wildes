extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[audio_footsteps] starting")
	call_deferred("_run")

func _expect(cond: bool, msg: String):
	if not cond:
		_errors.append(msg)
		print("[audio_footsteps] FAIL: %s" % msg)

func _finish(marker: String):
	var orphan_after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d" % orphan_after)
	if _errors.is_empty():
		print("%s PASS orphan=%d" % [marker, orphan_after])
		quit(0)
	else:
		print("%s FAIL %s" % [marker, str(_errors)])
		quit(1)

func _count_nodes(n: Node) -> int:
	var c = 1
	for child in n.get_children():
		c += _count_nodes(child)
	return c

func _run():
	var packed = load("res://player/player.tscn") as PackedScene
	_expect(packed != null, "player.tscn load failed")
	var player = packed.instantiate() as PlayerMotor
	root.add_child(player)
	await process_frame

	var footsteps = player.get_node_or_null("Footsteps")
	_expect(footsteps != null, "Footsteps node missing in player.tscn")
	var asp = footsteps.get_node_or_null("FootstepPlayer") as AudioStreamPlayer
	_expect(asp != null, "FootstepPlayer missing")
	_expect(asp.bus == &"SFX", "footstep bus not SFX is %s" % asp.bus)
	_expect(abs(asp.volume_db - (-8.0)) < 0.1, "footstep volume not -8dB got %f" % asp.volume_db)
	_expect(footsteps._dirt_streams.size() == 9, "dirt footstep streams expected 9 got %d" % footsteps._dirt_streams.size())
	_expect(footsteps._water_streams.size() == 8, "water footstep streams expected 8 got %d" % footsteps._water_streams.size())
	for stream in footsteps._dirt_streams + footsteps._water_streams:
		_expect(stream != null, "null stream in footsteps")

	var profile = player.animation_driver.animator.profile
	footsteps.setup(player, profile)
	await process_frame
	_expect(asp.stream != null, "setup didn't assign stream")

	var last_stream: AudioStream
	var repeated = false
	for i in range(30):
		footsteps._play_step()
		if asp.stream == last_stream and last_stream != null:
			repeated = true
		_expect(asp.pitch_scale >= 0.92 and asp.pitch_scale <= 1.08, "footstep pitch out of range %f" % asp.pitch_scale)
		last_stream = asp.stream
	_expect(not repeated, "footstep repeated same idx immediate")

	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var voxel_world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var water_cell := Vector3i(0, 1, 0)
	voxel_world.restore_block_edits({water_cell: BlockId.Type.WATER}, {})
	player.voxel_world = voxel_world
	player.global_position = Vector3(0.5, 1.0, 0.5)
	_expect(player.is_in_water(), "player did not detect water at feet")
	footsteps._play_step()
	_expect(footsteps._water_streams.has(asp.stream), "water did not select a water footstep")
	player.global_position = Vector3(1.5, 1.0, 0.5)
	_expect(not player.is_in_water(), "player detected water in a dry feet cell")
	footsteps._play_step()
	_expect(footsteps._dirt_streams.has(asp.stream), "dry ground did not select a dirt footstep")

	player.on_ground = false
	player.velocity = Vector3(0.0, -4.0, 0.0)
	footsteps._step_timer = 0.32
	asp.stop()
	player.global_position = Vector3(0.5, 1.0, 0.5)
	footsteps._process(0.1)
	_expect(asp.playing, "entering water did not play a splash")
	_expect(footsteps._water_streams.has(asp.stream), "water entry splash did not use a water footstep")
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "water entry splash did not reset the footstep timer")
	asp.stop()
	footsteps._process(0.1)
	_expect(not asp.playing, "remaining in water replayed the entry splash")
	player.global_position = Vector3(1.5, 1.0, 0.5)
	footsteps._process(0.1)
	player.global_position = Vector3(0.5, 1.0, 0.5)
	footsteps._process(0.1)
	_expect(asp.playing, "re-entering water did not play another splash")

	player.on_ground = false
	player.velocity = Vector3(5.5, 0, 0)
	footsteps._step_timer = 0.32
	footsteps._process(0.1)
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "timer not reset when not on_ground")

	player.on_ground = true
	player.velocity = Vector3(0.1, 0, 0.1)
	footsteps._step_timer = 0.32
	footsteps._process(0.1)
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "timer not reset when planar <0.2")

	player.on_ground = true
	player.velocity = Vector3(5.5, 0, 0)
	player.is_sprinting = false
	footsteps._step_timer = 0.0
	var walk_interval = profile.walk_cycle_seconds * 0.5
	footsteps._process(walk_interval - 0.01)
	_expect(footsteps._step_timer > 0.0, "walk triggered before profile contact interval")
	footsteps._process(0.02)
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "walk did not trigger at profile contact interval")

	player.is_sprinting = true
	footsteps._step_timer = 0.0
	var sprint_interval = profile.sprint_cycle_seconds * 0.5
	footsteps._process(sprint_interval - 0.01)
	_expect(footsteps._step_timer > 0.0, "sprint triggered before profile contact interval")
	footsteps._process(0.02)
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "sprint did not trigger at profile contact interval")

	var before_count = _count_nodes(root)
	player.velocity = Vector3(5.5, 0, 0)
	player.on_ground = true
	footsteps._step_timer = 0.32
	footsteps._process(0.1)
	_expect(_count_nodes(root) == before_count, "footstep _process leaked nodes")

	player.voxel_world = null
	voxel_world = null
	block_catalog = null
	player.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish", "AUDIO_FOOTSTEPS")
