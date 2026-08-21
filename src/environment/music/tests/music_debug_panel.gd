extends SceneTree

var _failures: int = 0

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[music_debug_panel] FAIL: %s" % message)

func _finish() -> void:
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "music debug cleanup left %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("MUSIC_DEBUG_PANEL PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("MUSIC_DEBUG_PANEL FAIL failures=%d" % _failures)
		quit(1)

func _run() -> void:
	var music_scene := load("res://environment/music/contextual_music_player.tscn") as PackedScene
	var music := music_scene.instantiate() as ContextualMusicPlayer
	root.add_child(music)
	var clock := GameClock.new()
	root.add_child(clock)
	clock.enable_cycle = false
	clock.setup(2.0)
	music.setup(clock, 991)
	music.set_volume(1.0)
	music.start()

	var panel_scene := load("res://environment/music/music_debug_panel.tscn") as PackedScene
	var panel := panel_scene.instantiate() as MusicDebugPanel
	root.add_child(panel)
	await process_frame
	panel.setup(music)
	var daytime_tracks := panel.track_list.get_node("DaytimeTracks") as VBoxContainer
	var dungeon_tracks := panel.track_list.get_node("DungeonTracks") as VBoxContainer
	_expect(daytime_tracks != null, "daytime folder group was not created")
	_expect(dungeon_tracks != null, "dungeon folder group was not created")
	var track_buttons: Array[Button] = []
	if daytime_tracks != null:
		for child in daytime_tracks.get_children():
			if child is Button:
				track_buttons.append(child as Button)
	_expect(track_buttons.size() == 3, "daytime folder did not list all tracks")
	if track_buttons.size() == 3:
		_expect(track_buttons[0].text == "Morning", "first track label was not derived from its file")
		_expect(track_buttons[1].text == "The Britons", "second track label was not derived from its file")
		_expect(track_buttons[2].text == "Sunrise", "third track label was not derived from its file")
	var dungeon_buttons: Array[Button] = []
	if dungeon_tracks != null:
		for child in dungeon_tracks.get_children():
			if child is Button:
				dungeon_buttons.append(child as Button)
	_expect(dungeon_buttons.size() == 3, "dungeon folder did not list all tracks")
	if dungeon_buttons.size() == 3:
		_expect(dungeon_buttons[0].text == "Dungeon Master", "first dungeon track label was not derived from its file")
		_expect(dungeon_buttons[1].text == "Dark Angel", "second dungeon track label was not derived from its file")
		_expect(dungeon_buttons[2].text == "Night", "third dungeon track label was not derived from its file")

	var toggle_event := InputEventKey.new()
	toggle_event.pressed = true
	toggle_event.keycode = KEY_M
	panel._unhandled_input(toggle_event)
	_expect(panel.is_open(), "M key did not open the music debug panel")
	panel._unhandled_input(toggle_event)
	_expect(not panel.is_open(), "M key did not close the music debug panel")
	panel.disable_input()
	panel._unhandled_input(toggle_event)
	_expect(not panel.is_open(), "disabled music debug input still opened the panel")
	panel.enable_input()
	panel.show_panel()

	if not track_buttons.is_empty():
		track_buttons[0].pressed.emit()
	_expect(music.is_debug_preview_active(), "track button did not start a debug preview")
	_expect(music._player.playing, "debug preview did not start the music player")
	_expect(music._player.volume_db > -79.0, "nighttime muted the explicit debug preview")
	panel._process(0.0)
	_expect(panel.status_label.text.begins_with("Previewing:"), "panel did not report the active preview")

	music.set_combat_active(true)
	music._process(ContextualMusicPlayer.COMBAT_FADE_OUT_SECONDS)
	panel._process(0.0)
	_expect(music._player.stream_paused, "debug preview continued playing through aggro")
	_expect(panel.status_label.text == "Blocked by enemy aggro", "panel did not report the aggro block")
	if not track_buttons.is_empty():
		_expect(track_buttons[0].disabled, "track button remained enabled during aggro")
	if not dungeon_buttons.is_empty():
		_expect(not dungeon_buttons[0].disabled, "dungeon track button was blocked during aggro")
		dungeon_buttons[0].pressed.emit()
		panel._process(0.0)
		_expect(music.is_debug_preview_active() and not music._player.stream_paused, "dungeon debug preview was blocked by aggro")
		_expect(panel.status_label.text == "Previewing: Dungeon Master", "panel did not report the dungeon debug preview")
	music.set_combat_active(false)
	music._process(ContextualMusicPlayer.COMBAT_FADE_IN_SECONDS)
	panel._process(0.0)
	_expect(not music._player.stream_paused, "debug preview did not resume after aggro cleared")
	panel.stop_button.pressed.emit()
	_expect(not music.is_debug_preview_active(), "stop button retained the debug preview")
	_expect(not music._player.playing, "stop button retained music playback")
	if not track_buttons.is_empty():
		track_buttons[0].pressed.emit()
	panel.disable_input()
	_expect(not music.is_debug_preview_active(), "disabling debug input retained the music preview")
	_expect(not music._player.playing, "disabling debug input retained music playback")

	music.stop()
	music.daytime_tracks.clear()
	music.dungeon_tracks.clear()
	music._player.stream = null
	await create_timer(0.1).timeout
	panel.queue_free()
	music.queue_free()
	clock.queue_free()
	await create_timer(0.1).timeout
	panel = null
	music = null
	clock = null
	panel_scene = null
	music_scene = null
	call_deferred("_finish")
