extends Node3D
class_name ChunkRenderer

const MAX_MESH_CACHE: int = 96

var _terrain_instances: Dictionary = {}
var _water_instances: Dictionary = {}
var _foliage_instances: Dictionary = {}

var _mesher: ChunkMesher
var _foliage_mesher: FoliageMesher
var _terrain_material: Material
var _water_material: Material
var _foliage_material: Material
var _voxel_model: VoxelWorld
var _shadow_center := Vector2i.ZERO
var _shadow_render_distance: int

var _mesh_cache: Dictionary = {}
var _mesh_cache_order: Array[Vector2i] = []
var _terrain_pool: Array[MeshInstance3D] = []
var _water_pool: Array[MeshInstance3D] = []
var _foliage_pool: Array[MeshInstance3D] = []

func setup(p_mesher: ChunkMesher, p_foliage_mesher: FoliageMesher, p_terrain_material: Material, p_water_material: Material, p_foliage_material: Material, p_voxel_model: VoxelWorld, p_shadow_render_distance: int):
	_mesher = p_mesher
	_foliage_mesher = p_foliage_mesher
	_terrain_material = p_terrain_material
	_water_material = p_water_material
	_foliage_material = p_foliage_material
	_voxel_model = p_voxel_model
	_shadow_render_distance = p_shadow_render_distance

func set_shadow_center(center: Vector2i):
	_shadow_center = center
	_update_shadow_casters()

func set_shadow_render_distance(distance: int):
	_shadow_render_distance = distance
	_update_shadow_casters()

func _update_shadow_casters():
	_update_shadow_casters_for(_terrain_instances)

func _update_shadow_casters_for(instances: Dictionary):
	for coord in instances:
		var instance := instances[coord] as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _should_cast_shadow(coord) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _should_cast_shadow(coord: Vector2i) -> bool:
	var offset := coord - _shadow_center
	return maxi(abs(offset.x), abs(offset.y)) <= _shadow_render_distance

func apply_result(result: ChunkBuildResult):
	_apply_generation(result.coord, result.generation_payload, not result.terrain_only)
	if result.terrain_only:
		return
	var terrain_mesh := _mesher.create_mesh_from_data(result.terrain_mesh_data)
	var water_mesh := _mesher.create_water_mesh_from_data(result.water_mesh_data)
	var visible_foliage_cells := _voxel_model.get_visible_foliage_cells_for_chunk(result.coord)
	var foliage_mesh_data := result.foliage_mesh_data
	if visible_foliage_cells != result.foliage_cells:
		foliage_mesh_data = _foliage_mesher.build_mesh_data(visible_foliage_cells)
	var foliage_mesh := _foliage_mesher.create_mesh_from_data(foliage_mesh_data)
	if terrain_mesh == null:
		_ensure_empty_terrain(result.coord)
	else:
		_set_or_create_terrain(result.coord, terrain_mesh)
	if water_mesh == null:
		_release_water(result.coord, false)
	else:
		_set_or_create_water(result.coord, water_mesh)
	if foliage_mesh == null:
		_release_foliage(result.coord, false)
	else:
		_set_or_create_foliage(result.coord, foliage_mesh)

func restore_cached(coord: Vector2i) -> bool:
	if not _mesh_cache.has(coord):
		return false
	var cached := _pop_cached_meshes(coord)
	var terrain_mesh := cached.get("terrain", null) as ArrayMesh
	var water_mesh := cached.get("water", null) as ArrayMesh
	var foliage_mesh := cached.get("foliage", null) as ArrayMesh
	if terrain_mesh == null:
		_ensure_empty_terrain(coord)
	else:
		_set_or_create_terrain(coord, terrain_mesh)
	if water_mesh == null:
		_release_water(coord, false)
	else:
		_set_or_create_water(coord, water_mesh)
	if foliage_mesh == null:
		_release_foliage(coord, false)
	else:
		_set_or_create_foliage(coord, foliage_mesh)
	return true

