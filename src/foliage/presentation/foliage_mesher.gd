extends RefCounted
class_name FoliageMesher

const HASH_MASK: int = 0xffffffff
const HASH_RANGE: float = 4294967296.0
const X_PRIME: int = 73856093
const Y_PRIME: int = 83492791
const Z_PRIME: int = 19349663
const LAYER_PRIME: int = 2654435761
const MIX_PRIME: int = 1274126177
const ROTATION_SALT: int = 913157523
const WIDTH_SALT: int = 1597334677
const HEIGHT_SALT: int = 381201581
const OFFSET_X_SALT: int = 1103515245
const OFFSET_Z_SALT: int = 214013
const MIN_PLANE_WIDTH: float = 0.82
const MAX_PLANE_WIDTH: float = 0.96
const MIN_PLANE_HEIGHT: float = 0.90
const MAX_PLANE_HEIGHT: float = 1.03
const MAX_CENTER_OFFSET: float = 0.08
const VERTICES_PER_CELL: int = 8
const INDICES_PER_CELL: int = 12

var _texture_layers: PackedInt32Array
var _texture_uv_rects: Array[Rect2]
var _seed_value: int

func _init(texture_set: FoliageTextureSet, seed_value: int) -> void:
	assert(texture_set != null)
	_texture_layers = texture_set.texture_layers.duplicate()
	_texture_uv_rects = texture_set.texture_uv_rects.duplicate()
	_seed_value = seed_value

func build_mesh_data(cells: PackedInt32Array) -> Variant:
	assert(cells.size() % FoliageCellSnapshot.STRIDE == 0)
	var cell_count: int = cells.size() / FoliageCellSnapshot.STRIDE
	if cell_count == 0:
		return null
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var texture_layers := PackedVector2Array()
	var indices := PackedInt32Array()
	vertices.resize(cell_count * VERTICES_PER_CELL)
	uvs.resize(cell_count * VERTICES_PER_CELL)
	texture_layers.resize(cell_count * VERTICES_PER_CELL)
	indices.resize(cell_count * INDICES_PER_CELL)
	for cell_index in range(cell_count):
		var data_index := cell_index * FoliageCellSnapshot.STRIDE
		var cell := Vector3i(cells[data_index], cells[data_index + 1], cells[data_index + 2])
		var block_id := cells[data_index + 3]
		assert(BlockId.is_foliage(block_id))
		_append_crossed_quads(
			cell,
			_texture_layers[block_id],
			_texture_uv_rects[block_id],
			cell_index * VERTICES_PER_CELL,
			cell_index * INDICES_PER_CELL,
			vertices,
			uvs,
			texture_layers,
			indices
		)
	return {
		"vertices": vertices,
		"uvs": uvs,
		"texture_layers": texture_layers,
		"indices": indices,
	}

func create_mesh_from_data(data: Variant) -> ArrayMesh:
	if data == null:
		return null
	var mesh_data := data as Dictionary
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"] as PackedVector3Array
	arrays[Mesh.ARRAY_TEX_UV] = mesh_data["uvs"] as PackedVector2Array
	arrays[Mesh.ARRAY_TEX_UV2] = mesh_data["texture_layers"] as PackedVector2Array
	arrays[Mesh.ARRAY_INDEX] = mesh_data["indices"] as PackedInt32Array
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _append_crossed_quads(
	cell: Vector3i,
	texture_layer: int,
	uv_rect: Rect2,
	vertex_index: int,
	index_index: int,
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	texture_layers: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	assert(texture_layer >= 0)
	var layer_uv := Vector2(float(texture_layer), 0.0)
	var variation_base := int(_seed_value & HASH_MASK)
	variation_base = int((variation_base ^ ((cell.x * X_PRIME) & HASH_MASK) ^ ((cell.y * Y_PRIME) & HASH_MASK) ^ ((cell.z * Z_PRIME) & HASH_MASK) ^ ((texture_layer * LAYER_PRIME) & HASH_MASK)) & HASH_MASK)
	var center := Vector3(cell) + Vector3(0.5, 0.0, 0.5)
	center.x += lerpf(-MAX_CENTER_OFFSET, MAX_CENTER_OFFSET, _variation(variation_base, OFFSET_X_SALT))
	center.z += lerpf(-MAX_CENTER_OFFSET, MAX_CENTER_OFFSET, _variation(variation_base, OFFSET_Z_SALT))
	var plane_width := lerpf(MIN_PLANE_WIDTH, MAX_PLANE_WIDTH, _variation(variation_base, WIDTH_SALT))
	var plane_height := lerpf(MIN_PLANE_HEIGHT, MAX_PLANE_HEIGHT, _variation(variation_base, HEIGHT_SALT))
	var angle := _variation(variation_base, ROTATION_SALT) * PI * 0.5 + PI * 0.25
	var first_direction := Vector3(cos(angle), 0.0, sin(angle)) * plane_width * 0.5
	var second_direction := Vector3(-first_direction.z, 0.0, first_direction.x)
	_write_quad(center, first_direction, plane_height, uv_rect, layer_uv, vertex_index, index_index, vertices, uvs, texture_layers, indices)
	_write_quad(center, second_direction, plane_height, uv_rect, layer_uv, vertex_index + 4, index_index + 6, vertices, uvs, texture_layers, indices)

func _write_quad(
	center: Vector3,
	half_direction: Vector3,
	height: float,
	uv_rect: Rect2,
	layer_uv: Vector2,
	vertex_index: int,
	index_index: int,
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	texture_layers: PackedVector2Array,
	indices: PackedInt32Array
) -> void:
	var left := center - half_direction * uv_rect.size.x
	var right := center + half_direction * uv_rect.size.x
	var bottom_offset := Vector3.UP * height * (1.0 - uv_rect.end.y)
	var top_offset := Vector3.UP * height * (1.0 - uv_rect.position.y)
	vertices[vertex_index] = left + bottom_offset
	vertices[vertex_index + 1] = right + bottom_offset
	vertices[vertex_index + 2] = right + top_offset
	vertices[vertex_index + 3] = left + top_offset
	uvs[vertex_index] = uv_rect.position + Vector2(0.0, uv_rect.size.y)
	uvs[vertex_index + 1] = uv_rect.end
	uvs[vertex_index + 2] = uv_rect.position + Vector2(uv_rect.size.x, 0.0)
	uvs[vertex_index + 3] = uv_rect.position
	for offset in range(4):
		texture_layers[vertex_index + offset] = layer_uv
	indices[index_index] = vertex_index
	indices[index_index + 1] = vertex_index + 1
	indices[index_index + 2] = vertex_index + 2
	indices[index_index + 3] = vertex_index
	indices[index_index + 4] = vertex_index + 2
	indices[index_index + 5] = vertex_index + 3

func _variation(base: int, salt: int) -> float:
	var value := int((base ^ salt) & HASH_MASK)
	value = int((value ^ (value >> 13)) & HASH_MASK)
	value = int((value * MIX_PRIME) & HASH_MASK)
	value = int((value ^ (value >> 16)) & HASH_MASK)
	return float(value) / HASH_RANGE
