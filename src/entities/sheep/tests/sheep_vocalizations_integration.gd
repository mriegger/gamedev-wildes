extends SceneTree

var _failures: int = 0


func _init():
	call_deferred(&"_run")


func _expect(condition: bool, message: String):
	if condition:
		return
	_failures += 1
	push_error("[sheep_vocalizations_integration] FAIL: %s" % message)


func _run():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(8, 16, 3, 4.0, block_catalog)
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var definition := entity_catalog.get_definition(&"sheep")
	var actor := definition.actor_scene.instantiate() as SheepActor
	get_root().add_child(actor)
	actor.setup(11, definition, world, 24680, EntityNavigationLimits.new(24, 256, 1))
	var vocalizations := actor.get_node_or_null(actor.vocalizations_path) as EntityVocalizations
	_expect(vocalizations != null, "sheep vocalizations missing")
	var profile := vocalizations.profile
	_expect(profile != null and profile.validate(), "sheep vocalization profile invalid")
	_expect(vocalizations.bus == &"SFX", "vocalizations bus was %s" % vocalizations.bus)
	_expect(is_equal_approx(vocalizations.volume_db, -10.0), "vocalizations volume was %.2f" % vocalizations.volume_db)
	_expect(is_equal_approx(vocalizations.unit_size, 3.5), "vocalizations unit size was %.2f" % vocalizations.unit_size)
	_expect(is_equal_approx(vocalizations.max_distance, 24.0), "vocalizations max distance was %.2f" % vocalizations.max_distance)
	_expect(profile.streams.size() == 7, "expected 7 vocalizations, got %d" % profile.streams.size())
	for stream in profile.streams:
		_expect(stream != null, "vocalization stream was null")
	_expect(
		vocalizations._remaining_seconds >= profile.initial_delay_min_seconds
		and vocalizations._remaining_seconds <= profile.initial_delay_max_seconds,
		"initial delay was %.2f" % vocalizations._remaining_seconds,
	)

	vocalizations._remaining_seconds = 0.0
	vocalizations._process(0.0)
	_expect(profile.streams.has(vocalizations.stream), "due vocalization did not select a stream")
	_expect(
		vocalizations.pitch_scale >= profile.pitch_min
		and vocalizations.pitch_scale <= profile.pitch_max,
		"vocalization pitch was %.3f" % vocalizations.pitch_scale,
	)
	_expect(
		vocalizations._remaining_seconds >= profile.interval_min_seconds
		and vocalizations._remaining_seconds <= profile.interval_max_seconds,
		"next interval was %.2f" % vocalizations._remaining_seconds,
	)
	var first_index := vocalizations._last_stream_index
	vocalizations.stop()
	vocalizations._remaining_seconds = 0.0
	vocalizations._process(0.0)
	_expect(vocalizations._last_stream_index != first_index, "vocalization immediately repeated")
	var active_stream := vocalizations.stream
	var active_interval := vocalizations._remaining_seconds
	vocalizations._process(active_interval + 1.0)
	_expect(vocalizations.stream == active_stream, "active vocalization was replaced")
	_expect(is_equal_approx(vocalizations._remaining_seconds, active_interval), "active vocalization consumed its silence interval")

	actor.begin_death_retirement()
	_expect(not vocalizations.is_processing(), "vocalizations kept processing during death")
	_expect(vocalizations.playing, "death did not start a vocalization")
	_expect(profile.streams.has(vocalizations.stream), "death did not select a configured vocalization")
	actor.begin_despawn_fade()
	_expect(not vocalizations.is_processing(), "vocalizations kept processing during despawn")
	_expect(not vocalizations.playing, "vocalizations kept playing during despawn")
	_expect(vocalizations.stream == null, "vocalization stream remained assigned during despawn")
	actor.queue_free()
	for _frame_index in range(10):
		await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "vocalization test ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("SHEEP_VOCALIZATIONS PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("SHEEP_VOCALIZATIONS FAIL failures=%d" % _failures)
		quit(1)