func invalidate_cache(coord: Vector2i):
	_mesh_cache.erase(coord)
	_mesh_cache_order.erase(coord)

func apply_foliage_cells(coord: Vector2i, cells: PackedInt32Array) -> void:
	if not _terrain_instances.has(coord):
		return
	var mesh_data: Variant = _foliage_mesher.build_mesh_data(cells)
	var foliage_mesh := _foliage_mesher.create_mesh_from_data(mesh_data)
	if foliage_mesh == null:
		_release_foliage(coord, false)
	else:
		_set_or_create_foliage(coord, foliage_mesh)

func unload(coord: Vector2i):
	_release_render_instances(coord)

func clear():
	for instance in _terrain_instances.values():
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_terrain_instances.clear()
	for instance in _water_instances.values():
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_water_instances.clear()
	for instance in _foliage_instances.values():
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_foliage_instances.clear()
	for instance in _terrain_pool:
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_terrain_pool.clear()
	for instance in _water_pool:
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_water_pool.clear()
	for instance in _foliage_pool:
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_foliage_pool.clear()
	_mesh_cache.clear()
	_mesh_cache_order.clear()

func _apply_generation(coord: Vector2i, payload: Dictionary, include_copper: bool):
	var height := payload.get("height", {}) as Dictionary
	if not height.is_empty():
		_voxel_model.apply_chunk_gen_for_coord(coord, {
			"height": height,
			"type": payload.get("type", {}) as Dictionary,
		})
	_voxel_model.apply_tree_chunk_for_coord(coord, {
		"tree_block_fast": payload.get("tree_block_fast", {}) as Dictionary,
	})
	_voxel_model.apply_foliage_chunk_for_coord(coord, {
		"foliage_block_fast": payload.get("foliage_block_fast", {}) as Dictionary,
	})
	if include_copper:
		_voxel_model.apply_copper_chunk_for_coord(coord, {
			"copper_block_fast": payload.get("copper_block_fast", {}) as Dictionary,
		})

func _touch_cache(coord: Vector2i):
	_mesh_cache_order.erase(coord)
	_mesh_cache_order.append(coord)
	if _mesh_cache_order.size() > MAX_MESH_CACHE:
		var oldest := _mesh_cache_order.pop_front() as Vector2i
		_mesh_cache.erase(oldest)

func _cache_terrain_mesh(coord: Vector2i, mesh: ArrayMesh):
	var entry := _mesh_cache.get(coord, {"terrain": null, "water": null, "foliage": null}) as Dictionary
	entry["terrain"] = mesh
	_mesh_cache[coord] = entry
	_touch_cache(coord)

func _cache_water_mesh(coord: Vector2i, mesh: ArrayMesh):
	if not _mesh_cache.has(coord):
		return
	var entry := _mesh_cache[coord] as Dictionary
	entry["water"] = mesh
	_mesh_cache[coord] = entry
	_touch_cache(coord)

func _cache_foliage_mesh(coord: Vector2i, mesh: ArrayMesh):
	if not _mesh_cache.has(coord):
		return
	var entry := _mesh_cache[coord] as Dictionary
	entry["foliage"] = mesh
	_mesh_cache[coord] = entry
	_touch_cache(coord)

func _pop_cached_meshes(coord: Vector2i) -> Dictionary:
	var entry := _mesh_cache[coord] as Dictionary
	_mesh_cache.erase(coord)
	_mesh_cache_order.erase(coord)
	return entry

func _pop_pooled_instance(pool: Array[MeshInstance3D]) -> MeshInstance3D:
	while not pool.is_empty():
		var instance := pool.pop_back() as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			return instance
	return null

func _attach_to_container(instance: MeshInstance3D):
	if instance.get_parent() == null:
		add_child(instance)

