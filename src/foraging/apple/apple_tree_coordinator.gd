extends HarvestSource
class_name AppleTreeCoordinator

signal state_changed

const GROUND_OFFSETS: Array[Vector2] = [
	Vector2(0.78, 0.18),
	Vector2(-0.72, 0.28),
	Vector2(0.22, 0.82),
	Vector2(-0.18, -0.76),
	Vector2(0.65, -0.58),
	Vector2(-0.62, -0.55),
]
const DECORATIVE_OFFSETS: Array[Vector3] = [
	Vector3(1.64, 0.10, 0.18),
	Vector3(-1.64, 0.22, -0.12),
	Vector3(0.16, 0.36, 1.64),
	Vector3(-0.18, 0.05, -1.64),
	Vector3(1.64, 0.52, -0.48),
	Vector3(-1.64, 0.08, 0.52),
	Vector3(0.52, 0.62, 1.64),
	Vector3(-0.54, 0.28, -1.64),
	Vector3(1.62, 0.42, 1.62),
	Vector3(-1.62, 0.58, -1.62),
	Vector3(1.62, 0.16, -1.62),
	Vector3(-1.62, 0.34, 1.62),
	Vector3(1.64, 0.78, 0.72),
	Vector3(-1.64, 0.88, -0.70),
	Vector3(0.72, 0.72, -1.64),
]

@export var definition: AppleTreeDefinition

var _voxel_world: VoxelWorld
var _chunk_manager: ChunkManager
var _world_seed: int
var _state := AppleTreeState.new()
var _model_bounds: AABB
var _chunk_roots: Dictionary = {}
var _targets: Dictionary = {}
var _next_target_id: int = 1

func setup(voxel_world: VoxelWorld, chunk_manager: ChunkManager, world_seed: int, saved_state: Variant, item_catalog: ItemCatalog) -> bool:
	assert(voxel_world != null and chunk_manager != null and item_catalog != null)
	assert(_voxel_world == null and _chunk_manager == null)
	_voxel_world = voxel_world
	_chunk_manager = chunk_manager
	_world_seed = world_seed
	if definition == null or not definition.validate(item_catalog) or not _state.restore(saved_state) or not _prepare_model_bounds():
		return false
	_chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	_chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	_voxel_world.block_edit_committed.connect(_on_block_edit_committed)
	for coord in _chunk_manager.visible_chunks:
		_render_chunk(coord)
	return true

func snapshot() -> Dictionary:
	return _state.snapshot()

func validate_harvest_items(item_catalog: ItemCatalog) -> bool:
	return definition != null and definition.validate(item_catalog)

func find_harvest_target(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	if ray_direction.is_zero_approx() or max_distance <= 0.0:
		return {}
	var nearest_id := -1
	var nearest_distance := max_distance
	for target_id in _targets:
		var record := _targets[target_id] as Dictionary
		var hit = (record["bounds"] as AABB).intersects_ray(ray_origin, ray_direction)
		if not hit is Vector3:
			continue
		var distance := ray_origin.distance_to(hit)
		if distance <= nearest_distance:
			nearest_id = target_id
			nearest_distance = distance
	if nearest_id < 0:
		return {}
	return {"target_id": nearest_id, "distance": nearest_distance}

func get_harvest_target_bounds(target_id: int) -> AABB:
	assert(_targets.has(target_id))
	return (_targets[target_id] as Dictionary)["bounds"] as AABB

func can_harvest_target(target_id: int) -> bool:
	return _targets.has(target_id)

func get_harvest_item_ids(target_id: int) -> Array[StringName]:
	assert(_targets.has(target_id))
	return [definition.apple_item_id]

func try_harvest_target(target_id: int) -> bool:
	if not _targets.has(target_id):
		return false
	var record := _targets[target_id] as Dictionary
	var tree_position := record["tree_position"] as Vector3i
	var slot_index := int(record["slot_index"])
	if not _state.collect(tree_position, slot_index):
		return false
	var apple := record["node"] as Node3D
	_targets.erase(target_id)
	apple.queue_free()
	state_changed.emit()
	return true

func get_harvest_prompt() -> String:
	return "Left Click  Pick Up Apple"

func _prepare_model_bounds() -> bool:
	if definition == null or definition.apple_scene == null:
		return false
	var model := definition.apple_scene.instantiate() as Node3D
	if model == null:
		return false
	var bounds: Array[AABB] = []
	_collect_mesh_bounds(model, Transform3D.IDENTITY, bounds)
	model.free()
	if bounds.is_empty():
		return false
	_model_bounds = bounds[0]
	for index in range(1, bounds.size()):
		_model_bounds = _model_bounds.merge(bounds[index])
	return maxf(_model_bounds.size.x, maxf(_model_bounds.size.y, _model_bounds.size.z)) > 0.0

func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, output: Array[AABB]) -> void:
	for child in node.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * (child as Node3D).transform
		if child is MeshInstance3D:
			output.append(child_transform * (child as MeshInstance3D).get_aabb())
		_collect_mesh_bounds(child, child_transform, output)

func _on_chunk_loaded(coord: Vector2i) -> void:
	_render_chunk(coord)

func _on_chunk_unloaded(coord: Vector2i) -> void:
	_unload_chunk(coord)

func _on_block_edit_committed(edit: BlockEdit) -> void:
	var coord := ChunkCoord.world_to_chunk_vec3i(edit.pos, _voxel_world.chunk_size)
	if _chunk_manager.visible_chunks.has(coord):
		_render_chunk(coord)

