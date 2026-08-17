extends Resource
class_name FootstepAudioProfile

@export var surface_block_id: BlockId.Type = BlockId.Type.DIRT
@export var streams: Array[AudioStream] = []
@export_range(-80.0, 24.0, 0.01) var volume_offset_db: float = 0.0


func validate() -> bool:
	if not BlockId.is_valid(surface_block_id) or surface_block_id == BlockId.Type.AIR:
		return false
	if streams.is_empty():
		return false
	for stream in streams:
		if stream == null:
			return false
	return true