func _release_terrain(coord: Vector2i):
	if not _terrain_instances.has(coord):
		return
	var instance := _terrain_instances[coord] as MeshInstance3D
	if instance != null and is_instance_valid(instance):
		var mesh := instance.mesh as ArrayMesh
		if mesh != null:
			_cache_terrain_mesh(coord, mesh)
		instance.mesh = null
		instance.visible = false
		_terrain_pool.append(instance)
	_terrain_instances.erase(coord)

func _release_water(coord: Vector2i, cache_mesh: bool):
	if not _water_instances.has(coord):
		return
	var instance := _water_instances[coord] as MeshInstance3D
	if instance != null and is_instance_valid(instance):
		if cache_mesh:
			var mesh := instance.mesh as ArrayMesh
			if mesh != null:
				_cache_water_mesh(coord, mesh)
		instance.mesh = null
		instance.visible = false
		_water_pool.append(instance)
	_water_instances.erase(coord)

func _release_foliage(coord: Vector2i, cache_mesh: bool):
	if not _foliage_instances.has(coord):
		return
	var instance := _foliage_instances[coord] as MeshInstance3D
	if instance != null and is_instance_valid(instance):
		if cache_mesh:
			var mesh := instance.mesh as ArrayMesh
			if mesh != null:
				_cache_foliage_mesh(coord, mesh)
		instance.mesh = null
		instance.visible = false
		_foliage_pool.append(instance)
	_foliage_instances.erase(coord)

func _release_render_instances(coord: Vector2i):
	_release_terrain(coord)
	_release_water(coord, true)
	_release_foliage(coord, true)

func _create_terrain_instance(coord: Vector2i, mesh: ArrayMesh) -> MeshInstance3D:
	var instance := _pop_pooled_instance(_terrain_pool)
	if instance == null:
		instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _terrain_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _should_cast_shadow(coord) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = true
	instance.name = "Chunk_%d_%d" % [coord.x, coord.y]
	_attach_to_container(instance)
	return instance

func _create_water_instance(coord: Vector2i, mesh: ArrayMesh) -> MeshInstance3D:
	var instance := _pop_pooled_instance(_water_pool)
	if instance == null:
		instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _water_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = true
	instance.name = "Water_%d_%d" % [coord.x, coord.y]
	_attach_to_container(instance)
	return instance

func _create_foliage_instance(coord: Vector2i, mesh: ArrayMesh) -> MeshInstance3D:
	var instance := _pop_pooled_instance(_foliage_pool)
	if instance == null:
		instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _foliage_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.visible = true
	instance.name = "Foliage_%d_%d" % [coord.x, coord.y]
	_attach_to_container(instance)
	return instance

func _create_empty_terrain_instance(coord: Vector2i) -> MeshInstance3D:
	var instance := _pop_pooled_instance(_terrain_pool)
	if instance == null:
		instance = MeshInstance3D.new()
	instance.mesh = null
	instance.visible = true
	instance.name = "Chunk_%d_%d_empty" % [coord.x, coord.y]
	_attach_to_container(instance)
	return instance

func _set_or_create_terrain(coord: Vector2i, mesh: ArrayMesh):
	if _terrain_instances.has(coord):
		var instance := _terrain_instances[coord] as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			instance.mesh = mesh
			return
	_terrain_instances[coord] = _create_terrain_instance(coord, mesh)

func _set_or_create_water(coord: Vector2i, mesh: ArrayMesh):
	if _water_instances.has(coord):
		var instance := _water_instances[coord] as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			instance.mesh = mesh
			return
	_water_instances[coord] = _create_water_instance(coord, mesh)

func _set_or_create_foliage(coord: Vector2i, mesh: ArrayMesh):
	if _foliage_instances.has(coord):
		var instance := _foliage_instances[coord] as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			instance.mesh = mesh
			return
	_foliage_instances[coord] = _create_foliage_instance(coord, mesh)

func _ensure_empty_terrain(coord: Vector2i):
	if _terrain_instances.has(coord):
		var instance := _terrain_instances[coord] as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			instance.mesh = null
			return
	_terrain_instances[coord] = _create_empty_terrain_instance(coord)
