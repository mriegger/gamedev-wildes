extends Node
class_name ContextualMusicPlayer

const BASE_VOLUME: float = 0.144
const FADE_IN_SECONDS: float = 1.2
const FADE_OUT_SECONDS: float = 0.6
const COMBAT_FADE_OUT_SECONDS: float = 0.45
const COMBAT_FADE_IN_SECONDS: float = 1.2
const INITIAL_DELAY_MIN: float = 40.0
const INITIAL_DELAY_MAX: float = 90.0
const GAP_MIN_SECONDS: float = 25.0
const GAP_MAX_SECONDS: float = 60.0
const EARLIEST_START_HOUR: float = 7.5
const DUNGEON_INITIAL_DELAY_MIN: float = 8.0
const DUNGEON_INITIAL_DELAY_MAX: float = 20.0
const DUNGEON_GAP_MIN_SECONDS: float = 20.0
const DUNGEON_GAP_MAX_SECONDS: float = 45.0

@export var daytime_tracks: Array[AudioStream] = []
@export var dungeon_tracks: Array[AudioStream] = []
@export_range(0.0, 1.0, 0.01) var base_volume: float = BASE_VOLUME
@export var autoplay_fade_in_seconds: float = FADE_IN_SECONDS
@export var autoplay_fade_out_seconds: float = FADE_OUT_SECONDS

@onready var _player: AudioStreamPlayer = $MusicPlayer

var _clock: GameClock
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _music_volume: float = 0.7
var _day_factor: float = 1.0
var _running: bool = false
var _player_fade: float = 0.0
var _combat_duck: float = 1.0
var _combat_active: bool = false
var _pending_fade_target: float = 1.0
var _pending_fade_duration: float = 1.0
var _pending_fade_elapsed: float = 0.0
var _combat_fade_start: float = 1.0
var _gap_remaining: float = 0.0
var _last_track_index: int = -1
var _current_stream: AudioStream = null
var _current_stream_is_dungeon: bool = false
var _current_track_scale: float = 1.0
var _played_today: bool = false
var _last_time: float = -1.0
var _debug_preview_active: bool = false
var _dungeon_active: bool = false


func _ready():
	if _player != null and not _player.finished.is_connected(_on_player_finished):
		_player.finished.connect(_on_player_finished)


func setup(p_clock: GameClock, seed_value: int):
	_clock = p_clock
	_rng.seed = seed_value
	_clock.time_changed.connect(_on_time_changed)
	var t = _clock.get_time_of_day()
	_day_factor = _get_day_factor(t)
	_last_time = t
	_played_today = false
	if _player != null and not _player.finished.is_connected(_on_player_finished):
		_player.finished.connect(_on_player_finished)
	_apply_volume()


func start():
	_running = true
	var t = _clock.get_time_of_day() if _clock != null else 1.0
	_day_factor = _get_day_factor(t)
	_last_time = t
	_combat_duck = 0.0 if _is_combat_blocking_music() else 1.0
	_pending_fade_target = _combat_duck
	_pending_fade_duration = 0.0
	_pending_fade_elapsed = 0.0
	_player_fade = 0.0
	_player.stream_paused = _is_combat_blocking_music() and _player.playing
	_gap_remaining = _random_initial_delay()
	_apply_volume()
	_sync_playback()


func stop():
	_running = false
	_debug_preview_active = false
	_player.stream_paused = false
	_player.stop()
	_current_stream = null
	_current_stream_is_dungeon = false
	_current_track_scale = 1.0
	_player_fade = 0.0
	_gap_remaining = 0.0
	_apply_volume()


func apply_settings(settings: GameSettings):
	set_volume(settings.music_volume)


func set_volume(volume: float):
	_music_volume = clampf(volume, 0.0, 1.0)
	_apply_volume()
	if _running:
		_sync_playback()


