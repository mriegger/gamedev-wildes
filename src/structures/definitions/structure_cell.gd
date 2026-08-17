extends RefCounted
class_name StructureCell

const VOID: int = -1
const AIR: int = 0

static func is_valid(value: int) -> bool:
	return value == VOID or is_generic_valid(value)

static func is_generic_valid(value: int) -> bool:
	return value == AIR or is_structure_solid(value)

static func is_structure_solid(value: int) -> bool:
	return BlockId.is_chunk_cube(value)

static func index_of(cell: Vector3i, size: Vector3i) -> int:
	return cell.x + size.x * (cell.z + size.z * cell.y)

static func is_in_bounds(cell: Vector3i, size: Vector3i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.z >= 0 and cell.x < size.x and cell.y < size.y and cell.z < size.z
