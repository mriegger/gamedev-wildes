extends Resource
class_name LevelPresentationDefinition

@export var terrain_shader: Shader
@export var background_color: Color = Color(0.002, 0.003, 0.005, 1.0)
@export_range(0.0, 16.0, 0.01) var background_energy_multiplier: float = 0.1
@export var ambient_light_color: Color = Color(0.42, 0.44, 0.48, 1.0)
@export_range(0.0, 16.0, 0.01) var ambient_light_energy: float = 0.28
@export var return_door_block_id: int = BlockId.Type.LOG

func validate(source: String) -> bool:
	var valid := true
	if terrain_shader == null:
		push_error("[LevelPresentationDefinition] Missing terrain shader for %s" % source)
		valid = false
	if background_energy_multiplier < 0.0 or ambient_light_energy < 0.0:
		push_error("[LevelPresentationDefinition] Negative lighting energy for %s" % source)
		valid = false
	if not BlockId.is_chunk_cube(return_door_block_id):
		push_error("[LevelPresentationDefinition] Invalid return door block for %s" % source)
		valid = false
	return valid