func set_dungeon_active(active: bool) -> void:
	if active == _dungeon_active:
		return
	_dungeon_active = active
	_debug_preview_active = false
	_player.stream_paused = false
	_player.stop()
	_current_stream = null
	_current_stream_is_dungeon = false
	_current_track_scale = 1.0
	_player_fade = 0.0
	_last_track_index = -1
	_gap_remaining = _random_initial_delay()
	_combat_duck = 0.0 if _is_combat_blocking_music() else 1.0
	_pending_fade_target = _combat_duck
	_pending_fade_duration = 0.0
	_pending_fade_elapsed = 0.0
	_apply_volume()
	if _running:
		_sync_playback()


func set_combat_active(active: bool) -> void:
	if active == _combat_active:
		return
	_combat_active = active
	if not _is_combat_sensitive_playback():
		_player.stream_paused = false
		_combat_duck = 1.0
		_pending_fade_target = 1.0
		_pending_fade_duration = 0.0
		_pending_fade_elapsed = 0.0
		_apply_volume()
		return
	if not active:
		_player.stream_paused = false
	if not _running and not _debug_preview_active:
		_combat_duck = 0.0 if active else 1.0
		_pending_fade_target = _combat_duck
		_pending_fade_duration = 0.0
		_pending_fade_elapsed = 0.0
		_apply_volume()
		return
	_begin_combat_fade(0.0 if active else 1.0, COMBAT_FADE_OUT_SECONDS if active else COMBAT_FADE_IN_SECONDS)
	if not active:
		_sync_playback()


func _exit_tree():
	stop()
	if _clock != null and _clock.time_changed.is_connected(_on_time_changed):
		_clock.time_changed.disconnect(_on_time_changed)
	_clock = null
	if _player:
		_player.stream = null
	_current_stream = null
	_current_stream_is_dungeon = false
	_current_track_scale = 1.0


func _process(delta):
	if not _running and not _debug_preview_active:
		return
	_update_combat_duck(delta)
	_update_player_fade(delta)
	_apply_volume()
	if _debug_preview_active:
		return
	_update_scheduling(delta)


func _on_time_changed(new_time: float):
	if _last_time >= 0.0 and new_time < _last_time:
		_played_today = false
	_last_time = new_time
	_day_factor = _get_day_factor(new_time)
	_apply_volume()
	if not _running:
		return
	_sync_playback()


func _update_combat_duck(delta):
	if not _is_combat_sensitive_playback():
		_combat_duck = 1.0
		return
	_combat_duck = _advance_fade(_combat_duck, delta)
	if _pending_fade_duration > 0.0 and _pending_fade_elapsed >= _pending_fade_duration:
		_combat_duck = _pending_fade_target
		_pending_fade_elapsed = 0.0
		_pending_fade_duration = 0.0
	if _combat_active and _combat_duck <= 0.001 and _player.playing:
		_player.stream_paused = true


func _begin_combat_fade(target: float, duration: float):
	_pending_fade_target = clampf(target, 0.0, 1.0)
	_pending_fade_duration = maxf(duration, 0.01)
	_pending_fade_elapsed = 0.0
	_combat_fade_start = _combat_duck


func _advance_fade(_current: float, delta: float) -> float:
	if _pending_fade_duration <= 0.0 or is_equal_approx(_combat_duck, _pending_fade_target):
		return _pending_fade_target
	_pending_fade_elapsed += delta
	var t = clampf(_pending_fade_elapsed / _pending_fade_duration, 0.0, 1.0)
	if t >= 1.0:
		return _pending_fade_target
	return lerpf(_combat_fade_start, _pending_fade_target, t)


func _update_player_fade(delta):
	if not _player.playing:
		_player_fade = 0.0
		return
	var target = 1.0 if (_debug_preview_active or _current_stream_is_dungeon or _is_daytime_audible()) and _music_volume > 0.001 else 0.0
	var fade_seconds = autoplay_fade_in_seconds if target > _player_fade else autoplay_fade_out_seconds
	if is_equal_approx(_player_fade, target):
		return
	if fade_seconds <= 0.01:
		_player_fade = target
		return
	var step = delta / fade_seconds
	if target > _player_fade:
		_player_fade = minf(target, _player_fade + step)
	else:
		_player_fade = maxf(target, _player_fade - step)


