extends SceneTree

const SPECIES_IDS: Array[int] = [
	BlockId.Type.SHORT_GRASS,
	BlockId.Type.GRASS_FOLIAGE,
	BlockId.Type.BLUE_WILDFLOWER,
	BlockId.Type.ORANGE_TULIP,
	BlockId.Type.PINK_HEARTFLOWER,
	BlockId.Type.RED_FLOWER,
]

var _errors: Array[String] = []
var _block_catalog: BlockCatalog
var _foliage_catalog: FoliageCatalog
var _block_texture_set: BlockTextureSet
var _foliage_texture_set: FoliageTextureSet
var _chunk_mesher: ChunkMesher
var _foliage_mesher: FoliageMesher

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_foliage_catalog = load("res://foliage/foliage_catalog.tres") as FoliageCatalog
	_expect(_block_catalog != null and _block_catalog.validate(), "block catalog did not load or validate")
	_expect(_foliage_catalog != null and _foliage_catalog.validate(_block_catalog), "foliage catalog did not load or validate")
	if _block_catalog == null or _foliage_catalog == null:
		_finish()
		return
	_block_texture_set = BlockTextureSet.new(_block_catalog)
	_foliage_texture_set = FoliageTextureSet.new(_foliage_catalog)
	_chunk_mesher = ChunkMesher.new(SPECIES_IDS.size(), 3, 7, false, _block_texture_set)
	_foliage_mesher = FoliageMesher.new(_foliage_texture_set, 7)
	_test_texture_layers()
	var cache := _make_cache()
	var foliage_data: Variant = _test_crossed_quad_mesh(cache["foliage_cells"] as PackedInt32Array)
	if foliage_data != null:
		await _test_renderer_lifecycle(cache, foliage_data)
		await _test_stale_foliage_result(cache, foliage_data)
	_finish()

func _test_texture_layers() -> void:
	_expect(_foliage_texture_set.texture_array != null, "foliage texture array was not created")
	if _foliage_texture_set.texture_array == null:
		return
	_expect(_foliage_texture_set.texture_array.get_layers() == SPECIES_IDS.size(), "foliage texture layer count changed")
	for block_id in SPECIES_IDS:
		var layer := _foliage_texture_set.texture_layers[block_id]
		_expect(layer >= 0 and layer < _foliage_texture_set.texture_array.get_layers(), "foliage texture layer is out of bounds for %s" % BlockId.get_display_name(block_id))

