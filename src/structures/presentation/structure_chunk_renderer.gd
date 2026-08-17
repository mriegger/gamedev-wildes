extends Node3D
class_name StructureChunkRenderer

var _draft: StructureDraft
var _mesher: StructureChunkMesher
var _terrain_material: ShaderMaterial
var _chunks: Dictionary = {}

func setup(draft: StructureDraft, texture_set: BlockTextureSet, terrain_shader: Shader) -> void:
	assert(draft != null)
	assert(texture_set != null)
	assert(terrain_shader != null)
	_draft = draft
	_mesher = StructureChunkMesher.new(texture_set)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = terrain_shader
	_terrain_material.set_shader_parameter("terrain_textures", texture_set.texture_array)
	rebuild_all()

func rebuild_all() -> void:
	assert(_draft != null)
	var chunk_extent := _chunk_extent()
	var cells := _draft.snapshot_cells()
	for y in range(chunk_extent.y):
		for z in range(chunk_extent.z):
			for x in range(chunk_extent.x):
				_rebuild_chunk(Vector3i(x, y, z), cells)

func rebuild_for_cells(changed_cells: Array[Vector3i]) -> void:
	assert(_draft != null)
	var queued: Dictionary = {}
	for cell in changed_cells:
		if not _draft.is_in_bounds(cell):
			continue
		var chunk := _chunk_for_cell(cell)
		queued[chunk] = true
		var local := Vector3i(
			posmod(cell.x, StructureChunkMesher.CHUNK_SIZE),
			posmod(cell.y, StructureChunkMesher.CHUNK_SIZE),
			posmod(cell.z, StructureChunkMesher.CHUNK_SIZE)
		)
		if local.x == 0:
			_queue_chunk(queued, chunk + Vector3i.LEFT)
		elif local.x == StructureChunkMesher.CHUNK_SIZE - 1:
			_queue_chunk(queued, chunk + Vector3i.RIGHT)
		if local.y == 0:
			_queue_chunk(queued, chunk + Vector3i.DOWN)
		elif local.y == StructureChunkMesher.CHUNK_SIZE - 1:
			_queue_chunk(queued, chunk + Vector3i.UP)
		if local.z == 0:
			_queue_chunk(queued, chunk + Vector3i.FORWARD)
		elif local.z == StructureChunkMesher.CHUNK_SIZE - 1:
			_queue_chunk(queued, chunk + Vector3i.BACK)
	var ordered: Array[Vector3i] = []
	for chunk_value in queued:
		ordered.append(chunk_value as Vector3i)
	ordered.sort_custom(_chunk_less)
	var cells := _draft.snapshot_cells()
	for chunk in ordered:
		_rebuild_chunk(chunk, cells)

func _rebuild_chunk(chunk: Vector3i, cells: PackedInt32Array) -> void:
	var data: Variant = _mesher.build_mesh_data(cells, _draft.get_size(), chunk)
	var existing := _chunks.get(chunk) as MeshInstance3D
	if data == null:
		if existing != null:
			_chunks.erase(chunk)
			existing.queue_free()
	else:
		if existing == null:
			existing = MeshInstance3D.new()
			existing.name = "Chunk_%d_%d_%d" % [chunk.x, chunk.y, chunk.z]
			existing.material_override = _terrain_material
			existing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(existing)
			_chunks[chunk] = existing
		existing.mesh = _mesher.create_mesh_from_data(data)

func _queue_chunk(queued: Dictionary, chunk: Vector3i) -> void:
	var extent := _chunk_extent()
	if chunk.x < 0 or chunk.y < 0 or chunk.z < 0:
		return
	if chunk.x >= extent.x or chunk.y >= extent.y or chunk.z >= extent.z:
		return
	queued[chunk] = true

func _chunk_extent() -> Vector3i:
	var size := _draft.get_size()
	return Vector3i(
		ceili(float(size.x) / float(StructureChunkMesher.CHUNK_SIZE)),
		ceili(float(size.y) / float(StructureChunkMesher.CHUNK_SIZE)),
		ceili(float(size.z) / float(StructureChunkMesher.CHUNK_SIZE))
	)

func _chunk_for_cell(cell: Vector3i) -> Vector3i:
	return Vector3i(
		cell.x / StructureChunkMesher.CHUNK_SIZE,
		cell.y / StructureChunkMesher.CHUNK_SIZE,
		cell.z / StructureChunkMesher.CHUNK_SIZE
	)

func _chunk_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z
