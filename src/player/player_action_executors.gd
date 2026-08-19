extends RefCounted
class_name PlayerActionExecutors

var mining: MiningActionExecutor
var tilling: TillingActionExecutor
var placement: BlockPlacementActionExecutor

func setup(
	p_mining: MiningActionExecutor,
	p_tilling: TillingActionExecutor,
	p_placement: BlockPlacementActionExecutor,
) -> bool:
	if (
		p_mining == null
		or p_tilling == null
		or p_placement == null
		or mining != null
		or tilling != null
		or placement != null
	):
		return false
	mining = p_mining
	tilling = p_tilling
	placement = p_placement
	return true

func bind_world(voxel_world: VoxelWorld) -> void:
	assert(voxel_world != null and mining != null and tilling != null and placement != null)
	mining.bind_world(voxel_world)
	tilling.bind_world(voxel_world)
	placement.bind_world(voxel_world)

func unbind_world() -> void:
	if mining == null:
		return
	mining.unbind_world()
	tilling.unbind_world()
	placement.unbind_world()
