extends SceneTree

var _failures: int = 0


func _init():
	call_deferred(&"_run")


func _expect(condition: bool, message: String):
	if condition:
		return
	_failures += 1
	push_error("[zombie_vocalizations_integration] FAIL: %s" % message)


func _run():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(8, 16, 3, 4.0, block_catalog)
	var camera_rig := (load("res://player/camera/camera_rig.tscn") as PackedScene).instantiate() as CameraRig
	get_root().add_child(camera_rig)
	var listener := camera_rig.get_node_or_null(^"AudioListener3D") as AudioListener3D
	_expect(listener != null, "camera audio listener missing")
	_expect(listener.is_current(), "camera audio listener was not current")
	_expect(listener.get_parent() == camera_rig, "audio listener was not centered on the camera rig")
	var listener_forward := -listener.global_transform.basis.z
	camera_rig.rotation_degrees.y += 45.0
	var rotated_listener_forward := -listener.global_transform.basis.z
	_expect(listener_forward.dot(rotated_listener_forward) < 0.9, "audio listener did not follow camera yaw")
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var definition := entity_catalog.get_definition(&"zombie")
	var actor := definition.actor_scene.instantiate() as ZombieActor
	get_root().add_child(actor)
	actor.setup(7, definition, world, 12345, EntityNavigationLimits.new(24, 256, 1))
	var vocalizations := actor.get_node_or_null(actor.vocalizations_path) as EntityVocalizations
	_expect(vocalizations != null, "zombie vocalizations missing")
	var profile := vocalizations.profile
	_expect(profile != null and profile.validate(), "zombie vocalization profile invalid")
	_expect(vocalizations.bus == &"SFX", "vocalizations bus was %s" % vocalizations.bus)
	_expect(is_equal_approx(vocalizations.volume_db, -6.0), "vocalizations volume was %.2f" % vocalizations.volume_db)
	_expect(is_equal_approx(vocalizations.unit_size, 4.0), "vocalizations unit size was %.2f" % vocalizations.unit_size)
	_expect(is_equal_approx(vocalizations.max_distance, 26.0), "vocalizations max distance was %.2f" % vocalizations.max_distance)
	_expect(profile.streams.size() == 6, "expected 6 vocalizations, got %d" % profile.streams.size())
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
	_expect(not vocalizations.is_processing(), "death vocalization retained ambient scheduling")
	_expect(vocalizations.playing, "zombie death did not play a vocalization")
	_expect(profile.streams.has(vocalizations.stream), "zombie death selected audio outside its vocalization profile")
	var visual_retirement_seconds := ZombieAnimationDriver.DEATH_SECONDS + maxf(
		actor.visual_fader.fade_out_seconds,
		actor.death_poof.lifetime,
	)
	_expect(not actor.advance_retirement(visual_retirement_seconds), "zombie retired while its death vocalization was playing")
	vocalizations.stop()
	_expect(actor.advance_retirement(0.0), "zombie did not finish retirement after its death vocalization stopped")
	actor.queue_free()
	camera_rig.queue_free()
	for _frame_index in range(10):
		await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "vocalization test ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("ZOMBIE_VOCALIZATIONS PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("ZOMBIE_VOCALIZATIONS FAIL failures=%d" % _failures)
		quit(1)
