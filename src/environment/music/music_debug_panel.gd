extends CanvasLayer
class_name MusicDebugPanel

@onready var panel: Panel = $Panel
@onready var close_button: Button = $Panel/VBox/Header/CloseButton
@onready var status_label: Label = $Panel/VBox/StatusLabel
@onready var track_list: VBoxContainer = $Panel/VBox/TrackScroll/TrackList
@onready var stop_button: Button = $Panel/VBox/Controls/StopButton

var _music: ContextualMusicPlayer
var _track_buttons: Array[Button] = []
var _input_enabled: bool = false

func _ready() -> void:
	set_process(false)
	set_process_unhandled_input(false)
	panel.add_theme_stylebox_override("panel", WildesStyle.make_panel(Color(0.06, 0.07, 0.09, 0.96), 10, Color(0.55, 0.68, 0.82, 0.72), 1))
	close_button.pressed.connect(hide_panel)
	stop_button.pressed.connect(_on_stop_pressed)

func setup(music: ContextualMusicPlayer) -> void:
	assert(music != null)
	_music = music
	_build_track_list()
	enable_input()

func _build_track_list() -> void:
	for child in track_list.get_children():
		child.queue_free()
	_track_buttons.clear()
	var folder_containers: Dictionary = {}
	for index in range(_music.get_debug_track_count()):
		var folder := _music.get_debug_track_folder(index)
		var folder_tracks := folder_containers.get(folder) as VBoxContainer
		if folder_tracks == null:
			folder_tracks = VBoxContainer.new()
			folder_tracks.name = "%sTracks" % folder.to_pascal_case()
			folder_tracks.add_theme_constant_override("separation", 6)
			var folder_label := Label.new()
			folder_label.text = folder
			folder_label.add_theme_font_size_override("font_size", 14)
			folder_tracks.add_child(folder_label)
			track_list.add_child(folder_tracks)
			folder_containers[folder] = folder_tracks
		var button := Button.new()
		button.text = _music.get_debug_track_name(index)
		button.custom_minimum_size = Vector2(0.0, 32.0)
		button.pressed.connect(_on_track_pressed.bind(index))
		button.set_meta(&"track_index", index)
		folder_tracks.add_child(button)
		_track_buttons.append(button)

func _process(_delta: float) -> void:
	_refresh_status()

func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_M or event.physical_keycode == KEY_M:
			toggle_panel()

func _on_track_pressed(index: int) -> void:
	_music.try_debug_play_track(index)
	_refresh_status()

func _on_stop_pressed() -> void:
	_music.stop_debug_playback()
	_refresh_status()

func _refresh_status() -> void:
	if _music == null:
		return
	var combat_active := _music.is_combat_active()
	for button in _track_buttons:
		button.disabled = _music.is_debug_track_blocked(int(button.get_meta(&"track_index")))
	stop_button.disabled = not _music.is_debug_preview_active()
	if combat_active and _music.is_combat_blocking_music():
		status_label.text = "Blocked by enemy aggro"
	elif _music.is_debug_preview_active():
		status_label.text = "Previewing: %s" % _music.get_current_track_name()
	elif not _music.get_current_track_name().is_empty():
		status_label.text = "Scheduled: %s" % _music.get_current_track_name()
	else:
		status_label.text = "No music playing"

func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	assert(_music != null)
	visible = true
	set_process(true)
	_refresh_status()

func hide_panel() -> void:
	visible = false
	set_process(false)

func is_open() -> bool:
	return visible

func is_input_enabled() -> bool:
	return _input_enabled

func disable_input() -> void:
	hide_panel()
	if _music != null:
		_music.stop_debug_playback()
	_input_enabled = false
	set_process_unhandled_input(false)

func enable_input() -> void:
	_input_enabled = true
	set_process_unhandled_input(true)
