extends Resource
class_name EntityVocalizationProfile

@export var streams: Array[AudioStream] = []
@export_range(0.0, 120.0, 0.1) var initial_delay_min_seconds: float = 2.0
@export_range(0.0, 120.0, 0.1) var initial_delay_max_seconds: float = 8.0
@export_range(0.0, 120.0, 0.1) var interval_min_seconds: float = 6.0
@export_range(0.0, 120.0, 0.1) var interval_max_seconds: float = 14.0
@export_range(0.01, 4.0, 0.01) var pitch_min: float = 0.96
@export_range(0.01, 4.0, 0.01) var pitch_max: float = 1.04
@export var rng_salt: int = 0


func validate() -> bool:
	if streams.is_empty():
		return false
	for stream in streams:
		if stream == null:
			return false
	return (
		initial_delay_min_seconds >= 0.0
		and initial_delay_max_seconds >= initial_delay_min_seconds
		and interval_min_seconds >= 0.0
		and interval_max_seconds >= interval_min_seconds
		and pitch_min > 0.0
		and pitch_max >= pitch_min
	)