func _test_crossed_quad_mesh(cells: PackedInt32Array) -> Variant:
	var data: Variant = _foliage_mesher.build_mesh_data(cells)
	_expect(data != null, "foliage mesher returned no data")
	if data == null:
		return null
	var vertices := data["vertices"] as PackedVector3Array
	var uvs := data["uvs"] as PackedVector2Array
	var layers := data["texture_layers"] as PackedVector2Array
	var indices := data["indices"] as PackedInt32Array
	var expected_vertices := SPECIES_IDS.size() * 8
	var expected_indices := SPECIES_IDS.size() * 12
	_expect(vertices.size() == expected_vertices, "crossed-quad vertex count changed")
	_expect(indices.size() == expected_indices, "crossed-quad index count changed")
	_expect(not data.has("normals"), "foliage mesh retained constant CPU normal data")
	_expect(not data.has("colors"), "foliage mesh retained constant white color data")
	_expect(uvs.size() == vertices.size(), "foliage UV count differs from vertices")
	_expect(layers.size() == vertices.size(), "foliage texture-layer count differs from vertices")
	for species_index in SPECIES_IDS.size():
		var expected_layer := float(_foliage_texture_set.texture_layers[SPECIES_IDS[species_index]])
		var expected_uv_rect := _foliage_texture_set.texture_uv_rects[SPECIES_IDS[species_index]]
		for vertex_index in range(species_index * 8, species_index * 8 + 8):
			_expect(is_equal_approx(layers[vertex_index].x, expected_layer), "foliage texture layer does not match its species")
			_expect(is_zero_approx(layers[vertex_index].y), "foliage secondary texture layer changed")
		for plane_offset in [0, 4]:
			var uv_start: int = species_index * 8 + plane_offset
			_expect(uvs[uv_start] == expected_uv_rect.position + Vector2(0.0, expected_uv_rect.size.y), "foliage bottom-left UV was not cropped")
			_expect(uvs[uv_start + 1] == expected_uv_rect.end, "foliage bottom-right UV was not cropped")
			_expect(uvs[uv_start + 2] == expected_uv_rect.position + Vector2(expected_uv_rect.size.x, 0.0), "foliage top-right UV was not cropped")
			_expect(uvs[uv_start + 3] == expected_uv_rect.position, "foliage top-left UV was not cropped")
	var matching_data := FoliageMesher.new(_foliage_texture_set, 7).build_mesh_data(cells) as Dictionary
	var varied_data := FoliageMesher.new(_foliage_texture_set, 8).build_mesh_data(cells) as Dictionary
	_expect((matching_data["vertices"] as PackedVector3Array) == vertices, "same seed changed foliage presentation")
	_expect((varied_data["vertices"] as PackedVector3Array) != vertices, "different seed preserved every foliage transform")
	for species_index in SPECIES_IDS.size():
		var start := species_index * 8
		var first_center := (vertices[start] + vertices[start + 1]) * 0.5
		var second_center := (vertices[start + 4] + vertices[start + 5]) * 0.5
		_expect(first_center.distance_to(second_center) < 0.0001, "foliage planes no longer cross at one center")
		for vertex_index in range(start, start + 8):
			var vertex := vertices[vertex_index]
			_expect(vertex.x >= float(species_index) - 0.08 and vertex.x <= float(species_index + 1) + 0.08, "foliage variation escaped its cell on X")
			_expect(vertex.z >= -0.08 and vertex.z <= 1.08, "foliage variation escaped its cell on Z")
			_expect(vertex.y >= 1.0 and vertex.y <= 2.03, "foliage variation escaped its vertical bounds")
	var mesh := _foliage_mesher.create_mesh_from_data(data)
	_expect(mesh != null and mesh.get_surface_count() == 1, "foliage mesh surface was not created")
	if mesh != null and mesh.get_surface_count() == 1:
		var arrays := mesh.surface_get_arrays(0)
		_expect((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array) == vertices, "foliage vertices were not installed on the mesh")
		_expect((arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array) == layers, "foliage layers were not installed on the mesh")
		_expect(arrays[Mesh.ARRAY_NORMAL] == null, "foliage mesh uploaded constant normals")
		_expect(arrays[Mesh.ARRAY_COLOR] == null, "foliage mesh uploaded constant colors")
	return data

