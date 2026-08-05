extends Node3D
class_name ChunkRenderer

const MAX_MESH_CACHE: int = 200

var _terrain_instances: Dictionary = {}
var _water_instances: Dictionary = {}

var _mesher: ChunkMesher
var _terrain_material: Material
var _water_material: Material
var _voxel_model: VoxelWorld

var _mesh_cache: Dictionary = {}
var _mesh_cache_order: Array[Vector2i] = []
var _terrain_pool: Array[MeshInstance3D] = []
var _water_pool: Array[MeshInstance3D] = []

func setup(p_mesher: ChunkMesher, p_terrain_material: Material, p_water_material: Material, p_voxel_model: VoxelWorld):
	_mesher = p_mesher
	_terrain_material = p_terrain_material
	_water_material = p_water_material
	_voxel_model = p_voxel_model

func apply_result(result: ChunkBuildResult):
	_apply_generation(result.coord, result.generation_payload)
	if result.terrain_only:
		return
	var terrain_mesh := _mesher.create_mesh_from_data(result.terrain_mesh_data)
	var water_mesh := _mesher.create_water_mesh_from_data(result.water_mesh_data)
	if terrain_mesh == null:
		_ensure_empty_terrain(result.coord)
	else:
		_set_or_create_terrain(result.coord, terrain_mesh)
	if water_mesh == null:
		_release_water(result.coord, false)
	else:
		_set_or_create_water(result.coord, water_mesh)

func restore_cached(coord: Vector2i) -> bool:
	if not _mesh_cache.has(coord):
		return false
	var cached := _pop_cached_meshes(coord)
	var terrain_mesh := cached.get("terrain", null) as ArrayMesh
	var water_mesh := cached.get("water", null) as ArrayMesh
	if terrain_mesh == null:
		_ensure_empty_terrain(coord)
	else:
		_set_or_create_terrain(coord, terrain_mesh)
	if water_mesh == null:
		_release_water(coord, false)
	else:
		_set_or_create_water(coord, water_mesh)
	return true

func invalidate_cache(coord: Vector2i):
	_mesh_cache.erase(coord)
	_mesh_cache_order.erase(coord)

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
	for instance in _terrain_pool:
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_terrain_pool.clear()
	for instance in _water_pool:
		if instance != null and is_instance_valid(instance):
			instance.queue_free()
	_water_pool.clear()
	_mesh_cache.clear()
	_mesh_cache_order.clear()

func _apply_generation(coord: Vector2i, payload: Dictionary):
	var height := payload.get("height", {}) as Dictionary
	if not height.is_empty():
		_voxel_model.apply_chunk_gen_for_coord(coord, {
			"height": height,
			"type": payload.get("type", {}) as Dictionary,
		})
	_voxel_model.apply_tree_chunk_for_coord(coord, {
		"tree_block_fast": payload.get("tree_block_fast", {}) as Dictionary,
	})

func _touch_cache(coord: Vector2i):
	_mesh_cache_order.erase(coord)
	_mesh_cache_order.append(coord)
	if _mesh_cache_order.size() > MAX_MESH_CACHE:
		var oldest := _mesh_cache_order.pop_front() as Vector2i
		_mesh_cache.erase(oldest)

func _cache_terrain_mesh(coord: Vector2i, mesh: ArrayMesh):
	var entry := _mesh_cache.get(coord, {"terrain": null, "water": null}) as Dictionary
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

func _release_render_instances(coord: Vector2i):
	_release_terrain(coord)
	_release_water(coord, true)

func _create_terrain_instance(coord: Vector2i, mesh: ArrayMesh) -> MeshInstance3D:
	var instance := _pop_pooled_instance(_terrain_pool)
	if instance == null:
		instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _terrain_material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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

func _ensure_empty_terrain(coord: Vector2i):
	if _terrain_instances.has(coord):
		var instance := _terrain_instances[coord] as MeshInstance3D
		if instance != null and is_instance_valid(instance):
			instance.mesh = null
			return
	_terrain_instances[coord] = _create_empty_terrain_instance(coord)
