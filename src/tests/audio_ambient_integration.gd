extends SceneTree

var _errors: Array[String] = []
var _orphan_before: int = 0

func _init():
	print("[audio_ambient] starting")
	_orphan_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	call_deferred("_run")

func _expect(cond: bool, msg: String):
	if not cond:
		_errors.append(msg)
		print("[audio_ambient] FAIL: %s" % msg)

func _finish(marker: String):
	var orphan_after = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d before %d" % [orphan_after, _orphan_before])
	if _errors.is_empty():
		print("%s PASS orphan=%d" % [marker, orphan_after])
		quit(0)
	else:
		print("%s FAIL %s" % [marker, str(_errors)])
		quit(1)

func _run():
	# Bus layout
	_expect(AudioServer.get_bus_index("Master") != -1, "Master bus missing")
	_expect(AudioServer.get_bus_index("SFX") != -1, "SFX bus missing")
	_expect(AudioServer.get_bus_index("Ambient") != -1, "Ambient bus missing")

	var packed = load("res://environment/ambient/ambient_soundscape.tscn") as PackedScene
	_expect(packed != null, "ambient_soundscape.tscn load failed")
	var amb = packed.instantiate() as AmbientSoundscape
	root.add_child(amb)
	await process_frame

	var birds = amb.get_node("BirdsPlayer") as AudioStreamPlayer
	var insects = amb.get_node("InsectsPlayer") as AudioStreamPlayer
	var timer_birds = amb.get_node("TimerBirds") as Timer
	var timer_insects = amb.get_node("TimerInsects") as Timer

	_expect(birds != null, "BirdsPlayer missing")
	_expect(insects != null, "InsectsPlayer missing")
	_expect(birds.bus == &"Ambient", "birds bus not Ambient is %s" % birds.bus)
	_expect(insects.bus == &"Ambient", "insects bus not Ambient")
	_expect(birds.stream != null, "birds stream null")
	_expect(timer_birds != null, "TimerBirds missing")
	_expect(timer_insects != null, "TimerInsects missing")

	var clock = GameClock.new()
	root.add_child(clock)
	clock.setup(12.0)
	amb.setup(clock)
	await process_frame

	_expect(clock.time_changed.get_connections().size() >= 1, "clock time_changed not connected")

	# Settings 0 volume
	var settings = GameSettings.new()
	settings.ambient_volume = 0.0
	settings.birds_enabled = true
	settings.insects_enabled = true
	amb.apply_settings(settings)
	await process_frame
	_expect(birds.volume_db <= -79.0, "birds not muted at vol 0: %f" % birds.volume_db)

	# Day factor boundaries
	_expect(is_equal_approx(amb._get_day_factor(0.0), 0.0), "day_factor 0")
	_expect(is_equal_approx(amb._get_day_factor(5.99), 0.0), "day_factor 5.99")
	_expect(is_equal_approx(amb._get_day_factor(6.0), 0.0), "day_factor 6")
	_expect(amb._get_day_factor(7.0) > 0.4 and amb._get_day_factor(7.0) < 0.6, "day_factor 7 ~0.5 got %f" % amb._get_day_factor(7.0))
	_expect(is_equal_approx(amb._get_day_factor(8.0), 1.0), "day_factor 8")
	_expect(is_equal_approx(amb._get_day_factor(12.0), 1.0), "day_factor 12")
	_expect(is_equal_approx(amb._get_day_factor(17.0), 1.0), "day_factor 17")
	_expect(amb._get_day_factor(18.0) > 0.4 and amb._get_day_factor(18.0) < 0.6, "day_factor 18 ~0.5 got %f" % amb._get_day_factor(18.0))
	_expect(is_equal_approx(amb._get_day_factor(19.0), 0.0), "day_factor 19")
	_expect(is_equal_approx(amb._get_day_factor(20.0), 0.0), "day_factor 20")

	# Noon volumes - birds at 0.5 linear = -6dB approx
	settings.ambient_volume = 1.0
	amb.apply_settings(settings)
	clock.set_time_of_day(12.0)
	amb._on_time_changed(12.0)
	await process_frame
	_expect(birds.volume_db > -8.0 and birds.volume_db < -4.0, "birds vol at noon not ~-6dB got %f" % birds.volume_db)
	_expect(insects.volume_db <= -79.0, "insects should be muted at noon got %f" % insects.volume_db)

	# Night
	clock.set_time_of_day(2.0)
	amb._on_time_changed(2.0)
	_expect(is_equal_approx(amb._day_factor, 0.0), "night day_factor not 0")
	_expect(birds.volume_db <= -79.0, "birds should mute at night")

	# start/stop idempotent
	amb.start()
	amb.stop()
	amb.stop()
	_expect(not birds.playing, "birds still playing after stop")

	amb.queue_free()
	clock.queue_free()
	await process_frame
	await process_frame
	_finish("AUDIO_AMBIENT")
