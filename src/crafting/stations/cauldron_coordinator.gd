extends CraftingStationCoordinator
class_name CauldronCoordinator

func setup(p_voxel_world: VoxelWorld) -> void:
	setup_station(p_voxel_world, &"cauldron", BlockId.Type.CAULDRON)
