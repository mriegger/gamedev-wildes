extends SceneTree

const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const TERRAIN_SHADER_PATH: String = "res://levels/presentation/level_terrain.gdshader"
const FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i.RIGHT,
	Vector3i.LEFT,
	Vector3i.BACK,
	Vector3i.FORWARD,
]
const FACE_CORNERS: Dictionary = {
	Vector3i.UP: [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)],
	Vector3i.DOWN: [Vector3(0, 0, 1), Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0)],
	Vector3i.RIGHT: [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0)],
	Vector3i.LEFT: [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	Vector3i.BACK: [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	Vector3i.FORWARD: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
}
const TOP_BOTTOM_UVS: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const SIDE_UVS: Array[Vector2] = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]

var _errors: Array[String] = []
var _block_catalog: BlockCatalog
var _texture_set: BlockTextureSet
var _terrain_shader: Shader

class TrackingRenderer extends StructureChunkRenderer:
	var rebuilt_chunks: Array[Vector3i] = []
	var rebuild_counts: Dictionary = {}

	func rebuild_all() -> void:
		rebuilt_chunks.clear()
		super.rebuild_all()

	func rebuild_for_cells(changed_cells: Array[Vector3i]) -> void:
		rebuilt_chunks.clear()
		super.rebuild_for_cells(changed_cells)

	func _rebuild_chunk(chunk: Vector3i) -> void:
		super._rebuild_chunk(chunk)
		rebuilt_chunks.append(chunk)
		rebuild_counts[chunk] = int(rebuild_counts.get(chunk, 0)) + 1

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_block_catalog = load(BLOCK_CATALOG_PATH) as BlockCatalog
	_terrain_shader = load(TERRAIN_SHADER_PATH) as Shader
	_expect(_block_catalog != null and _block_catalog.validate(), "block catalog did not load or validate")
	_expect(_terrain_shader != null, "terrain shader did not load")
	if _block_catalog == null or _terrain_shader == null:
		_finish()
		return
	_texture_set = BlockTextureSet.new(_block_catalog)
	_test_level_mesh_equivalence()
	_test_structure_chunk_mesher()
	await _test_renderer_locality()
	await _test_empty_chunk_removal()
	await _test_maximum_chunk_bounds()
	_finish()

func _test_level_mesh_equivalence() -> void:
	var solids: Dictionary = {
		Vector3i(0, 0, 0): BlockId.Type.STONE,
		Vector3i(0, 0, 1): BlockId.Type.LOG,
		Vector3i(1, 0, 0): BlockId.Type.DIRT,
	}
	var cells := solids.duplicate()
	for cell_value in solids:
		var cell := cell_value as Vector3i
		for direction in FACE_DIRECTIONS:
			var neighbor := cell + direction
			if not cells.has(neighbor):
				cells[neighbor] = StructureCell.AIR
	cells[Vector3i(0, 2, 0)] = StructureCell.AIR
	cells[Vector3i(1, 2, 0)] = StructureCell.AIR
	var state := LevelState.new(
		_block_catalog,
		cells,
		Vector3i(0, 1, 0),
		LevelSocketDefinition.Direction.NORTH,
		Vector3i(1, 1, 0),
		LevelSocketDefinition.Direction.WEST,
		Vector3i(-2, -2, -2),
		Vector3i(3, 3, 3)
	)
	var expected: Variant = _build_legacy_level_mesh_data(state)
	var actual: Variant = LevelMesher.new(_texture_set).build_mesh_data(state)
	_expect(actual != null and expected != null, "level mesher returned no data for the equivalence fixture")
	if actual == null or expected == null:
		return
	for key in ["vertices", "normals", "colors", "uvs", "texture_layers", "indices"]:
		_expect(actual[key] == expected[key], "shared cube mesher changed legacy level %s data" % key)