func _update_scheduling(delta):
	if _get_active_tracks().is_empty() or (not _dungeon_active and _played_today) or _is_combat_blocking_music() or _debug_preview_active:
		return
	if not _is_active_context_audible() or _music_volume <= 0.001:
		return
	if _player.playing:
		return
	if not _is_eligible_for_play():
		return
	_gap_remaining -= delta
	if _gap_remaining > 0.0:
		return
	_play_next_track()


func _sync_playback():
	if _debug_preview_active:
		return
	if not _running or _get_active_tracks().is_empty():
		if _player.playing and _player_fade <= 0.01:
			_player.stop()
			_current_stream = null
		return
	if _is_combat_blocking_music():
		return
	if _player.playing:
		if (not _is_active_context_audible() or _music_volume <= 0.001) and _player_fade <= 0.01:
			_player.stop()
			_current_stream = null
		return
	if (not _dungeon_active and _played_today) or not _is_active_context_audible() or _music_volume <= 0.001:
		return
	if _gap_remaining <= 0.0 and _is_eligible_for_play():
		_play_next_track()


func _play_next_track():
	var active_tracks := _get_active_tracks()
	if active_tracks.is_empty() or not _running or (not _dungeon_active and _played_today) or _is_combat_blocking_music():
		return
	if not _is_eligible_for_play():
		return
	var next_index = _pick_next_index()
	if next_index < 0:
		return
	_last_track_index = next_index
	_current_stream = active_tracks[next_index]
	_current_stream_is_dungeon = _dungeon_active
	_current_track_scale = _get_track_scale(_current_stream)
	_player.stream = _current_stream
	_player_fade = 0.0
	_player.play()
	if not _dungeon_active:
		_played_today = true
	_gap_remaining = _random_track_gap()


func _pick_next_index() -> int:
	var active_tracks := _get_active_tracks()
	if active_tracks.is_empty():
		return -1
	if active_tracks.size() == 1:
		return 0
	var next_index = _rng.randi_range(0, active_tracks.size() - 1)
	if next_index == _last_track_index:
		next_index = (next_index + 1) % active_tracks.size()
	return next_index


func _on_player_finished():
	_current_stream = null
	_current_stream_is_dungeon = false
	_current_track_scale = 1.0
	if _debug_preview_active:
		_debug_preview_active = false
		_player_fade = 0.0
		_apply_volume()
		if _running:
			_sync_playback()
		return
	_gap_remaining = _random_track_gap()


func _apply_volume():
	if _player == null:
		return
	var time_factor := 1.0 if _debug_preview_active or _current_stream_is_dungeon else _day_factor
	var linear = _music_volume * time_factor * base_volume * _current_track_scale * _combat_duck * _player_fade
	_player.volume_db = linear_to_db(linear) if linear > 0.001 else -80.0


func get_debug_track_count() -> int:
	return daytime_tracks.size() + dungeon_tracks.size()


func get_debug_track_folder(index: int) -> String:
	assert(index >= 0 and index < get_debug_track_count())
	var stream := _get_debug_stream(index)
	if stream == null or stream.resource_path.is_empty():
		return "Uncategorized"
	return stream.resource_path.get_base_dir().get_file().capitalize()


func get_debug_track_name(index: int) -> String:
	assert(index >= 0 and index < get_debug_track_count())
	return _get_stream_name(_get_debug_stream(index), index)


