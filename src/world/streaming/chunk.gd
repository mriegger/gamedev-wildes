extends RefCounted
class_name WorldChunk

## WorldChunk - lightweight holder for streaming state

enum State {
	UNLOADED = 0,
	QUEUED_LOAD = 1,
	LOADING = 2,
	LOADED = 3,
	QUEUED_UNLOAD = 4,
}

var coord: Vector2i = Vector2i.ZERO
var state: State = State.UNLOADED
var last_visible_time: float = 0.0
var last_request_time: float = 0.0
var load_attempts: int = 0

func _init(p_coord: Vector2i = Vector2i.ZERO):
	coord = p_coord
	state = State.UNLOADED

func key() -> String:
	return "%d_%d" % [coord.x, coord.y]

func to_dict() -> Dictionary:
	return {
		"coord": coord,
		"state": state,
		"key": key(),
		"last_visible": last_visible_time,
	}

func _to_string() -> String:
	return "[WorldChunk %s state=%s]" % [key(), State.keys()[state]]
