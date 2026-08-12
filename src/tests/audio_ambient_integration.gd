extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[audio_ambient] starting")
	call_deferred("_run")

func _expect(cond: bool, msg: String):
	if not cond:
		_errors.append(msg)
		print("[audio_ambient] FAIL: %s" % msg)

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
	_expect(AudioServer.get_bus_index("Master") != -1, "Master bus missing")
	_expect(AudioServer.get_bus_index("SFX") != -1, "SFX bus missing")
	_expect(AudioServer.get_bus_index("Ambient") != -1, "Ambient bus missing")

	var packed = load("res://environment/ambient/ambient_soundscape.tscn") as PackedScene
	_expect(packed != null, "ambient_soundscape.tscn load failed")
	var amb = packed.instantiate() as AmbientSoundscape
	root.add_child(amb)
	await process_frame

	var birds = amb.get_node("BirdsPlayer") as AudioStreamPlayer
	var night = amb.get_node("NightPlayer") as AudioStreamPlayer

	_expect(birds != null, "BirdsPlayer missing")
	_expect(night != null, "NightPlayer missing")
	_expect(birds.bus == &"Ambient", "birds bus not Ambient is %s" % birds.bus)
	_expect(night.bus == &"Ambient", "night bus not Ambient is %s" % night.bus)

	var clock = GameClock.new()
	root.add_child(clock)
	clock.setup(12.0)
	amb.setup(clock)
	await process_frame

	_expect(birds.stream != null, "birds stream null after setup")
	_expect(night.stream != null, "night stream null after setup")
	_expect(clock.time_changed.get_connections().size() >= 1, "clock time_changed not connected")

	var settings = GameSettings.new()
	settings.ambient_volume = 0.0
	settings.birds_enabled = true
	amb.apply_settings(settings)
	await process_frame
	_expect(birds.volume_db <= -79.0, "birds not muted at vol 0: %f" % birds.volume_db)

	settings.ambient_volume = 0.42
	settings.birds_enabled = false
	var restored_settings = GameSettings.new()
	restored_settings._apply_dict(settings.to_dict())
	_expect(is_equal_approx(restored_settings.ambient_volume, 0.42), "ambient volume did not persist")
	_expect(not restored_settings.birds_enabled, "birds setting did not persist")

	var settings_scene = load("res://ui/screens/settings/settings_screen.tscn") as PackedScene
	var settings_screen = settings_scene.instantiate() as SettingsScreen
	root.add_child(settings_screen)
	await process_frame
	settings_screen.setup(restored_settings)
	_expect(is_equal_approx(settings_screen.ambient_volume.value, 0.42), "ambient volume control did not sync")
	_expect(not settings_screen.birds_enabled.button_pressed, "birds control did not sync")
	settings_screen.ambient_volume.set_value_no_signal(0.65)
	settings_screen.ambient_volume.value_changed.emit(0.65)
	settings_screen.birds_enabled.set_pressed_no_signal(true)
	settings_screen.birds_enabled.toggled.emit(true)
	_expect(is_equal_approx(restored_settings.ambient_volume, 0.65), "ambient volume control did not update settings")
	_expect(restored_settings.birds_enabled, "birds control did not update settings")

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
	_expect(is_equal_approx(amb._get_night_factor(0.0), 1.0), "night_factor 0")
	_expect(is_equal_approx(amb._get_night_factor(5.0), 1.0), "night_factor 5")
	_expect(amb._get_night_factor(5.5) > 0.4 and amb._get_night_factor(5.5) < 0.6, "night_factor 5.5")
	_expect(is_equal_approx(amb._get_night_factor(6.0), 0.0), "night_factor 6")
	_expect(is_equal_approx(amb._get_night_factor(17.0), 0.0), "night_factor 17")
	_expect(amb._get_night_factor(18.0) > 0.4 and amb._get_night_factor(18.0) < 0.6, "night_factor 18")
	_expect(is_equal_approx(amb._get_night_factor(19.0), 1.0), "night_factor 19")
	_expect(is_equal_approx(amb._night_factor, 0.0), "night factor did not initialize from noon")

	restored_settings.ambient_volume = 1.0
	amb.apply_settings(restored_settings)
	clock.set_time_of_day(12.0)
	amb.start()
	await process_frame
	_expect(birds.volume_db > -8.0 and birds.volume_db < -4.0, "birds vol at noon not ~-6dB got %f" % birds.volume_db)
	_expect(birds.playing, "birds did not start during daytime")
	_expect(night.volume_db <= -79.0, "night ambience should mute at noon")
	_expect(not night.playing, "night ambience started during daytime")

	clock.set_time_of_day(2.0)
	_expect(is_equal_approx(amb._day_factor, 0.0), "night day_factor not 0")
	_expect(is_equal_approx(amb._night_factor, 1.0), "night factor not 1")
	_expect(birds.volume_db <= -79.0, "birds should mute at night")
	_expect(not birds.playing, "birds did not stop at night")
	_expect(night.volume_db > -28.0 and night.volume_db < -24.0, "night ambience vol not ~-26dB got %f" % night.volume_db)
	_expect(night.playing, "night ambience did not start at night")
	amb.set_birds_enabled(false)
	_expect(night.playing, "disabling birds stopped night ambience")
	_expect(night.volume_db > -28.0 and night.volume_db < -24.0, "disabling birds changed night ambience volume")
	amb.set_birds_enabled(true)
	clock.set_time_of_day(5.5)
	_expect(not birds.playing, "birds started before sunrise")
	_expect(night.playing, "night ambience stopped during predawn fade")
	_expect(night.volume_db > -34.0 and night.volume_db < -30.0, "predawn night volume not ~-32dB")
	clock.set_time_of_day(6.0)
	_expect(not birds.playing, "birds played at zero sunrise factor")
	_expect(not night.playing, "night ambience did not stop at sunrise")

	clock.set_time_of_day(18.0)
	_expect(amb._day_factor > 0.4 and amb._day_factor < 0.6, "sundown day factor not ~0.5")
	_expect(amb._night_factor > 0.4 and amb._night_factor < 0.6, "sundown night factor not ~0.5")
	_expect(birds.playing, "birds did not play during sundown crossfade")
	_expect(night.playing, "night ambience did not play during sundown crossfade")
	_expect(birds.volume_db > -14.0 and birds.volume_db < -10.0, "birds sundown volume not ~-12dB")
	_expect(night.volume_db > -34.0 and night.volume_db < -30.0, "night sundown volume not ~-32dB")

	amb.stop()
	amb.stop()
	_expect(not birds.playing, "birds still playing after stop")
	_expect(not night.playing, "night ambience still playing after stop")
	amb.start()
	_expect(clock.time_changed.is_connected(amb._on_time_changed), "stop disconnected clock")
	amb.stop()

	amb.queue_free()
	clock.queue_free()
	settings_screen.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish", "AUDIO_AMBIENT")
