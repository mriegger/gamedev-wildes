extends RefCounted
class_name VoxelSpace

const NO_SURFACE_Y: float = -9999.0
const WATER_SURFACE_HEIGHT: float = 0.75

var block_catalog: BlockCatalog

func get_block_at(_position: Vector3i) -> Variant:
	return null

func get_block_id_at(position: Vector3i) -> int:
	var block: Variant = get_block_at(position)
	if block == null:
		return BlockId.Type.AIR
	return block as int

func is_solid(position: Vector3i) -> bool:
	var block: Variant = get_block_at(position)
	return block != null and block_catalog.is_solid(block as int)

func is_raycast_solid(position: Vector3i) -> bool:
	var block: Variant = get_block_at(position)
	return block != null and block_catalog.is_raycast_solid(block as int)

func get_interaction_bounds(position: Vector3i) -> AABB:
	var block: Variant = get_block_at(position)
	if block == null or block_catalog == null:
		return AABB(Vector3(position), Vector3.ONE)
	var local_bounds := block_catalog.get_interaction_bounds(block as int)
	return AABB(Vector3(position) + local_bounds.position, local_bounds.size)

func get_highest_top(_x: int, _z: int) -> float:
	return NO_SURFACE_Y

func get_spawn_position() -> Vector3:
	return Vector3.ZERO

func is_face_targetable(block_position: Vector3i, _face_normal: Vector3i) -> bool:
	return is_raycast_solid(block_position)
