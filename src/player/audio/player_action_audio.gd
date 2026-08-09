extends Node
class_name PlayerActionAudio

@onready var _player: AudioStreamPlayer = $ClunkPlayer

var _interactor: PlayerInteractor
var _streams: Array[AudioStream] = [
	preload("res://assets/audio/sfx/tools/impactGeneric_light_001.ogg"),
	preload("res://assets/audio/sfx/tools/impactGeneric_light_002.ogg"),
	preload("res://assets/audio/sfx/tools/impactGeneric_light_003.ogg"),
	preload("res://assets/audio/sfx/tools/impactGeneric_light_004.ogg"),
]

var _last_idx: int = -1


func setup(p_interactor: PlayerInteractor):
	_interactor = p_interactor
	_interactor.mining_hit.connect(_on_mining_hit)
	_interactor.melee_terrain_hit.connect(_on_melee_terrain_hit)
	if _player.stream == null and _streams.size() > 0:
		_player.stream = _streams[0]


func _on_mining_hit(_pos: Vector3i, _block_id: int, _action):
	_play_clunk(-6.0)


func _on_melee_terrain_hit(_pos: Vector3i):
	_play_clunk(-4.0)


func _play_clunk(volume_db: float = -6.0):
	if _streams.is_empty():
		return
	var idx = randi_range(0, _streams.size() - 1)
	if _streams.size() > 1:
		while idx == _last_idx:
			idx = randi_range(0, _streams.size() - 1)
		_last_idx = idx
	_player.stream = _streams[idx]
	_player.pitch_scale = randf_range(0.95, 1.07)
	_player.volume_db = volume_db
	_player.play()
