extends SceneTree

var _errors: Array[String] = []
var _orphan_before: int = 0

func _init():
	print("[audio_action] starting")
	_orphan_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	call_deferred("_run")

func _expect(cond: bool, msg: String):
	if not cond:
		_errors.append(msg)
		print("[audio_action] FAIL: %s" % msg)

func _finish(marker: String):
	var orphan_after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d" % orphan_after)
	if _errors.is_empty():
		print("%s PASS orphan=%d" % [marker, orphan_after])
		quit(0)
	else:
		print("%s FAIL %s" % [marker, str(_errors)])
		quit(1)

func _run():
	var packed = load("res://player/player.tscn") as PackedScene
	_expect(packed != null, "player.tscn load failed")
	var player = packed.instantiate() as PlayerMotor
	root.add_child(player)
	await process_frame

	var interactor = player.interactor as PlayerInteractor
	var action_audio = player.get_node_or_null("ActionAudio")
	_expect(action_audio != null, "ActionAudio node missing")
	var clunk = action_audio.get_node_or_null("ClunkPlayer") as AudioStreamPlayer
	_expect(clunk != null, "ClunkPlayer missing")
	_expect(clunk.bus == &"SFX", "clunk bus not SFX is %s" % clunk.bus)
	_expect(action_audio._streams.size() == 4, "clunk streams expected 4 got %d" % action_audio._streams.size())

	action_audio.setup(interactor)
	await process_frame

	var has_mining = false
	var has_melee = false
	for c in interactor.mining_hit.get_connections():
		if c["callable"].get_object() == action_audio:
			has_mining = true
	for c in interactor.melee_terrain_hit.get_connections():
		if c["callable"].get_object() == action_audio:
			has_melee = true
	_expect(has_mining, "mining_hit not connected to action audio")
	_expect(has_melee, "melee_terrain_hit not connected")

	action_audio._on_mining_hit(Vector3i.ZERO, 0, null)
	await process_frame
	_expect(clunk.stream != null, "clunk stream null after mining_hit")
	_expect(abs(clunk.volume_db - (-6.0)) < 0.1, "mining clunk vol expected -6 got %f" % clunk.volume_db)
	_expect(clunk.pitch_scale >= 0.95 and clunk.pitch_scale <= 1.07, "mining pitch out of range %f" % clunk.pitch_scale)

	action_audio._on_melee_terrain_hit(Vector3i(1,2,3))
	await process_frame
	_expect(abs(clunk.volume_db - (-4.0)) < 0.1, "melee clunk vol expected -4 got %f" % clunk.volume_db)

	var before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for i in range(50):
		action_audio._play_clunk(-6.0)
	var after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(before == after, "clunk spam leaked orphan before %d after %d" % [before, after])

	player.queue_free()
	await process_frame
	await process_frame
	_finish("AUDIO_ACTION")
