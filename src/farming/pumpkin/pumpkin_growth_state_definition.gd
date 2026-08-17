extends Resource
class_name PumpkinGrowthStateDefinition

@export var id: StringName
@export var model_scene: PackedScene
@export var generate_in_new_patch: bool = true
@export var harvest_item_id: StringName
@export_range(0, 999, 1) var harvest_count: int = 0
@export var harvest_result_state_id: StringName

func validate() -> bool:
	if id.is_empty() or (generate_in_new_patch and model_scene == null):
		return false
	var harvest_fields := int(not harvest_item_id.is_empty()) + int(harvest_count > 0) + int(not harvest_result_state_id.is_empty())
	return harvest_fields == 0 or (harvest_fields == 3 and harvest_result_state_id != id)

func is_harvestable() -> bool:
	return not harvest_item_id.is_empty()
