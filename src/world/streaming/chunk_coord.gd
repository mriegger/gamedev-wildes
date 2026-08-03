extends RefCounted
class_name ChunkCoord

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

static func get_chunks_in_radius_infinite(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dx in range(-radius, radius + 1):
		for dz in range(-radius, radius + 1):
			out.append(Vector2i(center.x + dx, center.y + dz))
	return out

static func euclidean_distance(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()

static func sort_by_distance(chunks: Array[Vector2i], center: Vector2i) -> Array[Vector2i]:
	var sorted = chunks.duplicate()
	sorted.sort_custom(func(p1, p2): return euclidean_distance(p1, center) < euclidean_distance(p2, center))
	return sorted

static func key_to_chunk(key: String) -> Vector2i:
	var parts = key.split("_")
	if parts.size() != 2:
		return Vector2i(-9999, -9999)
	return Vector2i(int(parts[0]), int(parts[1]))