func _test_renderer_lifecycle(cache: Dictionary, foliage_data: Dictionary) -> void:
	var terrain_data: Variant = _chunk_mesher.build_mesh_data_from_cache(cache)
	_expect(terrain_data != null, "terrain fixture mesh was not created")
	if terrain_data == null:
		return
	var terrain_material := ShaderMaterial.new()
	terrain_material.shader = load("res://world/materials/terrain.gdshader") as Shader
	terrain_material.set_shader_parameter("terrain_textures", _block_texture_set.texture_array)
	var foliage_material := ShaderMaterial.new()
	foliage_material.shader = load("res://foliage/presentation/foliage.gdshader") as Shader
	foliage_material.set_shader_parameter("foliage_textures", _foliage_texture_set.texture_array)
	_expect(foliage_material.get_shader_parameter("foliage_textures") == _foliage_texture_set.texture_array, "foliage material did not bind its texture array")
	var world := VoxelWorld.new(SPECIES_IDS.size(), 3, 0, 0.0, _block_catalog)
	var renderer := ChunkRenderer.new()
	root.add_child(renderer)
	renderer.setup(_chunk_mesher, _foliage_mesher, terrain_material, StandardMaterial3D.new(), foliage_material, world, 0)
	var coord := Vector2i.ZERO
	var foliage_cells := cache["foliage_cells"] as PackedInt32Array
	renderer.apply_result(_make_result(coord, terrain_data, foliage_cells, foliage_data))
	_expect(renderer._terrain_instances.has(coord), "terrain instance was not created")
	_expect(renderer._foliage_instances.has(coord), "foliage instance was not created")
	var foliage_instance := renderer._foliage_instances.get(coord, null) as MeshInstance3D
	_expect(foliage_instance != null and foliage_instance.material_override == foliage_material, "foliage instance did not use its dedicated material")
	_expect(foliage_instance != null and foliage_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "foliage cast noisy per-tuft shadows")
	var terrain_mesh_before := (renderer._terrain_instances[coord] as MeshInstance3D).mesh
	var reduced_cells := (cache["foliage_cells"] as PackedInt32Array).duplicate()
	reduced_cells.resize(reduced_cells.size() - FoliageCellSnapshot.STRIDE)
	renderer._cache_terrain_mesh(coord, terrain_mesh_before)
	var chunk_manager := ChunkManager.new()
	chunk_manager._renderer = renderer
	chunk_manager.visible_chunks[coord] = true
	chunk_manager.refresh_foliage(coord, reduced_cells)
	_expect(not renderer._mesh_cache.has(coord), "foliage refresh retained a stale cached mesh")
	_expect((renderer._terrain_instances[coord] as MeshInstance3D).mesh == terrain_mesh_before, "foliage refresh replaced the terrain mesh")
	var refreshed_foliage_mesh := (renderer._foliage_instances[coord] as MeshInstance3D).mesh as ArrayMesh
	var refreshed_vertices := refreshed_foliage_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	_expect(refreshed_vertices.size() == (SPECIES_IDS.size() - 1) * FoliageMesher.VERTICES_PER_CELL, "foliage refresh rebuilt the wrong plant count")
	_expect(chunk_manager._dirty_chunks.is_empty(), "foliage refresh queued a full chunk rebuild")
	chunk_manager.refresh_foliage(coord, PackedInt32Array())
	_expect(not renderer._foliage_instances.has(coord), "empty foliage refresh retained the last plant mesh")
	_expect((renderer._terrain_instances[coord] as MeshInstance3D).mesh == terrain_mesh_before, "empty foliage refresh replaced the terrain mesh")
	chunk_manager.refresh_foliage(coord, cache["foliage_cells"] as PackedInt32Array)
	foliage_instance = renderer._foliage_instances.get(coord, null) as MeshInstance3D
	chunk_manager.visible_chunks.erase(coord)
	chunk_manager._requested_meshes[coord] = true
	chunk_manager.refresh_foliage(coord, reduced_cells)
	_expect(chunk_manager._dirty_chunks.has(coord), "foliage edit during initial mesh loading did not queue a current rebuild")
	chunk_manager._requested_meshes.erase(coord)
	chunk_manager._dirty_chunks.erase(coord)
	chunk_manager.visible_chunks[coord] = true
	renderer.set_shadow_center(Vector2i.ONE)
	_expect(foliage_instance != null and foliage_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "distant foliage enabled shadows")
	renderer.set_shadow_center(Vector2i.ZERO)
	_expect(foliage_instance != null and foliage_instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "near foliage enabled shadows")
	renderer.apply_result(_make_result(coord, terrain_data, PackedInt32Array(), null))
	_expect(not renderer._foliage_instances.has(coord), "null foliage result left a stale instance")
	_expect(renderer._foliage_pool.size() == 1, "released foliage instance did not enter the pool")
	renderer.apply_result(_make_result(coord, terrain_data, foliage_cells, foliage_data))
	_expect(renderer._foliage_instances.has(coord), "foliage instance was not recreated from the pool")
	_expect(renderer._foliage_pool.is_empty(), "foliage pool was not reused")
	renderer.unload(coord)
	_expect(not renderer._terrain_instances.has(coord) and not renderer._foliage_instances.has(coord), "chunk unload left render instances active")
	_expect(renderer._mesh_cache.has(coord), "chunk unload did not cache its meshes")
	if renderer._mesh_cache.has(coord):
		var entry := renderer._mesh_cache[coord] as Dictionary
		_expect(entry.get("foliage", null) is ArrayMesh, "chunk cache omitted foliage mesh")
	_expect(renderer.restore_cached(coord), "cached chunk did not restore")
	_expect(renderer._terrain_instances.has(coord) and renderer._foliage_instances.has(coord), "cached foliage did not restore with terrain")
	var terrain_mesh := (renderer._terrain_instances[coord] as MeshInstance3D).mesh as ArrayMesh
	for index in range(ChunkRenderer.MAX_MESH_CACHE + 1):
		renderer._cache_terrain_mesh(Vector2i(index, 1), terrain_mesh)
	_expect(renderer._mesh_cache.size() == ChunkRenderer.MAX_MESH_CACHE, "foliage-capable mesh cache exceeded its bound")
	_expect(not renderer._mesh_cache.has(Vector2i(0, 1)), "mesh cache did not evict its oldest coordinate")
	renderer.queue_free()
	await process_frame