func _test_structure_chunk_mesher() -> void:
	var size := Vector3i(17, 1, 1)
	var draft := StructureDraft.create_generic(size)
	_expect(draft.try_place_block(Vector3i(15, 0, 0), BlockId.Type.STONE).succeeded, "first mesher fixture block was rejected")
	_expect(draft.try_place_block(Vector3i(16, 0, 0), BlockId.Type.DIRT).succeeded, "second mesher fixture block was rejected")
	var mesher := StructureChunkMesher.new(_texture_set)
	var first := mesher.build_mesh_data(draft.copy_cells_for_chunk(Vector3i.ZERO, StructureChunkMesher.CHUNK_SIZE), size, Vector3i.ZERO) as Dictionary
	var partial := mesher.build_mesh_data(draft.copy_cells_for_chunk(Vector3i(1, 0, 0), StructureChunkMesher.CHUNK_SIZE), size, Vector3i(1, 0, 0)) as Dictionary
	_expect(first != null and (first["vertices"] as PackedVector3Array).size() == 20, "first chunk did not hide its cross-chunk shared face")
	_expect(partial != null and (partial["vertices"] as PackedVector3Array).size() == 20, "partial chunk did not render the targetable plot exterior")
	_expect(draft.try_remove_block(Vector3i(16, 0, 0)).succeeded, "mesher fixture block removal was rejected")
	var beside_air := mesher.build_mesh_data(draft.copy_cells_for_chunk(Vector3i.ZERO, StructureChunkMesher.CHUNK_SIZE), size, Vector3i.ZERO) as Dictionary
	_expect(beside_air != null and (beside_air["vertices"] as PackedVector3Array).size() == 24, "in-bounds AIR did not expose its neighboring face")
	var module_definition := LevelModuleDefinition.new()
	module_definition.module_id = &"void_rendering"
	module_definition.size = size
	module_definition.cells.resize(size.x * size.y * size.z)
	module_definition.cells.fill(StructureCell.AIR)
	module_definition.cells[StructureCell.index_of(Vector3i(15, 0, 0), size)] = BlockId.Type.STONE
	module_definition.cells[StructureCell.index_of(Vector3i(16, 0, 0), size)] = StructureCell.VOID
	var module := StructureDraft.restore_level_module(module_definition, ProjectSettings.globalize_path("res://../void_rendering.tres"))
	_expect(module != null, "VOID rendering module did not restore")
	if module != null:
		var beside_void := mesher.build_mesh_data(module.copy_cells_for_chunk(Vector3i.ZERO, StructureChunkMesher.CHUNK_SIZE), size, Vector3i.ZERO) as Dictionary
		_expect(beside_void != null and (beside_void["vertices"] as PackedVector3Array).size() == 20, "in-bounds VOID exposed its neighboring face")

