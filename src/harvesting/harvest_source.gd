extends Node3D
class_name HarvestSource

func validate_harvest_items(_item_catalog: ItemCatalog) -> bool:
	return false

func find_harvest_target(_ray_origin: Vector3, _ray_direction: Vector3, _max_distance: float) -> Dictionary:
	return {}

func get_harvest_target_bounds(_target_id: int) -> AABB:
	return AABB()

func get_harvest_target_ids() -> Array[int]:
	return []

func can_harvest_target(_target_id: int) -> bool:
	return false

func get_harvest_item_ids(_target_id: int) -> Array[StringName]:
	return []

func prepare_harvest_target(_target_id: int) -> PreparedHarvestChange:
	return null

func can_commit_prepared_harvest(_prepared: PreparedHarvestChange) -> bool:
	return false

func _commit_prepared_harvest(
	_prepared: PreparedHarvestChange,
	_emit_signal: bool = true,
) -> bool:
	return false

func _notify_prepared_harvest(_prepared: PreparedHarvestChange) -> bool:
	return false

func get_harvest_prompt() -> String:
	return ""
