extends RefCounted
class_name LevelLayout

var seed_value: int
var cells: Dictionary = {}
var placed_modules: Array[LevelPlacedModule] = []
var torches: Array[LevelTorchPlacement] = []
var spawn_cell: Vector3i
var spawn_facing: LevelSocketDefinition.Direction
var return_door_cell: Vector3i
var return_door_facing: LevelSocketDefinition.Direction
var bounds_min: Vector3i
var bounds_max: Vector3i
var target_module_count: int
var explored_state_count: int

func get_cell(cell: Vector3i) -> int:
	return int(cells.get(cell, StructureCell.VOID))

func has_cell(cell: Vector3i) -> bool:
	return cells.has(cell)
