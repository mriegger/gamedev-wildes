extends Node3D
class_name PumpkinPatchPreview

const PATCH_WIDTH: int = 5
const PATCH_DEPTH: int = 4
const SEARCH_RADIUS: int = 10
const MIN_PLAYER_DISTANCE_SQUARED: float = 9.0
const MODEL_FIT_SIZE: float = 1.755
const SOIL_SURFACE_OFFSET: float = 0.008
const GROWTH_STATE_COUNT: int = 6
const VALID_SURFACE_BLOCKS: Array[int] = [
	BlockId.Type.GRASS,
	BlockId.Type.DIRT,
	BlockId.Type.FARMLAND_DRY,
]

@export var soil_texture: Texture2D
@export var pumpkin_scenes: Array[PackedScene] = []

var _voxel_world: VoxelWorld
var _player: Node3D
var _preview_root: Node3D
var _random := RandomNumberGenerator.new()

func setup(p_voxel_world: VoxelWorld, p_player: Node3D) -> void:
	assert(p_voxel_world != null and p_player != null)
	assert(_voxel_world == null and _player == null)
	_voxel_world = p_voxel_world
	_player = p_player
	_random.randomize()

func spawn_patch() -> bool:
	if _voxel_world == null or _player == null or soil_texture == null or pumpkin_scenes.size() != GROWTH_STATE_COUNT:
		return false
	var origin := _find_patch_origin()
	if origin.y < 0:
		return false
	var patch := _build_patch(origin)
	if patch == null:
		return false
	if _preview_root != null:
		_preview_root.free()
	_preview_root = patch
	add_child(_preview_root)
	return true

func _find_patch_origin() -> Vector3i:
	var player_cell := Vector3i(floori(_player.global_position.x), 0, floori(_player.global_position.z))
	var best_origin := Vector3i(0, -1, 0)
	var best_distance_squared := INF
	for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dz in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var origin := Vector3i(player_cell.x + dx, 0, player_cell.z + dz)
			var center := Vector2(float(origin.x) + float(PATCH_WIDTH) * 0.5, float(origin.z) + float(PATCH_DEPTH) * 0.5)
			var player_center := Vector2(_player.global_position.x, _player.global_position.z)
			var distance_squared := center.distance_squared_to(player_center)
			if distance_squared < MIN_PLAYER_DISTANCE_SQUARED or distance_squared >= best_distance_squared:
				continue
			var surface_y := _get_patch_surface_y(origin.x, origin.z)
			if surface_y < 0:
				continue
			best_origin = Vector3i(origin.x, surface_y, origin.z)
			best_distance_squared = distance_squared
	return best_origin

func _get_patch_surface_y(origin_x: int, origin_z: int) -> int:
	var surface_y := -1
	for x_offset in range(PATCH_WIDTH):
		for z_offset in range(PATCH_DEPTH):
			var x := origin_x + x_offset
			var z := origin_z + z_offset
			var column_y := _voxel_world.get_highest_solid_y(x, z)
			if column_y < 0 or (surface_y >= 0 and column_y != surface_y):
				return -1
			var position := Vector3i(x, column_y, z)
			if _voxel_world.get_block_id_at(position) not in VALID_SURFACE_BLOCKS:
				return -1
			if _voxel_world.get_block_id_at(position + Vector3i.UP) != BlockId.Type.AIR:
				return -1
			surface_y = column_y
	return surface_y

func _build_patch(origin: Vector3i) -> Node3D:
	var state_bounds: Array[AABB] = []
	var largest_horizontal_size := 0.0
	for pumpkin_scene in pumpkin_scenes:
		if pumpkin_scene == null:
			return null
		var model := pumpkin_scene.instantiate() as Node3D
		if model == null:
			return null
		var model_bounds := _calculate_model_bounds(model)
		var horizontal_size := maxf(model_bounds.size.x, model_bounds.size.z)
		if horizontal_size <= 0.0 or model_bounds.size.y <= 0.0:
			model.free()
			return null
		model.free()
		state_bounds.append(model_bounds)
		largest_horizontal_size = maxf(largest_horizontal_size, horizontal_size)
	var model_scale := MODEL_FIT_SIZE / largest_horizontal_size
	var patch := Node3D.new()
	patch.name = "PumpkinPatch"
	patch.position = Vector3(origin.x, origin.y + 1.0, origin.z)
	var soil_mesh := PlaneMesh.new()
	soil_mesh.size = Vector2.ONE
	var soil_material := StandardMaterial3D.new()
	soil_material.albedo_texture = soil_texture
	soil_material.roughness = 1.0
	soil_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	soil_mesh.material = soil_material
	var soil_index := 1
	for z_offset in range(PATCH_DEPTH):
		for x_offset in range(PATCH_WIDTH):
			var soil := MeshInstance3D.new()
			soil.name = "Soil%02d" % soil_index
			soil.mesh = soil_mesh
			soil.position = Vector3(float(x_offset) + 0.5, SOIL_SURFACE_OFFSET, float(z_offset) + 0.5)
			soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			patch.add_child(soil)
			soil_index += 1
	var state_indices := _randomized_state_indices(PATCH_WIDTH * PATCH_DEPTH)
	for index in range(state_indices.size()):
		var x_offset := index % PATCH_WIDTH
		var z_offset := index / PATCH_WIDTH
		var tile_center := Vector3(float(x_offset) + 0.5, 0.0, float(z_offset) + 0.5)
		var holder := Node3D.new()
		holder.name = "State%02d" % (index + 1)
		holder.position = tile_center
		holder.rotation.y = float(_random.randi_range(0, 3)) * PI * 0.5
		patch.add_child(holder)
		var state_index := state_indices[index]
		var model := pumpkin_scenes[state_index].instantiate() as Node3D
		var model_bounds := state_bounds[state_index]
		var model_center := model_bounds.get_center()
		model.scale = Vector3.ONE * model_scale
		model.position = Vector3(
			-model_center.x * model_scale,
			SOIL_SURFACE_OFFSET - model_bounds.position.y * model_scale,
			-model_center.z * model_scale
		)
		holder.add_child(model)
	return patch

func _randomized_state_indices(tile_count: int) -> Array[int]:
	var indices: Array[int] = []
	for state_index in range(pumpkin_scenes.size()):
		indices.append(state_index)
	while indices.size() < tile_count:
		indices.append(_random.randi_range(0, pumpkin_scenes.size() - 1))
	for index in range(indices.size() - 1, 0, -1):
		var swap_index := _random.randi_range(0, index)
		var state_index := indices[index]
		indices[index] = indices[swap_index]
		indices[swap_index] = state_index
	return indices

func _calculate_model_bounds(model: Node3D) -> AABB:
	var mesh_bounds: Array[AABB] = []
	_collect_mesh_bounds(model, Transform3D.IDENTITY, mesh_bounds)
	if mesh_bounds.is_empty():
		return AABB()
	var combined := mesh_bounds[0]
	for index in range(1, mesh_bounds.size()):
		combined = combined.merge(mesh_bounds[index])
	return combined

func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, output: Array[AABB]) -> void:
	for child in node.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * (child as Node3D).transform
		if child is MeshInstance3D:
			output.append(child_transform * (child as MeshInstance3D).get_aabb())
		_collect_mesh_bounds(child, child_transform, output)
