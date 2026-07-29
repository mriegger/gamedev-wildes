extends RefCounted
class_name ChunkCoord

## ChunkCoord - pure static helpers for world<->chunk conversion and radius queries

static func world_to_chunk(world_pos: Vector3, chunk_size: int) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / float(chunk_size))),
		int(floor(world_pos.z / float(chunk_size)))
	)

static func world_to_chunk_vec3i(world_pos: Vector3i, chunk_size: int) -> Vector2i:
	return Vector2i(
		int(floor(float(world_pos.x) / float(chunk_size))),
		int(floor(float(world_pos.z) / float(chunk_size)))
	)

static func world_to_chunk_2d(x: float, z: float, chunk_size: int) -> Vector2i:
	return Vector2i(
		int(floor(x / float(chunk_size))),
		int(floor(z / float(chunk_size)))
	)

static func chunk_to_world_origin(chunk: Vector2i, chunk_size: int) -> Vector3i:
	return Vector3i(chunk.x * chunk_size, 0, chunk.y * chunk_size)

static func chunk_to_world_origin_vec3(chunk: Vector2i, chunk_size: int) -> Vector3:
	return Vector3(chunk.x * chunk_size, 0, chunk.y * chunk_size)

static func get_chunks_in_radius(center: Vector2i, radius: int, world_size: int, chunk_size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cx = center.x + dx
			var cz = center.y + dz
			if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
				continue
			out.append(Vector2i(cx, cz))
	return out

static func get_chunks_in_radius_infinite(center: Vector2i, radius: int) -> Array[Vector2i]:
	# No world bounds clamping - for infinite world
	var out: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			var cx = center.x + dx
			var cz = center.y + dz
			out.append(Vector2i(cx, cz))
	return out

static func get_chunks_in_radius_circular(center: Vector2i, radius: int, world_size: int, chunk_size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if Vector2i(dx, dz).length() > float(radius) + 0.4:
				continue
			var cx = center.x + dx
			var cz = center.y + dz
			if cx < 0 or cz < 0 or cx >= chunks_x or cz >= chunks_z:
				continue
			out.append(Vector2i(cx, cz))
	return out

static func get_chunks_in_radius_circular_infinite(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			if Vector2i(dx, dz).length() > float(radius) + 0.4:
				continue
			out.append(Vector2i(center.x + dx, center.y + dz))
	return out

static func chebyshev_distance(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

static func euclidean_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

static func sort_by_distance(chunks: Array[Vector2i], center: Vector2i) -> Array[Vector2i]:
	var sorted = chunks.duplicate()
	sorted.sort_custom(func(p1, p2): return euclidean_distance(p1, center) < euclidean_distance(p2, center))
	return sorted

static func is_valid_chunk(coord: Vector2i, world_size: int, chunk_size: int, infinite: bool = false) -> bool:
	if infinite:
		return true
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	return coord.x >= 0 and coord.y >= 0 and coord.x < chunks_x and coord.y < chunks_z

static func world_pos_to_chunk_key(world_pos: Vector3, chunk_size: int) -> String:
	var c = world_to_chunk(world_pos, chunk_size)
	return "%d_%d" % [c.x, c.y]

static func chunk_to_key(chunk: Vector2i) -> String:
	return "%d_%d" % [chunk.x, chunk.y]

static func key_to_chunk(key: String) -> Vector2i:
	var parts = key.split("_")
	if parts.size() != 2:
		return Vector2i(-9999, -9999)
	return Vector2i(int(parts[0]), int(parts[1]))