func _test_renderer_locality() -> void:
	var draft := StructureDraft.create_generic(Vector3i(32, 32, 32))
	var seeded_cells: Array[Vector3i] = [
		Vector3i(1, 1, 1),
		Vector3i(17, 1, 1),
		Vector3i(1, 17, 1),
		Vector3i(1, 1, 17),
		Vector3i(17, 17, 17),
	]
	for cell in seeded_cells:
		_expect(draft.try_place_block(cell, BlockId.Type.STONE).succeeded, "failed to seed renderer chunk at %s" % cell)
	var renderer := _create_renderer(draft)
	var owner := Vector3i.ZERO
	var x_neighbor := Vector3i(1, 0, 0)
	var y_neighbor := Vector3i(0, 1, 0)
	var z_neighbor := Vector3i(0, 0, 1)
	var diagonal := Vector3i(1, 1, 1)
	_expect(_chunk_count(renderer) == 5, "seeded renderer created %d chunks instead of 5" % _chunk_count(renderer))
	var owner_id := _chunk_instance_id(renderer, owner)
	var x_id := _chunk_instance_id(renderer, x_neighbor)
	var y_id := _chunk_instance_id(renderer, y_neighbor)
	var z_id := _chunk_instance_id(renderer, z_neighbor)
	var diagonal_id := _chunk_instance_id(renderer, diagonal)
	var owner_count := _rebuild_count(renderer, owner)
	var interior_change := draft.try_place_block(Vector3i(2, 2, 2), BlockId.Type.DIRT)
	_expect(interior_change.succeeded, "interior edit was rejected")
	if interior_change.succeeded:
		renderer.rebuild_for_cells(interior_change.changed_cells)
	_expect(_last_rebuilt_chunks(renderer) == [owner], "interior edit rebuilt chunks outside its owner")
	_expect(_rebuild_count(renderer, owner) == owner_count + 1, "interior edit did not rebuild its owner exactly once")
	_expect(_chunk_instance_id(renderer, owner) == owner_id, "interior edit replaced its chunk instance")
	_expect(_chunk_instance_id(renderer, x_neighbor) == x_id, "interior edit replaced the x-neighbor instance")
	_expect(_chunk_instance_id(renderer, y_neighbor) == y_id, "interior edit replaced the y-neighbor instance")
	_expect(_chunk_instance_id(renderer, z_neighbor) == z_id, "interior edit replaced the z-neighbor instance")
	_expect(_chunk_instance_id(renderer, diagonal) == diagonal_id, "interior edit replaced the diagonal instance")
	var boundary_change := draft.try_place_block(Vector3i(15, 15, 15), BlockId.Type.LOG)
	_expect(boundary_change.succeeded, "boundary edit was rejected")
	if boundary_change.succeeded:
		renderer.rebuild_for_cells(boundary_change.changed_cells)
	var expected_boundary: Array[Vector3i] = [owner, z_neighbor, y_neighbor, x_neighbor]
	_expect(_last_rebuilt_chunks(renderer) == expected_boundary, "corner-boundary edit did not rebuild only its axial neighbors")
	_expect(_chunk_instance_id(renderer, owner) == owner_id, "boundary edit replaced its owner instance")
	_expect(_chunk_instance_id(renderer, x_neighbor) == x_id, "boundary edit replaced the x-neighbor instance")
	_expect(_chunk_instance_id(renderer, y_neighbor) == y_id, "boundary edit replaced the y-neighbor instance")
	_expect(_chunk_instance_id(renderer, z_neighbor) == z_id, "boundary edit replaced the z-neighbor instance")
	_expect(_chunk_instance_id(renderer, diagonal) == diagonal_id, "boundary edit rebuilt the diagonal chunk")
	var first_batch_change := draft.try_place_block(Vector3i(16, 15, 15), BlockId.Type.GRASS)
	var second_batch_change := draft.try_place_block(Vector3i(17, 15, 15), BlockId.Type.SAND)
	_expect(first_batch_change.succeeded and second_batch_change.succeeded, "batch fixture edits were rejected")
	var batch_cells: Array[Vector3i] = []
	if first_batch_change.succeeded and second_batch_change.succeeded:
		batch_cells.append(first_batch_change.changed_cells[0])
		batch_cells.append(first_batch_change.changed_cells[0])
		batch_cells.append(second_batch_change.changed_cells[0])
		batch_cells.append(second_batch_change.changed_cells[0])
	var expected_batch: Array[Vector3i] = [
		owner,
		x_neighbor,
		Vector3i(1, 0, 1),
		Vector3i(1, 1, 0),
	]
	var counts_before: Dictionary = {}
	for chunk in expected_batch:
		counts_before[chunk] = _rebuild_count(renderer, chunk)
	if not batch_cells.is_empty():
		renderer.rebuild_for_cells(batch_cells)
	_expect(_last_rebuilt_chunks(renderer) == expected_batch, "batched boundary edits were not deduplicated")
	for chunk in expected_batch:
		_expect(_rebuild_count(renderer, chunk) == int(counts_before[chunk]) + 1, "batch rebuilt chunk %s more than once" % chunk)
	_expect(_chunk_instance_id(renderer, diagonal) == diagonal_id, "batch rebuild replaced an unaffected diagonal instance")
	renderer.queue_free()
	await process_frame

func _test_empty_chunk_removal() -> void:
	var draft := StructureDraft.create_generic(Vector3i(32, 16, 16))
	var retained_cell := Vector3i(1, 1, 1)
	var removed_cell := Vector3i(17, 1, 1)
	_expect(draft.try_place_block(retained_cell, BlockId.Type.STONE).succeeded, "failed to seed retained chunk")
	_expect(draft.try_place_block(removed_cell, BlockId.Type.DIRT).succeeded, "failed to seed removable chunk")
	var renderer := _create_renderer(draft)
	var retained_chunk := Vector3i.ZERO
	var removed_chunk := Vector3i(1, 0, 0)
	var retained_id := _chunk_instance_id(renderer, retained_chunk)
	var removed_instance := _chunk_instance(renderer, removed_chunk)
	_expect(removed_instance != null and _chunk_count(renderer) == 2, "empty-removal fixture did not create two chunks")
	var change := draft.try_remove_block(removed_cell)
	_expect(change.succeeded, "last block removal was rejected")
	if change.succeeded:
		renderer.rebuild_for_cells(change.changed_cells)
	_expect(_last_rebuilt_chunks(renderer) == [removed_chunk], "last block removal rebuilt another chunk")
	_expect(_chunk_instance(renderer, removed_chunk) == null, "empty chunk remained in the renderer index")
	_expect(_chunk_count(renderer) == 1, "empty chunk did not reduce the renderer chunk count")
	_expect(_chunk_instance_id(renderer, retained_chunk) == retained_id, "empty chunk removal replaced the retained instance")
	await process_frame
	_expect(not is_instance_valid(removed_instance), "empty chunk mesh instance was not freed")
	renderer.queue_free()
	await process_frame

