extends RefCounted
class_name CraftingStationCoordinator

signal closed

var voxel_world: VoxelWorld
var station_id: StringName
var block_id: int = BlockId.Type.AIR
var active_position: Vector3i
var active_definition: CraftingStationBlockDefinition

func setup_station(p_voxel_world: VoxelWorld, p_station_id: StringName, p_block_id: int) -> void:
	assert(p_voxel_world != null)
	assert(voxel_world == null)
	assert(not p_station_id.is_empty())
	assert(BlockId.is_valid(p_block_id) and p_block_id != BlockId.Type.AIR)
	voxel_world = p_voxel_world
	station_id = p_station_id
	block_id = p_block_id
	voxel_world.block_edit_committed.connect(_on_block_edit_committed)

func try_open(position: Vector3i, definition: CraftingStationBlockDefinition) -> bool:
	if voxel_world == null or definition == null or definition.id != station_id:
		return false
	var emplacement_anchor: Variant = voxel_world.get_emplacement_anchor(position)
	var station_position := emplacement_anchor as Vector3i if emplacement_anchor is Vector3i else position
	var current_block_id := voxel_world.get_block_id_at(station_position)
	if current_block_id != block_id:
		return false
	if voxel_world.block_catalog.get_definition(current_block_id).crafting_station != definition:
		return false
	active_position = station_position
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
	if edit.pos == active_position and edit.old_id == block_id:
		close()
