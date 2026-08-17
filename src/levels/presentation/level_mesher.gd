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

func create_doorway_seal_mesh(doorway: LevelDoorway) -> ArrayMesh:
	assert(doorway != null)
	var inward_direction := -LevelSocketDefinition.vector_for(doorway.direction)
	var visible_neighbors: Dictionary = {}
	for cell in doorway.aperture_cells:
		visible_neighbors[cell + inward_direction] = true
	return _cube_mesher.create_mesh_from_data(_cube_mesher.build_mesh_data(
		doorway.aperture_cells,
		func(_cell: Vector3i) -> int: return doorway.fill_block_id,
		func(cell: Vector3i) -> bool: return visible_neighbors.has(cell),
	))

func create_mesh_from_data(data: Variant) -> ArrayMesh:
	return _cube_mesher.create_mesh_from_data(data)
