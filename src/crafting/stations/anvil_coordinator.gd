extends CraftingStationCoordinator
class_name AnvilCoordinator

func setup(p_voxel_world: VoxelWorld) -> void:
	setup_station(p_voxel_world, &"anvil", BlockId.Type.ANVIL)