func _render_chunk(coord: Vector2i) -> void:
	_unload_chunk(coord)
	var tree_blocks := _voxel_world.get_tree_blocks_for_chunk(coord)
	if tree_blocks.is_empty():
		return
	var root := Node3D.new()
	root.name = "AppleTrees_%d_%d" % [coord.x, coord.y]
	add_child(root)
	_chunk_roots[coord] = root
	var trunk_bases: Array[Vector3i] = []
	for raw_position in tree_blocks:
		var position := raw_position as Vector3i
		if int(tree_blocks[position]) == BlockId.Type.LOG and position.y == _voxel_world.get_terrain_height(position.x, position.z) + 1:
			trunk_bases.append(position)
	trunk_bases.sort()
	for tree_position in trunk_bases:
		if _is_apple_tree(tree_position):
			_render_apple_tree(root, coord, tree_position, tree_blocks)
	if root.get_child_count() == 0:
		_chunk_roots.erase(coord)
		root.queue_free()

func _render_apple_tree(root: Node3D, coord: Vector2i, tree_position: Vector3i, tree_blocks: Dictionary) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = _stable_seed(tree_position, 17)
	var ground_offsets := GROUND_OFFSETS.duplicate()
	_shuffle(ground_offsets, random)
	var ground_count := random.randi_range(definition.minimum_ground_apples, definition.maximum_ground_apples)
	for slot_index in range(ground_count):
		if _state.is_collected(tree_position, slot_index):
			continue
		var offset := ground_offsets[slot_index] as Vector2
		var apple_position := Vector3(tree_position.x + 0.5 + offset.x, 0.0, tree_position.z + 0.5 + offset.y)
		var ground_height := _voxel_world.get_terrain_height(floori(apple_position.x), floori(apple_position.z))
		if ground_height < 0:
			ground_height = tree_position.y - 1
		apple_position.y = float(ground_height + 1)
		_spawn_ground_apple(root, coord, tree_position, slot_index, apple_position)
	var top_log_y := tree_position.y
	for raw_position in tree_blocks:
		var position := raw_position as Vector3i
		if position.x == tree_position.x and position.z == tree_position.z and int(tree_blocks[position]) == BlockId.Type.LOG:
			top_log_y = maxi(top_log_y, position.y)
	var decorative_offsets := DECORATIVE_OFFSETS.duplicate()
	_shuffle(decorative_offsets, random)
	for index in range(definition.decorative_apple_count):
		var offset := decorative_offsets[index] as Vector3
		var position := Vector3(tree_position.x + 0.5, top_log_y + 1.45, tree_position.z + 0.5) + offset
		var apple := _spawn_apple_model(root, position, definition.decorative_apple_size, false)
		apple.name = "DecorativeApple_%d" % index

func _spawn_ground_apple(root: Node3D, coord: Vector2i, tree_position: Vector3i, slot_index: int, position: Vector3) -> void:
	var holder := _spawn_apple_model(root, position, definition.ground_apple_size, true)
	holder.name = "GroundApple_%d" % slot_index
	var target_id := _next_target_id
	_next_target_id += 1
	var coordinator_transform := global_transform if is_inside_tree() else transform
	var bounds := coordinator_transform * root.transform * holder.transform * _calculate_holder_bounds(holder)
	_targets[target_id] = {
		"bounds": bounds.grow(0.08),
		"chunk": coord,
		"tree_position": tree_position,
		"slot_index": slot_index,
		"node": holder,
	}

func _spawn_apple_model(root: Node3D, position: Vector3, target_size: float, rest_on_surface: bool) -> Node3D:
	var holder := Node3D.new()
	holder.position = position
	root.add_child(holder)
	var model := definition.apple_scene.instantiate() as Node3D
	var source_size := maxf(_model_bounds.size.x, maxf(_model_bounds.size.y, _model_bounds.size.z))
	var model_scale := target_size / source_size
	model.scale = Vector3.ONE * model_scale
	var center := _model_bounds.get_center()
	model.position = Vector3(-center.x * model_scale, -center.y * model_scale, -center.z * model_scale)
	if rest_on_surface:
		model.position.y = -_model_bounds.position.y * model_scale
	holder.add_child(model)
	return holder

func _calculate_holder_bounds(holder: Node3D) -> AABB:
	var bounds: Array[AABB] = []
	_collect_mesh_bounds(holder, Transform3D.IDENTITY, bounds)
	var combined := bounds[0]
	for index in range(1, bounds.size()):
		combined = combined.merge(bounds[index])
	return combined

func _unload_chunk(coord: Vector2i) -> void:
	if _chunk_roots.has(coord):
		(_chunk_roots[coord] as Node3D).queue_free()
		_chunk_roots.erase(coord)
	for target_id in _targets.keys():
		if (_targets[target_id] as Dictionary)["chunk"] == coord:
			_targets.erase(target_id)

func _is_apple_tree(tree_position: Vector3i) -> bool:
	return _stable_seed(tree_position, 5) % 10000 < roundi(definition.tree_fraction * 10000.0)

func _stable_seed(tree_position: Vector3i, salt: int) -> int:
	return absi(("%d:%d:%d:%d:%d" % [_world_seed, tree_position.x, tree_position.y, tree_position.z, salt]).hash())

func _shuffle(values: Array, random: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var value = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func _exit_tree() -> void:
	if _chunk_manager != null:
		if _chunk_manager.chunk_loaded.is_connected(_on_chunk_loaded):
			_chunk_manager.chunk_loaded.disconnect(_on_chunk_loaded)
		if _chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
			_chunk_manager.chunk_unloaded.disconnect(_on_chunk_unloaded)
	if _voxel_world != null and _voxel_world.block_edit_committed.is_connected(_on_block_edit_committed):
		_voxel_world.block_edit_committed.disconnect(_on_block_edit_committed)
