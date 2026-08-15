extends RefCounted
class_name LevelMesher

var _cube_mesher: VoxelCubeMesher

func _init(texture_set: BlockTextureSet) -> void:
	_cube_mesher = VoxelCubeMesher.new(texture_set)

func build_mesh_data(state: LevelState) -> Variant:
	return build_mesh_data_for_cells(state, state.get_solid_cells())

func build_mesh_data_for_cells(state: LevelState, solid_cells: Array[Vector3i]) -> Variant:
	return _cube_mesher.build_mesh_data(
		solid_cells,
		Callable(state, "get_block_id_at"),
		Callable(state, "is_base_interior_open")
	)

func create_mesh_for_cells(state: LevelState, solid_cells: Array[Vector3i]) -> ArrayMesh:
	return _cube_mesher.create_mesh_from_data(build_mesh_data_for_cells(state, solid_cells))

func create_uniform_block_mesh(state: LevelState, cells: Array[Vector3i], block_id: int) -> ArrayMesh:
	assert(StructureCell.is_structure_solid(block_id))
	var occupied: Dictionary = {}
	for cell in cells:
		occupied[cell] = true
	return _cube_mesher.create_mesh_from_data(_cube_mesher.build_mesh_data(
		cells,
		func(_cell: Vector3i) -> int: return block_id,
		func(cell: Vector3i) -> bool: return not occupied.has(cell) and state.is_base_interior_open(cell),
	))

func create_mesh_from_data(data: Variant) -> ArrayMesh:
	return _cube_mesher.create_mesh_from_data(data)
