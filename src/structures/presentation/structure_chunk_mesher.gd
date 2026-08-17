extends RefCounted
class_name StructureChunkMesher

const CHUNK_SIZE: int = 16

var _cube_mesher: VoxelCubeMesher

func _init(texture_set: BlockTextureSet) -> void:
	_cube_mesher = VoxelCubeMesher.new(texture_set)

func build_mesh_data(cells: Dictionary, size: Vector3i, chunk: Vector3i) -> Variant:
	var solid_cells: Array[Vector3i] = []
	var start := chunk * CHUNK_SIZE
	var end := Vector3i(
		mini(start.x + CHUNK_SIZE, size.x),
		mini(start.y + CHUNK_SIZE, size.y),
		mini(start.z + CHUNK_SIZE, size.z)
	)
	for y in range(start.y, end.y):
		for z in range(start.z, end.z):
			for x in range(start.x, end.x):
				var cell := Vector3i(x, y, z)
				if BlockId.is_chunk_cube(_cell_at(cells, size, cell)):
					solid_cells.append(cell)
	var block_query := func(cell: Vector3i) -> int:
		return _cell_at(cells, size, cell)
	var face_open_query := func(cell: Vector3i) -> bool:
		if not StructureCell.is_in_bounds(cell, size):
			return true
		return _cell_at(cells, size, cell) == StructureCell.AIR
	return _cube_mesher.build_mesh_data(solid_cells, block_query, face_open_query)

func create_mesh_from_data(data: Variant) -> ArrayMesh:
	return _cube_mesher.create_mesh_from_data(data)

func _cell_at(cells: Dictionary, size: Vector3i, cell: Vector3i) -> int:
	if not StructureCell.is_in_bounds(cell, size):
		return StructureCell.VOID
	assert(cells.has(cell))
	return int(cells[cell])
