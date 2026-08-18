extends RefCounted
class_name AnvilCoordinator

signal closed

var voxel_world: VoxelWorld
var active_position: Vector3i
var active_definition: CraftingStationBlockDefinition

func setup(p_voxel_world: VoxelWorld) -> void:
	assert(p_voxel_world != null)
	assert(voxel_world == null)
	voxel_world = p_voxel_world
	voxel_world.block_edit_committed.connect(_on_block_edit_committed)

func try_open(position: Vector3i, definition: CraftingStationBlockDefinition) -> bool:
	if voxel_world == null or definition == null:
		return false
	var block_id := voxel_world.get_block_id_at(position)
	if block_id == BlockId.Type.AIR:
		return false
	if voxel_world.block_catalog.get_definition(block_id).crafting_station != definition:
		return false
	active_position = position
	active_definition = definition
	return true

func close() -> void:
	if active_definition == null:
		return
	active_definition = null
	closed.emit()

func _on_block_edit_committed(edit: BlockEdit) -> void:
	if active_definition == null or not edit.is_success() or not edit.is_mine():
		return
	if edit.pos == active_position and edit.old_id == BlockId.Type.ANVIL:
		close()
