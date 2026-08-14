extends Resource
class_name ItemEquipAudioProfile

@export var streams: Array[AudioStream] = []
@export_range(-80.0, 24.0, 0.1) var volume_db: float = -6.0
@export_range(0.01, 4.0, 0.01) var pitch_min: float = 0.98
@export_range(0.01, 4.0, 0.01) var pitch_max: float = 1.02


func validate(source: String) -> bool:
	if streams.is_empty():
		push_error("[ItemEquipAudioProfile] No streams at %s" % source)
		return false
	for stream in streams:
		if stream == null:
			push_error("[ItemEquipAudioProfile] Null stream at %s" % source)
			return false
	if not is_finite(volume_db) or pitch_min <= 0.0 or pitch_max < pitch_min:
		push_error("[ItemEquipAudioProfile] Invalid tuning at %s" % source)
		return false
	return true
