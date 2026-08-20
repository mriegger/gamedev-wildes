extends RefCounted
class_name VoxelWorldTestFixture

static func commit_mine(world: VoxelWorld, position: Vector3i) -> PreparedVoxelWorldChange:
	var prepared := world.prepare_mine_block(position)
	if prepared == null or not world._commit_prepared_change(prepared):
		return null
	return prepared

static func commit_place(
	world: VoxelWorld,
	position: Vector3i,
	block_id: int,
	attach_direction: Vector3i = Vector3i.ZERO,
) -> PreparedVoxelWorldChange:
	var prepared := world.prepare_place_block(position, block_id, attach_direction)
	if prepared == null or not world._commit_prepared_change(prepared):
		return null
	return prepared

static func commit_place_emplacement(
	world: VoxelWorld,
	anchor: Vector3i,
	block_id: int,
) -> PreparedVoxelWorldChange:
	var prepared := world.prepare_place_emplacement(anchor, block_id)
	if prepared == null or not world._commit_prepared_change(prepared):
		return null
	return prepared

static func commit_replace(
	world: VoxelWorld,
	position: Vector3i,
	expected_block_id: int,
	block_id: int,
) -> PreparedVoxelWorldChange:
	var prepared := world.prepare_replace_block(position, expected_block_id, block_id)
	if prepared == null or not world._commit_prepared_change(prepared):
		return null
	return prepared
