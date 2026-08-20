extends Resource
class_name CampfireAudioProfile

@export var loop_stream: AudioStream
@export_range(-80.0, 24.0, 0.1) var volume_db: float = -10.0
@export_range(0.1, 100.0, 0.1) var unit_size: float = 7.0
@export_range(0.1, 200.0, 0.1) var max_distance: float = 32.0

func validate() -> bool:
	return loop_stream != null and unit_size > 0.0 and max_distance >= unit_size
