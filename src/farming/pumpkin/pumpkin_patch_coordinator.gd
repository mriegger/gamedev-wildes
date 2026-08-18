extends HarvestSource
class_name PumpkinPatchCoordinator

signal state_changed

const PATCH_WIDTH: int = 5
const PATCH_DEPTH: int = 4
const MIN_HARVESTABLE_TILES: int = 3
const SEARCH_RADIUS: int = 45
const MIN_PLAYER_DISTANCE_SQUARED: float = 1225.0
const MODEL_FIT_SIZE: float = 1.755
const SOIL_SURFACE_OFFSET: float = 0.008
const VALID_SURFACE_BLOCKS: Array[int] = [
	BlockId.Type.GRASS,
	BlockId.Type.DIRT,
	BlockId.Type.FARMLAND_DRY,
]

@export var soil_texture: Texture2D
@export var growth_states: Array[PumpkinGrowthStateDefinition] = []

var _voxel_world: VoxelWorld
var _player: Node3D
var _state := PumpkinPatchState.new()
var _definitions_by_id: Dictionary[StringName, PumpkinGrowthStateDefinition] = {}
var _valid_state_ids: Array[StringName] = []
var _generated_state_ids: Array[StringName] = []
var _harvestable_generated_state_ids: Array[StringName] = []
var _patch_root: Node3D
var _random := RandomNumberGenerator.new()
var _tile_target_bounds: Array[AABB] = []

func setup(p_voxel_world: VoxelWorld, p_player: Node3D, world_seed: int, saved_state: Variant) -> bool:
	assert(p_voxel_world != null and p_player != null)
	assert(_voxel_world == null and _player == null)
	if not _index_definitions():
		return false
	_voxel_world = p_voxel_world
	_player = p_player
	_random.seed = world_seed
	if saved_state == null:
		if not _generate_near(_player.global_position):
			return false
	elif saved_state is Dictionary:
		if not _state.restore(saved_state, _valid_state_ids):
			return false
	else:
		return false
	return _render_state()

func spawn_patch() -> bool:
	if _voxel_world == null or _player == null:
		return false
	if not _generate_near(_player.global_position) or not _render_state():
		return false
	state_changed.emit()
	return true

func snapshot() -> Dictionary:
	return _state.snapshot()

func has_patch() -> bool:
	return _state.is_present()

func validate_harvest_items(item_catalog: ItemCatalog) -> bool:
	if item_catalog == null:
		return false
	for definition in growth_states:
		if definition.is_harvestable() and not item_catalog.has_definition(definition.harvest_item_id):
			return false
	return true

func can_harvest_tile(tile_index: int) -> bool:
	if not _state.is_present() or tile_index < 0 or tile_index >= PumpkinPatchState.TILE_COUNT:
		return false
	var definition := _definitions_by_id.get(_state.get_growth_state_id(tile_index), null) as PumpkinGrowthStateDefinition
	return definition != null and definition.is_harvestable()

func try_harvest_tile(tile_index: int) -> bool:
	if not can_harvest_tile(tile_index):
		return false
	var definition := _definitions_by_id[_state.get_growth_state_id(tile_index)] as PumpkinGrowthStateDefinition
	if not _state.transition_growth_state(tile_index, definition.id, definition.harvest_result_state_id, _valid_state_ids):
		return false
	var rendered := _render_state()
	assert(rendered)
	state_changed.emit()
	return true

