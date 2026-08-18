extends Resource
class_name ItemConsumeAudioProfile

@export var streams: Array[AudioStream]
@export_range(-80.0, 24.0, 0.1) var volume_db: float = -6.0
@export_range(0.1, 4.0, 0.01) var pitch_min: float = 1.0
@export_range(0.1, 4.0, 0.01) var pitch_max: float = 1.0

func validate(source: String) -> bool:
	if streams.is_empty():
		push_error("[ItemConsumeAudioProfile] Missing streams at %s" % source)
		return false
	for stream in streams:
		if stream == null:
			push_error("[ItemConsumeAudioProfile] Null stream at %s" % source)
			return false
	if not is_finite(volume_db) or not is_finite(pitch_min) or not is_finite(pitch_max) or pitch_min <= 0.0 or pitch_max < pitch_min:
		push_error("[ItemConsumeAudioProfile] Invalid playback values at %s" % source)
		return false
	return true
