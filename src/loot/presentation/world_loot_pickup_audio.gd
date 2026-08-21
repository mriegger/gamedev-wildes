extends Node
class_name WorldLootPickupAudio

@export var streams: Array[AudioStream] = []
@export_range(0.01, 4.0, 0.01) var pitch_min: float = 0.96
@export_range(0.01, 4.0, 0.01) var pitch_max: float = 1.04

@onready var _player: AudioStreamPlayer = $Player as AudioStreamPlayer

var _coordinator: OverworldLootCoordinator
var _last_stream_index: int = -1

func setup(coordinator: OverworldLootCoordinator) -> void:
	assert(coordinator != null and _coordinator == null)
	assert(not streams.is_empty() and pitch_min <= pitch_max)
	for stream in streams:
		assert(stream != null)
	_coordinator = coordinator
	_coordinator.pickup_committed.connect(_on_pickup_committed)

func _on_pickup_committed(_item_id: StringName, _count: int) -> void:
	var stream_index := randi_range(0, streams.size() - 1)
	if streams.size() > 1:
		while stream_index == _last_stream_index:
			stream_index = randi_range(0, streams.size() - 1)
	_last_stream_index = stream_index
	_player.stop()
	_player.stream = streams[stream_index]
	_player.pitch_scale = randf_range(pitch_min, pitch_max)
	_player.play()

func _exit_tree() -> void:
	if _coordinator != null and _coordinator.pickup_committed.is_connected(_on_pickup_committed):
		_coordinator.pickup_committed.disconnect(_on_pickup_committed)
	_coordinator = null
	_player.stop()
	_player.stream = null