func try_debug_play_track(index: int) -> bool:
	if index < 0 or index >= get_debug_track_count():
		return false
	var stream := _get_debug_stream(index)
	var stream_is_dungeon := _is_debug_stream_dungeon(index)
	if stream == null or (_combat_active and not stream_is_dungeon):
		return false
	_debug_preview_active = true
	_current_stream = stream
	_current_stream_is_dungeon = stream_is_dungeon
	_current_track_scale = _get_track_scale(_current_stream)
	_player.stream_paused = false
	_player.stream = _current_stream
	_player_fade = 1.0
	_combat_duck = 1.0
	_pending_fade_target = 1.0
	_pending_fade_duration = 0.0
	_pending_fade_elapsed = 0.0
	_player.play()
	_apply_volume()
	return true


func stop_debug_playback() -> void:
	if not _debug_preview_active:
		return
	_debug_preview_active = false
	_player.stream_paused = false
	_player.stop()
	_current_stream = null
	_current_stream_is_dungeon = false
	_current_track_scale = 1.0
	_player_fade = 0.0
	_apply_volume()
	if _running:
		_sync_playback()


func is_debug_preview_active() -> bool:
	return _debug_preview_active


func is_combat_active() -> bool:
	return _combat_active


func is_combat_blocking_music() -> bool:
	return _is_combat_blocking_music()


func is_debug_track_blocked(index: int) -> bool:
	assert(index >= 0 and index < get_debug_track_count())
	return _combat_active and not _is_debug_stream_dungeon(index)


func is_dungeon_active() -> bool:
	return _dungeon_active


func is_running() -> bool:
	return _running


func get_current_track_name() -> String:
	if _current_stream == null:
		return ""
	var index := daytime_tracks.find(_current_stream)
	if index < 0:
		index = daytime_tracks.size() + dungeon_tracks.find(_current_stream)
	return _get_stream_name(_current_stream, index)


func _get_stream_name(stream: AudioStream, index: int) -> String:
	if stream != null and not stream.resource_path.is_empty():
		return stream.resource_path.get_file().get_basename()
	return "Track %d" % (index + 1) if index >= 0 else "Track"


func _get_track_scale(stream: AudioStream) -> float:
	if stream != null and (stream.resource_path.contains("Morning") or stream.resource_path.contains("Sunrise")):
		return 2.25
	if stream != null and dungeon_tracks.has(stream):
		return 2.0
	return 1.0


func _get_active_tracks() -> Array[AudioStream]:
	return dungeon_tracks if _dungeon_active else daytime_tracks


func _get_debug_stream(index: int) -> AudioStream:
	return dungeon_tracks[index - daytime_tracks.size()] if _is_debug_stream_dungeon(index) else daytime_tracks[index]


func _is_debug_stream_dungeon(index: int) -> bool:
	return index >= daytime_tracks.size()


func _is_combat_sensitive_playback() -> bool:
	return not _current_stream_is_dungeon if _debug_preview_active else not _dungeon_active


func _is_combat_blocking_music() -> bool:
	return _combat_active and _is_combat_sensitive_playback()


func _is_active_context_audible() -> bool:
	return _dungeon_active or _is_daytime_audible()


func _random_initial_delay() -> float:
	return _rng.randf_range(DUNGEON_INITIAL_DELAY_MIN, DUNGEON_INITIAL_DELAY_MAX) if _dungeon_active else _rng.randf_range(INITIAL_DELAY_MIN, INITIAL_DELAY_MAX)


func _random_track_gap() -> float:
	return _rng.randf_range(DUNGEON_GAP_MIN_SECONDS, DUNGEON_GAP_MAX_SECONDS) if _dungeon_active else _rng.randf_range(GAP_MIN_SECONDS, GAP_MAX_SECONDS)


func _is_daytime_audible() -> bool:
	return _day_factor > 0.01


func _is_eligible_for_play() -> bool:
	return _dungeon_active or (_clock != null and _clock.get_time_of_day() >= EARLIEST_START_HOUR)


func _get_day_factor(t: float) -> float:
	if t < 6.0 or t >= 19.0:
		return 0.0
	if t < 8.0:
		return inverse_lerp(6.0, 8.0, t)
	if t < 17.0:
		return 1.0
	return 1.0 - inverse_lerp(17.0, 19.0, t)