func find_harvest_target(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	if _patch_root == null or not _patch_root.is_inside_tree() or ray_direction.is_zero_approx() or max_distance <= 0.0:
		return {}
	var inverse := _patch_root.global_transform.affine_inverse()
	var local_origin := inverse * ray_origin
	var local_direction := (inverse.basis * ray_direction).normalized()
	var nearest_index := -1
	var nearest_distance := max_distance
	for tile_index in range(PumpkinPatchState.TILE_COUNT):
		if not can_harvest_tile(tile_index):
			continue
		var local_hit = _tile_target_bounds[tile_index].intersects_ray(local_origin, local_direction)
		if not local_hit is Vector3:
			continue
		var world_hit := _patch_root.global_transform * (local_hit as Vector3)
		var distance := ray_origin.distance_to(world_hit)
		if distance <= nearest_distance:
			nearest_index = tile_index
			nearest_distance = distance
	if nearest_index < 0:
		return {}
	return {"target_id": nearest_index, "distance": nearest_distance}

func get_tile_world_bounds(tile_index: int) -> AABB:
	assert(_patch_root != null and tile_index >= 0 and tile_index < _tile_target_bounds.size())
	return _patch_root.global_transform * _tile_target_bounds[tile_index]

func get_harvest_target_bounds(target_id: int) -> AABB:
	return get_tile_world_bounds(target_id)

func can_harvest_target(target_id: int) -> bool:
	return can_harvest_tile(target_id)

func get_harvest_item_ids(target_id: int) -> Array[StringName]:
	assert(can_harvest_tile(target_id))
	var definition := _definitions_by_id[_state.get_growth_state_id(target_id)] as PumpkinGrowthStateDefinition
	var item_ids: Array[StringName] = []
	for _index in range(definition.harvest_count):
		item_ids.append(definition.harvest_item_id)
	return item_ids

func try_harvest_target(target_id: int) -> bool:
	return try_harvest_tile(target_id)

func get_harvest_prompt() -> String:
	return "Left Click  Harvest Pumpkin"

func _index_definitions() -> bool:
	if soil_texture == null or growth_states.is_empty():
		return false
	for definition in growth_states:
		if definition == null or not definition.validate() or _definitions_by_id.has(definition.id):
			return false
		_definitions_by_id[definition.id] = definition
		_valid_state_ids.append(definition.id)
		if definition.generate_in_new_patch:
			_generated_state_ids.append(definition.id)
			if definition.is_harvestable():
				_harvestable_generated_state_ids.append(definition.id)
	for definition in growth_states:
		if definition.is_harvestable() and not _definitions_by_id.has(definition.harvest_result_state_id):
			return false
	return (
		not _generated_state_ids.is_empty()
		and not _harvestable_generated_state_ids.is_empty()
		and _generated_state_ids.size() <= PumpkinPatchState.TILE_COUNT
		and MIN_HARVESTABLE_TILES <= PumpkinPatchState.TILE_COUNT
	)

func _generate_near(target_position: Vector3) -> bool:
	var origins := _find_patch_origins(target_position)
	if origins.is_empty():
		return false
	var origin := origins[_random.randi_range(0, origins.size() - 1)]
	var state_ids: Array[StringName] = _generated_state_ids.duplicate()
	var harvestable_count := 0
	for state_id in state_ids:
		if state_id in _harvestable_generated_state_ids:
			harvestable_count += 1
	while harvestable_count < MIN_HARVESTABLE_TILES:
		state_ids.append(_harvestable_generated_state_ids[_random.randi_range(0, _harvestable_generated_state_ids.size() - 1)])
		harvestable_count += 1
	while state_ids.size() < PumpkinPatchState.TILE_COUNT:
		state_ids.append(_generated_state_ids[_random.randi_range(0, _generated_state_ids.size() - 1)])
	for index in range(state_ids.size() - 1, 0, -1):
		var swap_index := _random.randi_range(0, index)
		var state_id := state_ids[index]
		state_ids[index] = state_ids[swap_index]
		state_ids[swap_index] = state_id
	var quarter_turns := PackedInt32Array()
	for index in range(PumpkinPatchState.TILE_COUNT):
		quarter_turns.append(_random.randi_range(0, 3))
	return _state.replace(origin, state_ids, quarter_turns, _valid_state_ids)

func _find_patch_origins(target_position: Vector3) -> Array[Vector3i]:
	var target_cell := Vector3i(floori(target_position.x), 0, floori(target_position.z))
	var origins: Array[Vector3i] = []
	for dx in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
		for dz in range(-SEARCH_RADIUS, SEARCH_RADIUS + 1):
			var origin := Vector3i(target_cell.x + dx, 0, target_cell.z + dz)
			var center := Vector2(float(origin.x) + float(PATCH_WIDTH) * 0.5, float(origin.z) + float(PATCH_DEPTH) * 0.5)
			var target_center := Vector2(target_position.x, target_position.z)
			if center.distance_squared_to(target_center) < MIN_PLAYER_DISTANCE_SQUARED:
				continue
			var surface_y := _get_patch_surface_y(origin.x, origin.z)
			if surface_y >= 0:
				origins.append(Vector3i(origin.x, surface_y, origin.z))
	return origins

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

func _render_state() -> bool:
	if _patch_root != null:
		_patch_root.free()
		_patch_root = null
	_tile_target_bounds.clear()
	if not _state.is_present():
		return true
	_patch_root = _build_patch()
	if _patch_root == null:
		return false
	add_child(_patch_root)
	return true

func _build_patch() -> Node3D:
	var bounds_by_id: Dictionary[StringName, AABB] = {}
	var largest_horizontal_size := 0.0
	for definition in growth_states:
		if definition.model_scene == null:
			continue
		var model := definition.model_scene.instantiate() as Node3D
		if model == null:
			return null
		var model_bounds := _calculate_model_bounds(model)
		var horizontal_size := maxf(model_bounds.size.x, model_bounds.size.z)
		model.free()
		if horizontal_size <= 0.0 or model_bounds.size.y <= 0.0:
			return null
		bounds_by_id[definition.id] = model_bounds
		largest_horizontal_size = maxf(largest_horizontal_size, horizontal_size)
	var model_scale := MODEL_FIT_SIZE / largest_horizontal_size
	var patch := Node3D.new()
	patch.name = "PumpkinPatch"
	_tile_target_bounds.resize(PumpkinPatchState.TILE_COUNT)
	var origin := _state.get_origin()
	patch.position = Vector3(origin.x, origin.y + 1.0, origin.z)
	var soil_mesh := PlaneMesh.new()
	soil_mesh.size = Vector2.ONE
	var soil_material := StandardMaterial3D.new()
	soil_material.albedo_texture = soil_texture
	soil_material.roughness = 1.0
	soil_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	soil_mesh.material = soil_material
	for index in range(PumpkinPatchState.TILE_COUNT):
		var x_offset := index % PATCH_WIDTH
		var z_offset := index / PATCH_WIDTH
		var soil := MeshInstance3D.new()
		soil.name = "Soil%02d" % (index + 1)
		soil.mesh = soil_mesh
		soil.position = Vector3(float(x_offset) + 0.5, SOIL_SURFACE_OFFSET, float(z_offset) + 0.5)
		soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		patch.add_child(soil)
		var holder := Node3D.new()
		holder.name = "State%02d" % (index + 1)
		holder.position = Vector3(float(x_offset) + 0.5, 0.0, float(z_offset) + 0.5)
		holder.rotation.y = float(_state.get_quarter_turns(index)) * PI * 0.5
		patch.add_child(holder)
		var state_id := _state.get_growth_state_id(index)
		var definition := _definitions_by_id[state_id]
		if definition.model_scene == null:
			_tile_target_bounds[index] = AABB(holder.position, Vector3.ZERO)
			continue
		var model := definition.model_scene.instantiate() as Node3D
		var model_bounds := bounds_by_id[state_id]
		model.scale = Vector3.ONE * model_scale
		model.position = Vector3(
			0.0,
			SOIL_SURFACE_OFFSET - model_bounds.position.y * model_scale,
			0.0
		)
		holder.add_child(model)
		_tile_target_bounds[index] = (holder.transform * model.transform * model_bounds).grow(0.08)
	return patch

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
