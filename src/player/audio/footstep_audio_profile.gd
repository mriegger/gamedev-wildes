extends Resource
class_name FootstepAudioProfile

@export var surface_block_id: BlockId.Type = BlockId.Type.DIRT
@export var streams: Array[AudioStream] = []


func validate() -> bool:
	if not BlockId.is_valid(surface_block_id) or surface_block_id == BlockId.Type.AIR:
		return false
	if streams.is_empty():
		return false
	for stream in streams:
		if stream == null:
			return false
	return true
