extends RefCounted
class_name LevelMesher

var _cube_mesher: VoxelCubeMesher

func _init(texture_set: BlockTextureSet) -> void:
	_cube_mesher = VoxelCubeMesher.new(texture_set)

func build_mesh_data(state: LevelState) -> Variant:
	return _cube_mesher.build_mesh_data(
		state.get_solid_cells(),
		Callable(state, "get_block_id_at"),
		Callable(state, "is_interior_open")
	)

func create_mesh(state: LevelState) -> ArrayMesh:
	return _cube_mesher.create_mesh_from_data(build_mesh_data(state))

func create_mesh_from_data(data: Variant) -> ArrayMesh:
	return _cube_mesher.create_mesh_from_data(data)
