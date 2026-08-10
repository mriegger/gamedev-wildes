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
	_expect(footsteps._streams.size() == 9, "footstep streams expected 9 got %d" % footsteps._streams.size())
	for s in footsteps._streams:
		_expect(s != null, "null stream in footsteps")

	footsteps.setup(player)
	await process_frame
	_expect(asp.stream != null, "setup didn't assign stream")

	var last = -1
	var repeated = false
	for i in range(30):
		footsteps._last_idx = last
		footsteps._play_step()
		if footsteps._last_idx == last and footsteps._streams.size() > 1 and last != -1:
			repeated = true
		_expect(asp.pitch_scale >= 0.92 and asp.pitch_scale <= 1.08, "footstep pitch out of range %f" % asp.pitch_scale)
		last = footsteps._last_idx
	_expect(not repeated, "footstep repeated same idx immediate")

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
	footsteps._process(0.32)
	_expect(footsteps._step_timer > 0.0, "walk should not yet trigger at 0.32")
	footsteps._process(0.01)
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "walk should trigger at 0.33 and reset")

	player.is_sprinting = true
	footsteps._step_timer = 0.0
	footsteps._process(0.22)
	_expect(footsteps._step_timer > 0.0, "sprint should not trigger at 0.22")
	footsteps._process(0.02)
	_expect(is_equal_approx(footsteps._step_timer, 0.0), "sprint should trigger at 0.24")

	var before_count = _count_nodes(root)
	player.velocity = Vector3(5.5, 0, 0)
	player.on_ground = true
	footsteps._step_timer = 0.32
	footsteps._process(0.1)
	_expect(_count_nodes(root) == before_count, "footstep _process leaked nodes")

	player.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish", "AUDIO_FOOTSTEPS")