func _test_stale_foliage_result(cache: Dictionary, foliage_data: Dictionary) -> void:
	var terrain_data: Variant = _chunk_mesher.build_mesh_data_from_cache(cache)
	var world := VoxelWorld.new(SPECIES_IDS.size(), 3, 0, 0.0, _block_catalog)
	var renderer := ChunkRenderer.new()
	root.add_child(renderer)
	renderer.setup(_chunk_mesher, _foliage_mesher, StandardMaterial3D.new(), StandardMaterial3D.new(), StandardMaterial3D.new(), world, 0)
	var foliage_cells := cache["foliage_cells"] as PackedInt32Array
	var blocked_position := Vector3i(foliage_cells[0], foliage_cells[1], foliage_cells[2])
	var tree_blocks: Dictionary = {blocked_position: BlockId.Type.LEAVES}
	world.apply_tree_chunk_for_coord(Vector2i.LEFT, {"tree_block_fast": tree_blocks})
	renderer.apply_result(_make_result(Vector2i.ZERO, terrain_data, foliage_cells, foliage_data))
	var foliage_instance := renderer._foliage_instances.get(Vector2i.ZERO, null) as MeshInstance3D
	_expect(foliage_instance != null, "stale foliage reconciliation removed unaffected plants")
	if foliage_instance != null:
		var foliage_mesh := foliage_instance.mesh as ArrayMesh
		_expect(foliage_mesh != null, "stale foliage reconciliation produced no mesh")
		if foliage_mesh != null:
			var vertices := foliage_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
			_expect(vertices.size() == (SPECIES_IDS.size() - 1) * FoliageMesher.VERTICES_PER_CELL, "stale worker foliage mesh ignored authoritative tree occupancy")
	renderer.queue_free()
	await process_frame

func _make_cache() -> Dictionary:
	var size_x := SPECIES_IDS.size()
	var size_y := 3
	var cache_z := 3
	var cache := PackedInt32Array()
	var foliage_cells := PackedInt32Array()
	cache.resize((size_x + 2) * size_y * cache_z)
	cache.fill(BlockId.Type.AIR)
	for x in size_x:
		var column_offset := (x + 1) * size_y * cache_z
		cache[column_offset + 1] = BlockId.Type.GRASS
		cache[column_offset + cache_z + 1] = SPECIES_IDS[x]
		foliage_cells.append(x)
		foliage_cells.append(1)
		foliage_cells.append(0)
		foliage_cells.append(SPECIES_IDS[x])
	return {
		"cache": cache,
		"origin_x": 0,
		"origin_z": 0,
		"size_x": size_x,
		"size_z": 1,
		"size_y": size_y,
		"cache_x": size_x + 2,
		"cache_z": cache_z,
		"foliage_cells": foliage_cells,
	}

func _make_result(coord: Vector2i, terrain_data: Variant, foliage_cells: PackedInt32Array, foliage_data: Variant) -> ChunkBuildResult:
	var foliage_blocks: Dictionary = {}
	for offset in range(0, foliage_cells.size(), FoliageCellSnapshot.STRIDE):
		foliage_blocks[Vector3i(foliage_cells[offset], foliage_cells[offset + 1], foliage_cells[offset + 2])] = foliage_cells[offset + 3]
	return ChunkBuildResult.new(coord, 0, false, {"foliage_block_fast": foliage_blocks}, terrain_data, null, foliage_cells, foliage_data)

func _finish() -> void:
	if _errors.is_empty():
		print("FOLIAGE_RENDERING PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
