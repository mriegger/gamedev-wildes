extends Node3D
class_name HarvestSource

func validate_harvest_items(_item_catalog: ItemCatalog) -> bool:
	return false

func find_harvest_target(_ray_origin: Vector3, _ray_direction: Vector3, _max_distance: float) -> Dictionary:
	return {}

func get_harvest_target_bounds(_target_id: int) -> AABB:
	return AABB()

func can_harvest_target(_target_id: int) -> bool:
	return false

func get_harvest_item_ids(_target_id: int) -> Array[StringName]:
	return []

func try_harvest_target(_target_id: int) -> bool:
	return false

func get_harvest_prompt() -> String:
	return ""
