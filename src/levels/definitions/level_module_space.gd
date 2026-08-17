extends VoxelSpace
class_name LevelModuleSpace

var _module: LevelModuleDefinition

func _init(module: LevelModuleDefinition) -> void:
	assert(module != null)
	_module = module

func get_block_at(position: Vector3i) -> Variant:
	if not StructureCell.is_in_bounds(position, _module.size):
		return null
	var value := _module.cell_at(position)
	return value if StructureCell.is_structure_solid(value) else null

func is_solid(position: Vector3i) -> bool:
	return StructureCell.is_in_bounds(position, _module.size) and StructureCell.is_structure_solid(_module.cell_at(position))

func get_highest_top(x: int, z: int) -> float:
	if x < 0 or z < 0 or x >= _module.size.x or z >= _module.size.z:
		return NO_SURFACE_Y
	for y in range(_module.size.y - 1, -1, -1):
		if StructureCell.is_structure_solid(_module.cell_at(Vector3i(x, y, z))):
			return float(y + 1)
	return NO_SURFACE_Y
