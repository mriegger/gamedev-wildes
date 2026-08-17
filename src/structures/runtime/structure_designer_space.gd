extends VoxelSpace
class_name StructureDesignerSpace

var _draft: StructureDraft

func _init(draft: StructureDraft, p_block_catalog: BlockCatalog) -> void:
	assert(draft != null)
	assert(p_block_catalog != null)
	_draft = draft
	block_catalog = p_block_catalog

func get_block_at(position: Vector3i) -> Variant:
	if is_guide_cell(position):
		return BlockId.Type.STONE
	if not _draft.is_in_bounds(position):
		return null
	if _draft.has_torch(position):
		return BlockId.Type.TORCH
	var value := _draft.get_cell(position)
	if not StructureCell.is_structure_solid(value):
		return null
	return value

func get_block_id_at(position: Vector3i) -> int:
	var block: Variant = get_block_at(position)
	if block == null:
		return BlockId.Type.AIR
	return block as int

func is_solid(position: Vector3i) -> bool:
	if is_guide_cell(position):
		return true
	if not _draft.is_in_bounds(position):
		return false
	return StructureCell.is_structure_solid(_draft.get_cell(position))

func is_raycast_solid(position: Vector3i) -> bool:
	return is_guide_cell(position) or _draft.has_torch(position) or is_solid(position)

func is_face_targetable(block_position: Vector3i, _face_normal: Vector3i) -> bool:
	return is_raycast_solid(block_position)

func get_highest_top(x: int, z: int) -> float:
	var size := _draft.get_size()
	if x < 0 or z < 0 or x >= size.x or z >= size.z:
		return NO_SURFACE_Y
	for y in range(size.y - 1, -1, -1):
		if StructureCell.is_structure_solid(_draft.get_cell(Vector3i(x, y, z))):
			return float(y + 1)
	return 0.0

func get_spawn_position() -> Vector3:
	var size := _draft.get_size()
	var x := clampi(size.x / 2, 0, size.x - 1)
	var z := clampi(size.z / 2, 0, size.z - 1)
	return Vector3(float(x) + 0.5, get_highest_top(x, z), float(z) + 0.5)

func is_guide_cell(position: Vector3i) -> bool:
	var size := _draft.get_size()
	return position.y == -1 and position.x >= 0 and position.z >= 0 and position.x < size.x and position.z < size.z
