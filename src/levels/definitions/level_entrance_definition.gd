extends Resource
class_name LevelEntranceDefinition

@export var entrance_id: StringName
@export var level_id: StringName
@export var arch_block_id: int = BlockId.Type.STONE
@export var door_block_id: int = BlockId.Type.LOG
@export var door_open_streams: Array[AudioStream] = []
@export var enter_prompt: String = "F  Enter Dungeon"
@export var return_prompt: String = "F  Return to Wildes"

func validate(level_catalog: LevelCatalog) -> bool:
	var valid := true
	var source := resource_path
	if source.is_empty():
		source = String(entrance_id)
	if entrance_id.is_empty():
		push_error("[LevelEntranceDefinition] Empty entrance ID at %s" % source)
		valid = false
	if level_id.is_empty() or level_catalog == null or not level_catalog.has_level(level_id):
		push_error("[LevelEntranceDefinition] Unknown level ID for %s" % source)
		valid = false
	if not BlockId.is_chunk_cube(arch_block_id) or not BlockId.is_chunk_cube(door_block_id):
		push_error("[LevelEntranceDefinition] Invalid doorway blocks for %s" % source)
		valid = false
	if door_open_streams.is_empty():
		push_error("[LevelEntranceDefinition] Door-open audio is required for %s" % source)
		valid = false
	for stream in door_open_streams:
		if stream == null:
			push_error("[LevelEntranceDefinition] Null door-open audio stream for %s" % source)
			valid = false
	if enter_prompt.is_empty() or return_prompt.is_empty():
		push_error("[LevelEntranceDefinition] Interaction prompts are required for %s" % source)
		valid = false
	return valid
