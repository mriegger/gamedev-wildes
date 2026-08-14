extends Resource
class_name PumpkinGrowthStateDefinition

@export var id: StringName
@export var model_scene: PackedScene

func validate() -> bool:
	return not id.is_empty() and model_scene != null