func _test_maximum_chunk_bounds() -> void:
	var draft := StructureDraft.create_generic(Vector3i(64, 64, 64))
	var maximum_cell := Vector3i(63, 63, 63)
	_expect(draft.try_place_block(maximum_cell, BlockId.Type.STONE).succeeded, "maximum-boundary block was rejected")
	var renderer := _create_renderer(draft)
	var maximum_chunk := Vector3i(3, 3, 3)
	var maximum_id := _chunk_instance_id(renderer, maximum_chunk)
	var count_before := _rebuild_count(renderer, maximum_chunk)
	var repeated_cells: Array[Vector3i] = [maximum_cell, maximum_cell]
	renderer.rebuild_for_cells(repeated_cells)
	_expect(_last_rebuilt_chunks(renderer) == [maximum_chunk], "maximum-boundary edit queued an out-of-bounds neighbor chunk")
	_expect(_rebuild_count(renderer, maximum_chunk) == count_before + 1, "maximum-boundary batch rebuilt its chunk more than once")
	_expect(_chunk_count(renderer) == 1, "maximum-size plot created empty mesh instances")
	_expect(_chunk_instance_id(renderer, maximum_chunk) == maximum_id, "maximum-boundary rebuild replaced its chunk instance")
	renderer.queue_free()
	await process_frame

func _create_renderer(draft: StructureDraft) -> TrackingRenderer:
	var renderer := TrackingRenderer.new()
	root.add_child(renderer)
	renderer.setup(draft, _texture_set, _terrain_shader)
	return renderer

func _chunk_instance_id(renderer: StructureChunkRenderer, chunk: Vector3i) -> int:
	var instance := _chunk_instance(renderer, chunk)
	if instance == null:
		return 0
	return instance.get_instance_id()

func _chunk_instance(renderer: StructureChunkRenderer, chunk: Vector3i) -> MeshInstance3D:
	return renderer._chunks.get(chunk) as MeshInstance3D

func _last_rebuilt_chunks(renderer: StructureChunkRenderer) -> Array[Vector3i]:
	return (renderer as TrackingRenderer).rebuilt_chunks.duplicate()

func _rebuild_count(renderer: StructureChunkRenderer, chunk: Vector3i) -> int:
	return int((renderer as TrackingRenderer).rebuild_counts.get(chunk, 0))

func _chunk_count(renderer: StructureChunkRenderer) -> int:
	return renderer._chunks.size()

func _build_legacy_level_mesh_data(state: LevelState) -> Variant:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var texture_layers := PackedVector2Array()
	var indices := PackedInt32Array()
	for cell in state.get_solid_cells():
		var block_id := state.get_block_id_at(cell)
		for direction in FACE_DIRECTIONS:
			if not state.is_interior_open(cell + direction):
				continue
			_append_legacy_face(
				cell,
				direction,
				_legacy_texture_layer(block_id, direction),
				vertices,
				normals,
				colors,
				uvs,
				texture_layers,
				indices
			)
	if vertices.is_empty():
		return null
	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"uvs": uvs,
		"texture_layers": texture_layers,
		"indices": indices,
	}

func _legacy_texture_layer(block_id: int, direction: Vector3i) -> int:
	if direction == Vector3i.UP:
		return _texture_set.top_layers[block_id]
	if direction == Vector3i.DOWN:
		return _texture_set.bottom_layers[block_id]
	return _texture_set.side_layers[block_id]

func _append_legacy_face(
	cell: Vector3i,
	direction: Vector3i,
	texture_layer: int,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	uvs: PackedVector2Array,
	texture_layers: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	var face_corners := FACE_CORNERS[direction] as Array
	var face_uvs := TOP_BOTTOM_UVS if direction.y != 0 else SIDE_UVS
	var cell_origin := Vector3(cell)
	var normal := Vector3(direction)
	var shade := _legacy_face_shade(direction)
	var base_index := vertices.size()
	var layer_uv := Vector2(float(texture_layer), 0.0)
	for index in range(4):
		vertices.append(cell_origin + (face_corners[index] as Vector3))
		normals.append(normal)
		colors.append(Color(shade, shade, shade, 1.0))
		uvs.append(face_uvs[index])
		texture_layers.append(layer_uv)
	indices.append(base_index)
	indices.append(base_index + 1)
	indices.append(base_index + 2)
	indices.append(base_index)
	indices.append(base_index + 2)
	indices.append(base_index + 3)

func _legacy_face_shade(direction: Vector3i) -> float:
	if direction == Vector3i.UP:
		return 1.0
	if direction == Vector3i.DOWN:
		return 0.82
	if direction.x != 0:
		return 0.94
	return 0.88

func _finish() -> void:
	if _errors.is_empty():
		print("STRUCTURE_CHUNK_RENDERING PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
