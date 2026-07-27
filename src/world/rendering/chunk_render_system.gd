extends RefCounted
class_name ChunkRenderSystem

## ChunkRenderSystem - schedules mesh jobs, manages chunk mesh nodes
## Canonical: always receives VoxelWorld, no callable fallback, no collision path

var chunk_container: Node3D
var mesher: ChunkMesher
var terrain_material: Material
var voxel_model: VoxelWorld

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var seed_value: int = 1337

var chunk_instances: Dictionary = {}
var dirty_chunks: Dictionary = {}
var max_per_frame: int = 2

var total_rebuilds: int = 0
var last_flush_ms: int = 0


func setup(p_container: Node3D, p_mesher: ChunkMesher, p_material: Material, p_world_size: int, p_chunk_size: int, p_max_y: int, p_seed: int, p_voxel_model: VoxelWorld):
	chunk_container = p_container
	mesher = p_mesher
	terrain_material = p_material
	world_size = p_world_size
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	seed_value = p_seed
	voxel_model = p_voxel_model
	if mesher == null:
		mesher = ChunkMesher.new(world_size, chunk_size, max_build_y, seed_value, true)

func clear():
	for key in chunk_instances.keys():
		var mi = chunk_instances[key]
		if mi and is_instance_valid(mi):
			mi.queue_free()
	chunk_instances.clear()
	dirty_chunks.clear()
	total_rebuilds = 0

func queue_rebuild(cx: int, cz: int):
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
		return
	var key = "%d_%d" % [cx, cz]
	dirty_chunks[key] = Vector2i(cx, cz)

func queue_rebuild_for_world_pos(pos: Vector3i):
	var cx = int(floor(float(pos.x) / float(chunk_size)))
	var cz = int(floor(float(pos.z) / float(chunk_size)))
	queue_rebuild(cx, cz)
	if pos.x % chunk_size == 0:
		queue_rebuild(cx - 1, cz)
	if (pos.x + 1) % chunk_size == 0:
		queue_rebuild(cx + 1, cz)
	if pos.z % chunk_size == 0:
		queue_rebuild(cx, cz - 1)
	if (pos.z + 1) % chunk_size == 0:
		queue_rebuild(cx, cz + 1)

func flush_dirty(max_per_call: int = -1) -> int:
	if max_per_call == -1:
		max_per_call = max_per_frame
	if dirty_chunks.is_empty():
		return 0
	var rebuilt = 0
	var keys = dirty_chunks.keys()
	var start = Time.get_ticks_msec()
	for k in keys:
		if rebuilt >= max_per_call:
			break
		var v = dirty_chunks[k] as Vector2i
		dirty_chunks.erase(k)
		rebuild_immediate(v.x, v.y)
		rebuilt += 1
	last_flush_ms = Time.get_ticks_msec() - start
	if rebuilt > 0:
		total_rebuilds += rebuilt
	return rebuilt

func generate_all_chunks():
	clear()
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	for cx in range(chunks_x):
		for cz in range(chunks_z):
			rebuild_immediate(cx, cz)

func rebuild_immediate(cx: int, cz: int):
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
		return
	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size

	var lookup = func(pos: Vector3i): return voxel_model.get_block_at(pos)
	var mesh = mesher.build_mesh(origin_x, origin_z, lookup, voxel_model.height_map)

	var key = "%d_%d" % [cx, cz]
	if chunk_instances.has(key):
		var mi: MeshInstance3D = chunk_instances[key] as MeshInstance3D
		if not is_instance_valid(mi):
			mi = _create_mesh_instance(mesh, cx, cz)
			chunk_instances[key] = mi
		else:
			mi.mesh = mesh
	else:
		var mi = _create_mesh_instance(mesh, cx, cz)
		chunk_instances[key] = mi

func _create_mesh_instance(mesh: ArrayMesh, cx: int, cz: int) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = terrain_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.name = "Chunk_%d_%d" % [cx, cz]
	chunk_container.add_child(mi)
	return mi

func get_dirty_count() -> int:
	return dirty_chunks.size()

func get_stats() -> Dictionary:
	return {
		"chunks": chunk_instances.size(),
		"dirty": dirty_chunks.size(),
		"total_rebuilds": total_rebuilds,
		"last_flush_ms": last_flush_ms,
		"max_per_frame": max_per_frame,
	}
