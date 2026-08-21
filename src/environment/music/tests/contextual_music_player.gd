extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[contextual_music] FAIL: %s" % message)

func _finish() -> void:
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "music cleanup left %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("CONTEXTUAL_MUSIC PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("CONTEXTUAL_MUSIC FAIL failures=%d" % _failures)
		quit(1)

func _run() -> void:
	_expect(AudioServer.get_bus_index("Music") != -1, "Music bus missing")
	var packed := load("res://environment/music/contextual_music_player.tscn") as PackedScene
	_expect(packed != null, "contextual music scene failed to load")
	var music := packed.instantiate() as ContextualMusicPlayer
	root.add_child(music)
	await process_frame
	music.set_process(false)
	var player := music.get_node("MusicPlayer") as AudioStreamPlayer
	_expect(player != null, "MusicPlayer missing")
	_expect(player.bus == &"Music", "MusicPlayer is not routed to Music bus")
	_expect(is_equal_approx(music.base_volume, 0.144), "music base volume was not reduced by 20 percent")
	_expect(music.daytime_tracks.size() == 3, "daytime track catalog does not contain all tracks")
	_expect(music.dungeon_tracks.size() == 3, "dungeon track catalog does not contain all tracks")
	for track in music.daytime_tracks:
		_expect(track != null, "daytime track catalog contains a null stream")
	for track in music.dungeon_tracks:
		_expect(track != null, "dungeon track catalog contains a null stream")
	var test_stream := AudioStreamWAV.new()
	test_stream.format = AudioStreamWAV.FORMAT_16_BITS
	test_stream.mix_rate = 44100
	test_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var test_audio_data := PackedByteArray()
	test_audio_data.resize(88200)
	test_stream.data = test_audio_data
	music.daytime_tracks = [test_stream]

	var clock := GameClock.new()
	root.add_child(clock)
	clock.enable_cycle = false
	clock.setup(12.0)
	music.setup(clock, 777)
	var settings := GameSettings.new()
	settings.music_volume = 0.43
	var restored_settings := GameSettings.new()
	restored_settings._apply_dict(settings.to_dict())
	_expect(is_equal_approx(restored_settings.music_volume, 0.43), "music volume did not persist")
	music.apply_settings(restored_settings)
	_expect(is_equal_approx(music._music_volume, 0.43), "music volume setting was not applied")
	_expect(is_equal_approx(music._get_day_factor(6.0), 0.0), "sunrise factor should begin silent")
	_expect(is_equal_approx(music._get_day_factor(8.0), 1.0), "daytime factor should reach full volume")
	_expect(is_equal_approx(music._get_day_factor(19.0), 0.0), "sundown factor should end silent")

	music.set_volume(1.0)
	music.start()
	_expect(music._gap_remaining >= ContextualMusicPlayer.INITIAL_DELAY_MIN, "initial delay was below its configured minimum")
	_expect(music._gap_remaining <= ContextualMusicPlayer.INITIAL_DELAY_MAX, "initial delay exceeded its configured maximum")
	music.set_combat_active(true)
	music._gap_remaining = 0.0
	music._process(10.0)
	_expect(not player.playing, "music started while aggro was active")
	_expect(music._combat_duck <= 0.001, "combat duck did not stay silent during aggro")

	music.set_combat_active(false)
	music._process(ContextualMusicPlayer.COMBAT_FADE_IN_SECONDS)
	_expect(player.playing, "music did not become eligible after aggro cleared")
	music._process(music.autoplay_fade_in_seconds)
	_expect(player.volume_db > -79.0, "music remained silent after aggro cleared")
	music.set_combat_active(true)
	music._process(ContextualMusicPlayer.COMBAT_FADE_OUT_SECONDS * 0.5)
	_expect(player.playing and not player.stream_paused, "music paused before the fast combat fade completed")
	music._process(ContextualMusicPlayer.COMBAT_FADE_OUT_SECONDS * 0.5)
	_expect(player.stream_paused, "music was not paused after the combat fade")
	_expect(player.volume_db <= -79.0, "music remained audible during aggro")
	music._process(10.0)
	_expect(player.stream_paused, "music resumed while aggro remained active")

	music.set_combat_active(false)
	_expect(not player.stream_paused, "music did not resume after aggro cleared")
	music._process(ContextualMusicPlayer.COMBAT_FADE_IN_SECONDS)
	_expect(player.volume_db > -79.0, "music did not fade back in after aggro cleared")
	player.stop()
	music._on_player_finished()
	music._gap_remaining = 0.0
	music._process(10.0)
	_expect(not player.playing, "a second track started on the same day")

	clock.set_time_of_day(5.0)
	clock.set_time_of_day(12.0)
	music._gap_remaining = 0.0
	music._process(0.1)
	_expect(player.playing, "daily music eligibility did not reset after midnight")

	music.stop()
	music.dungeon_tracks = [test_stream]
	clock.set_time_of_day(2.0)
	music.set_combat_active(true)
	music.set_dungeon_active(true)
	music.start()
	_expect(music.is_dungeon_active(), "dungeon music context was not activated")
	_expect(music._gap_remaining >= ContextualMusicPlayer.DUNGEON_INITIAL_DELAY_MIN, "dungeon initial delay was below its configured minimum")
	_expect(music._gap_remaining <= ContextualMusicPlayer.DUNGEON_INITIAL_DELAY_MAX, "dungeon initial delay exceeded its configured maximum")
	music._gap_remaining = 0.0
	music._process(0.1)
	_expect(player.playing and not player.stream_paused, "dungeon music did not start during nighttime combat")
	_expect(music._current_stream_is_dungeon and music._combat_duck == 1.0, "dungeon music was suppressed by combat")
	player.stop()
	music._on_player_finished()
	_expect(music._gap_remaining >= ContextualMusicPlayer.DUNGEON_GAP_MIN_SECONDS, "dungeon repeat gap was below its configured minimum")
	_expect(music._gap_remaining <= ContextualMusicPlayer.DUNGEON_GAP_MAX_SECONDS, "dungeon repeat gap exceeded its configured maximum")
	music._gap_remaining = 0.0
	music._process(0.1)
	_expect(player.playing, "dungeon music was limited to one track per day")

	music.stop()
	music.set_dungeon_active(false)
	music.set_combat_active(false)
	music.daytime_tracks.clear()
	music.dungeon_tracks.clear()
	player.stream = null
	await create_timer(0.1).timeout
	music.queue_free()
	clock.queue_free()
	await create_timer(0.1).timeout
	player = null
	music = null
	clock = null
	packed = null
	settings = null
	restored_settings = null
	test_stream = null
	call_deferred("_finish")
