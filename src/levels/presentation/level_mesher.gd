extends RefCounted
class_name LevelMesher

const FACE_DIRECTIONS: Array[Vector3i] = [
	Vector3i.UP,
	Vector3i.DOWN,
	Vector3i(1, 0, 0),
	Vector3i(-1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(0, 0, -1),
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

var _top_layers: PackedInt32Array
var _side_layers: PackedInt32Array
var _bottom_layers: PackedInt32Array

func _init(texture_set: BlockTextureSet) -> void:
	assert(texture_set != null)
	_top_layers = texture_set.top_layers.duplicate()
	_side_layers = texture_set.side_layers.duplicate()
	_bottom_layers = texture_set.bottom_layers.duplicate()

func build_mesh_data(state: LevelState) -> Variant:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var texture_layers := PackedVector2Array()
	var indices := PackedInt32Array()
	for cell in state.get_solid_cells():
		var block_id := state.get_block_id_at(cell)
		assert(BlockId.is_chunk_cube(block_id))
		for direction in FACE_DIRECTIONS:
			if not state.is_interior_open(cell + direction):
				continue
			_append_face(
				cell,
				direction,
				_get_texture_layer(block_id, direction),
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

func create_mesh(state: LevelState) -> ArrayMesh:
	return create_mesh_from_data(build_mesh_data(state))

func create_mesh_from_data(data: Variant) -> ArrayMesh:
	if data == null:
		return null
	var mesh_data := data as Dictionary
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_data["vertices"] as PackedVector3Array
	arrays[Mesh.ARRAY_NORMAL] = mesh_data["normals"] as PackedVector3Array
	arrays[Mesh.ARRAY_COLOR] = mesh_data["colors"] as PackedColorArray
	arrays[Mesh.ARRAY_TEX_UV] = mesh_data["uvs"] as PackedVector2Array
	arrays[Mesh.ARRAY_TEX_UV2] = mesh_data["texture_layers"] as PackedVector2Array
	arrays[Mesh.ARRAY_INDEX] = mesh_data["indices"] as PackedInt32Array
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _get_texture_layer(block_id: int, direction: Vector3i) -> int:
	if direction == Vector3i.UP:
		return _top_layers[block_id]
	if direction == Vector3i.DOWN:
		return _bottom_layers[block_id]
	return _side_layers[block_id]

func _append_face(
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
	assert(texture_layer >= 0)
	var face_corners := FACE_CORNERS[direction] as Array
	var face_uvs := TOP_BOTTOM_UVS if direction.y != 0 else SIDE_UVS
	var cell_origin := Vector3(cell)
	var normal := Vector3(direction)
	var shade := _get_face_shade(direction)
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

func _get_face_shade(direction: Vector3i) -> float:
	if direction == Vector3i.UP:
		return 1.0
	if direction == Vector3i.DOWN:
		return 0.82
	if direction.x != 0:
		return 0.94
	return 0.88
