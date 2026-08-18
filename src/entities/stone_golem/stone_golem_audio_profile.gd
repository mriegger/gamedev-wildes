extends Resource
class_name StoneGolemAudioProfile

@export var walk_streams: Array[AudioStream] = []
@export var impact_streams: Array[AudioStream] = []
@export var death_streams: Array[AudioStream] = []
@export_range(0.01, 4.0, 0.01) var walk_pitch_min: float = 0.94
@export_range(0.01, 4.0, 0.01) var walk_pitch_max: float = 1.04
@export_range(0.01, 4.0, 0.01) var impact_pitch_min: float = 0.94
@export_range(0.01, 4.0, 0.01) var impact_pitch_max: float = 1.06
@export_range(0.01, 4.0, 0.01) var death_pitch_min: float = 0.96
@export_range(0.01, 4.0, 0.01) var death_pitch_max: float = 1.02
@export var rng_salt: int = 0

func validate() -> bool:
	return (
		_validate_streams(walk_streams)
		and _validate_streams(impact_streams)
		and _validate_streams(death_streams)
		and walk_pitch_min > 0.0
		and walk_pitch_max >= walk_pitch_min
		and impact_pitch_min > 0.0
		and impact_pitch_max >= impact_pitch_min
		and death_pitch_min > 0.0
		and death_pitch_max >= death_pitch_min
	)

func _validate_streams(streams: Array[AudioStream]) -> bool:
	if streams.is_empty():
		return false
	for stream in streams:
		if stream == null:
			return false
	return true
