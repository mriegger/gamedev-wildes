extends RefCounted
class_name ChunkMesher

## ChunkMesher - converts chunk snapshots into optimized terrain + water geometry
## Supports water blocks as separate translucent mesh with wave shader

var world_size: int = 200
var chunk_size: int = 20
var max_build_y: int = 36
var seed_value: int = 1337
var enable_ao: bool = true
var ao_table: Array = [1.0, 0.86, 0.72, 0.58]

var catalog: BlockCatalog
var _color_cache: Dictionary = {}
var _color_cache_mutex: Mutex = Mutex.new()

func _init(p_world_size: int = 200, p_chunk_size: int = 20, p_max_y: int = 36, p_seed: int = 1337, p_ao: bool = true):
	world_size = p_world_size
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	seed_value = p_seed
	enable_ao = p_ao
	catalog = BlockCatalog.shared()
	_rebuild_color_cache()

func _rebuild_color_cache():
	_color_cache_mutex.lock()
	_color_cache.clear()
	if catalog != null:
		for type_id in [BlockId.Type.GRASS, BlockId.Type.DIRT, BlockId.Type.STONE, BlockId.Type.SAND, BlockId.Type.LOG, BlockId.Type.LEAVES, BlockId.Type.AIR, BlockId.Type.TORCH, BlockId.Type.WATER]:
			var def = catalog.get_definition(type_id)
			if def != null:
				_color_cache[type_id] = {"top": def.top_color, "side": def.side_color}
	_color_cache_mutex.unlock()

func configure_from_config(config: WorldConfig):
	if config.infinite_world:
		world_size = config.get_effective_world_size()
	else:
		world_size = config.world_size
	chunk_size = config.chunk_size
	max_build_y = config.max_build_y
	seed_value = config.seed_value
	enable_ao = config.enable_ao
	_rebuild_color_cache()

# ------------------------------------------------------------------
# Cache building
# ------------------------------------------------------------------
func build_cache(origin_x: int, origin_z: int, get_block_fn: Callable) -> Dictionary:
	var size_x = chunk_size
	var size_z = chunk_size
	var size_y = clamp(max_build_y, 6, 128)
	var cache_x = size_x + 2
	var cache_z = size_z + 2
	var cache: Array = []
	cache.resize(cache_x * size_y * cache_z)

	for lx in range(cache_x):
		for lz in range(cache_z):
			for ly in range(size_y):
				var wx = origin_x + lx - 1
				var wz = origin_z + lz - 1
				var wy = ly
				var v = get_block_fn.call(Vector3i(wx, wy, wz))
				var idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				if v == null or v == BlockId.Type.AIR:
					cache[idx] = -1
				else:
					cache[idx] = v

	return {
		"cache": cache,
		"origin_x": origin_x,
		"origin_z": origin_z,
		"size_x": size_x,
		"size_z": size_z,
		"size_y": size_y,
		"cache_x": cache_x,
		"cache_z": cache_z,
	}

func _is_terrain_solid(block_type: int) -> bool:
	if block_type == -1:
		return false
	if block_type == BlockId.Type.AIR:
		return false
	if block_type == BlockId.Type.TORCH:
		return false
	if block_type == BlockId.Type.WATER:
		return false
	return true

func _is_solid_for_ao(block_type: int) -> bool:
	if block_type == -1:
		return false
	if block_type == BlockId.Type.AIR:
		return false
	if block_type == BlockId.Type.TORCH:
		return false
	if block_type == BlockId.Type.WATER:
		return false
	return true

# ------------------------------------------------------------------
# Terrain mesh (excludes water)
# ------------------------------------------------------------------
func build_mesh_data_from_cache(cache_dict: Dictionary) -> Variant:
	var cache: Array = cache_dict.get("cache", [])
	var origin_x: int = cache_dict.get("origin_x", 0)
	var origin_z: int = cache_dict.get("origin_z", 0)
	var size_x: int = cache_dict.get("size_x", chunk_size)
	var size_z: int = cache_dict.get("size_z", chunk_size)
	var size_y: int = cache_dict.get("size_y", clamp(max_build_y, 6, 128))
	var cache_x: int = cache_dict.get("cache_x", size_x + 2)
	var cache_z: int = cache_dict.get("cache_z", size_z + 2)

	if cache.is_empty():
		return null

	var end_x = min(origin_x + size_x, world_size)
	var end_z = min(origin_z + size_z, world_size)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var local_seed = seed_value
	var local_enable_ao = enable_ao
	var local_ao_table = ao_table
	_color_cache_mutex.lock()
	var local_color_cache = _color_cache.duplicate()
	_color_cache_mutex.unlock()

	for x in range(origin_x, end_x):
		var lx = x - origin_x + 1
		for z in range(origin_z, end_z):
			var lz = z - origin_z + 1
			var h = (x * 73856093) ^ (z * 19349663) ^ local_seed
			h = abs(h) % 1000
			var var_off = (float(h) / 1000.0 - 0.5) * 0.08
			for y in range(size_y):
				var ly = y
				var cache_idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				if cache_idx < 0 or cache_idx >= cache.size():
					continue
				var block_type = cache[cache_idx]
				if block_type == -1:
					continue
				if block_type == BlockId.Type.AIR or block_type == BlockId.Type.TORCH or block_type == BlockId.Type.WATER:
					continue
				var cached = local_color_cache.get(block_type, null)
				if cached == null:
					continue
				var def_top = cached["top"] as Color
				var def_side = cached["side"] as Color
				var top_col = def_top + Color(var_off, var_off, var_off) if block_type != BlockId.Type.LOG and block_type != BlockId.Type.LEAVES else def_top + Color(var_off * 0.5, var_off * 0.5, var_off * 0.5)
				var side_col = def_side + Color(var_off * 0.6, var_off * 0.6, var_off * 0.6) if block_type != BlockId.Type.LOG and block_type != BlockId.Type.LEAVES else def_side
				if block_type == BlockId.Type.GRASS:
					side_col = def_side + Color(var_off * 0.6, var_off * 0.6, var_off * 0.6)

				# +Y
				var n_top = -1
				if ly + 1 < size_y:
					n_top = cache[(lx * size_y * cache_z) + ((ly + 1) * cache_z) + lz]
				if not _is_terrain_solid(n_top):
					var v0 = Vector3(x, y + 1, z)
					var v1 = Vector3(x + 1, y + 1, z)
					var v2 = Vector3(x + 1, y + 1, z + 1)
					var v3 = Vector3(x, y + 1, z + 1)
					var du = [-1, 1, 1, -1]
					var dv = [-1, -1, 1, 1]
					var ao_vals = [0, 0, 0, 0]
					var sh_vals = [1.0, 1.0, 1.0, 1.0]
					for i in range(4):
						var sx = x + du[i]
						var sz_ = z + dv[i]
						var s1 = false
						var s2 = false
						var cs = false
						var clx1 = sx - origin_x + 1
						if clx1 >= 0 and clx1 < cache_x and y + 1 >= 0 and y + 1 < size_y:
							var vv = cache[(clx1 * size_y * cache_z) + ((y + 1) * cache_z) + lz]
							if _is_solid_for_ao(vv):
								s1 = true
						var clz2 = sz_ - origin_z + 1
						if clz2 >= 0 and clz2 < cache_z and y + 1 >= 0 and y + 1 < size_y:
							var vv2 = cache[(lx * size_y * cache_z) + ((y + 1) * cache_z) + clz2]
							if _is_solid_for_ao(vv2):
								s2 = true
						var clx_c = sx - origin_x + 1
						var clz_c = sz_ - origin_z + 1
						if clx_c >= 0 and clx_c < cache_x and clz_c >= 0 and clz_c < cache_z and y + 1 >= 0 and y + 1 < size_y:
							var vvc = cache[(clx_c * size_y * cache_z) + ((y + 1) * cache_z) + clz_c]
							if _is_solid_for_ao(vvc):
								cs = true
						var ao = 0
						if s1 and s2:
							ao = 3
						else:
							if s1: ao += 1
							if s2: ao += 1
							if cs: ao += 1
						ao_vals[i] = ao
						var vx = x + (1 if i == 1 or i == 2 else 0)
						var vz_ = z + (1 if i == 2 or i == 3 else 0)
						var best_sh = 1.0
						for ox in range(-1, 2):
							for oz in range(-1, 2):
								var horiz = sqrt(float(ox * ox + oz * oz))
								for dy in range(2, 8):
									var wy2 = y + dy
									if wy2 >= 128:
										break
									var wwx = vx + ox
									var wwz = vz_ + oz
									var clx_s = wwx - origin_x + 1
									var clz_s = wwz - origin_z + 1
									var solid = false
									if clx_s >= 0 and clx_s < cache_x and clz_s >= 0 and clz_s < cache_z and wy2 >= 0 and wy2 < size_y:
										var vvs = cache[(clx_s * size_y * cache_z) + (wy2 * cache_z) + clz_s]
										if _is_solid_for_ao(vvs):
											solid = true
									if solid:
										var vert = dy - 1
										var f = 0.72 + float(vert - 1) * 0.06 + horiz * 0.10
										if f > 0.97: f = 0.97
										if f < best_sh: best_sh = f
										break
						sh_vals[i] = best_sh
					var base_idx = vertices.size()
					vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
					normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0))
					for i in range(4):
						var b = local_ao_table[ao_vals[i]] if local_enable_ao else 1.0
						var sh = sh_vals[i]
						colors.append(Color(top_col.r * b * sh, top_col.g * b * sh, top_col.b * b * sh, top_col.a))
					indices.append(base_idx+0); indices.append(base_idx+1); indices.append(base_idx+2)
					indices.append(base_idx+0); indices.append(base_idx+2); indices.append(base_idx+3)

				# -Y
				var n_bot = -1
				if ly - 1 >= 0:
					n_bot = cache[(lx * size_y * cache_z) + ((ly - 1) * cache_z) + lz]
				if not _is_terrain_solid(n_bot):
					if y > 0:
						var bcol = side_col * 0.92
						var du2 = [-1, 1, 1, -1]
						var dv2 = [1, 1, -1, -1]
						var ao2 = [0, 0, 0, 0]
						for i in range(4):
							var sx = x + du2[i]
							var sz_ = z + dv2[i]
							var s1 = false
							var s2 = false
							var cs = false
							var clx1 = sx - origin_x + 1
							if clx1 >= 0 and clx1 < cache_x and y - 1 >= 0 and y - 1 < size_y:
								var vv = cache[(clx1 * size_y * cache_z) + ((y - 1) * cache_z) + lz]
								if _is_solid_for_ao(vv):
									s1 = true
							var clz2 = sz_ - origin_z + 1
							if clz2 >= 0 and clz2 < cache_z and y - 1 >= 0 and y - 1 < size_y:
								var vv2 = cache[(lx * size_y * cache_z) + ((y - 1) * cache_z) + clz2]
								if _is_solid_for_ao(vv2):
									s2 = true
							var clx_c = sx - origin_x + 1
							var clz_c = sz_ - origin_z + 1
							if clx_c >= 0 and clx_c < cache_x and clz_c >= 0 and clz_c < cache_z and y - 1 >= 0 and y - 1 < size_y:
								var vvc = cache[(clx_c * size_y * cache_z) + ((y - 1) * cache_z) + clz_c]
								if _is_solid_for_ao(vvc):
									cs = true
							var ao = 0
							if s1 and s2: ao = 3
							else:
								if s1: ao += 1
								if s2: ao += 1
								if cs: ao += 1
							ao2[i] = ao
						var base_idx2 = vertices.size()
						vertices.append(Vector3(x, y, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x, y, z))
						normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0))
						for i in range(4):
							var b = local_ao_table[ao2[i]] if local_enable_ao else 1.0
							colors.append(Color(bcol.r * b, bcol.g * b, bcol.b * b, bcol.a))
						indices.append(base_idx2+0); indices.append(base_idx2+1); indices.append(base_idx2+2)
						indices.append(base_idx2+0); indices.append(base_idx2+2); indices.append(base_idx2+3)

				# +X
				var n_east = -1
				if lx + 1 < cache_x:
					n_east = cache[((lx + 1) * size_y * cache_z) + (ly * cache_z) + lz]
				if not _is_terrain_solid(n_east):
					var base_idx3 = vertices.size()
					vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z)); vertices.append(Vector3(x+1, y, z))
					normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx3+0); indices.append(base_idx3+1); indices.append(base_idx3+2)
					indices.append(base_idx3+0); indices.append(base_idx3+2); indices.append(base_idx3+3)

				# -X
				var n_west = -1
				if lx - 1 >= 0:
					n_west = cache[((lx - 1) * size_y * cache_z) + (ly * cache_z) + lz]
				if not _is_terrain_solid(n_west):
					var base_idx4 = vertices.size()
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x, y+1, z)); vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx4+0); indices.append(base_idx4+1); indices.append(base_idx4+2)
					indices.append(base_idx4+0); indices.append(base_idx4+2); indices.append(base_idx4+3)

				# +Z
				var n_south = -1
				if lz + 1 < cache_z:
					n_south = cache[(lx * size_y * cache_z) + (ly * cache_z) + (lz + 1)]
				if not _is_terrain_solid(n_south):
					var base_idx5 = vertices.size()
					vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx5+0); indices.append(base_idx5+1); indices.append(base_idx5+2)
					indices.append(base_idx5+0); indices.append(base_idx5+2); indices.append(base_idx5+3)

				# -Z
				var n_north = -1
				if lz - 1 >= 0:
					n_north = cache[(lx * size_y * cache_z) + (ly * cache_z) + (lz - 1)]
				if not _is_terrain_solid(n_north):
					var base_idx6 = vertices.size()
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x+1, y+1, z)); vertices.append(Vector3(x, y+1, z))
					normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx6+0); indices.append(base_idx6+1); indices.append(base_idx6+2)
					indices.append(base_idx6+0); indices.append(base_idx6+2); indices.append(base_idx6+3)

	if vertices.is_empty():
		return null

	return {
		"vertices": vertices,
		"normals": normals,
		"colors": colors,
		"indices": indices,
		"origin_x": origin_x,
		"origin_z": origin_z,
	}

# Water mesh - no foam, no dead plumbing (no colors/uv2s for foam)
func build_water_mesh_data_from_cache(cache_dict: Dictionary) -> Variant:
	var cache: Array = cache_dict.get("cache", [])
	var origin_x: int = cache_dict.get("origin_x", 0)
	var origin_z: int = cache_dict.get("origin_z", 0)
	var size_x: int = cache_dict.get("size_x", chunk_size)
	var size_z: int = cache_dict.get("size_z", chunk_size)
	var size_y: int = cache_dict.get("size_y", clamp(max_build_y, 6, 128))
	var cache_x: int = cache_dict.get("cache_x", size_x + 2)
	var cache_z: int = cache_dict.get("cache_z", size_z + 2)

	if cache.is_empty():
		return null

	var end_x = min(origin_x + size_x, world_size)
	var end_z = min(origin_z + size_z, world_size)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()

	const WATER_SURFACE_HEIGHT: float = 0.75
	const WATER_UV_SCALE: float = 0.12

	for x in range(origin_x, end_x):
		var lx = x - origin_x + 1
		for z in range(origin_z, end_z):
			var lz = z - origin_z + 1
			for y in range(size_y):
				var ly = y
				var cache_idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				if cache_idx < 0 or cache_idx >= cache.size():
					continue
				if cache[cache_idx] != BlockId.Type.WATER:
					continue

				var n_top = -1
				if ly + 1 < size_y:
					n_top = cache[(lx * size_y * cache_z) + ((ly + 1) * cache_z) + lz]
				var is_top_surface = n_top != BlockId.Type.WATER
				var vis_top_h = WATER_SURFACE_HEIGHT if is_top_surface else 1.0

				if is_top_surface:
					var above_solid = n_top != -1 and n_top != BlockId.Type.AIR and n_top != BlockId.Type.TORCH and n_top != BlockId.Type.WATER
					if not above_solid:
						var top_y = y + WATER_SURFACE_HEIGHT
						var v0 = Vector3(x, top_y, z)
						var v1 = Vector3(x + 1, top_y, z)
						var v2 = Vector3(x + 1, top_y, z + 1)
						var v3 = Vector3(x, top_y, z + 1)
						var base_idx = vertices.size()
						vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
						normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0))
						uvs.append(Vector2(x, z) * WATER_UV_SCALE)
						uvs.append(Vector2(x + 1, z) * WATER_UV_SCALE)
						uvs.append(Vector2(x + 1, z + 1) * WATER_UV_SCALE)
						uvs.append(Vector2(x, z + 1) * WATER_UV_SCALE)
						for _t in range(4):
							tangents.append(1.0); tangents.append(0.0); tangents.append(0.0); tangents.append(-1.0)
						indices.append(base_idx+0); indices.append(base_idx+1); indices.append(base_idx+2)
						indices.append(base_idx+0); indices.append(base_idx+2); indices.append(base_idx+3)

				var n_bot = -1
				if ly - 1 >= 0:
					n_bot = cache[(lx * size_y * cache_z) + ((ly - 1) * cache_z) + lz]
				if n_bot == -1 or n_bot == BlockId.Type.AIR or n_bot == BlockId.Type.TORCH:
					var base_idx2 = vertices.size()
					vertices.append(Vector3(x, y, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x, y, z))
					normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0))
					uvs.append(Vector2(x, z + 1) * WATER_UV_SCALE)
					uvs.append(Vector2(x + 1, z + 1) * WATER_UV_SCALE)
					uvs.append(Vector2(x + 1, z) * WATER_UV_SCALE)
					uvs.append(Vector2(x, z) * WATER_UV_SCALE)
					for _t in range(4):
						tangents.append(1.0); tangents.append(0.0); tangents.append(0.0); tangents.append(1.0)
					indices.append(base_idx2+0); indices.append(base_idx2+1); indices.append(base_idx2+2)
					indices.append(base_idx2+0); indices.append(base_idx2+2); indices.append(base_idx2+3)

				var n_east = -1
				if lx + 1 < cache_x:
					n_east = cache[((lx + 1) * size_y * cache_z) + (ly * cache_z) + lz]
				if n_east == -1 or n_east == BlockId.Type.AIR or n_east == BlockId.Type.TORCH:
					var base_idx3 = vertices.size()
					var yt = y + vis_top_h
					vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, yt, z+1)); vertices.append(Vector3(x+1, yt, z)); vertices.append(Vector3(x+1, y, z))
					normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0))
					uvs.append(Vector2((z + 1) * WATER_UV_SCALE, y * WATER_UV_SCALE))
					uvs.append(Vector2((z + 1) * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2(z * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2(z * WATER_UV_SCALE, y * WATER_UV_SCALE))
					for _t in range(4):
						tangents.append(0.0); tangents.append(0.0); tangents.append(1.0); tangents.append(-1.0)
					indices.append(base_idx3+0); indices.append(base_idx3+1); indices.append(base_idx3+2)
					indices.append(base_idx3+0); indices.append(base_idx3+2); indices.append(base_idx3+3)

				var n_west = -1
				if lx - 1 >= 0:
					n_west = cache[((lx - 1) * size_y * cache_z) + (ly * cache_z) + lz]
				if n_west == -1 or n_west == BlockId.Type.AIR or n_west == BlockId.Type.TORCH:
					var base_idx4 = vertices.size()
					var yt = y + vis_top_h
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x, yt, z)); vertices.append(Vector3(x, yt, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0))
					uvs.append(Vector2(z * WATER_UV_SCALE, y * WATER_UV_SCALE))
					uvs.append(Vector2(z * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2((z + 1) * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2((z + 1) * WATER_UV_SCALE, y * WATER_UV_SCALE))
					for _t in range(4):
						tangents.append(0.0); tangents.append(0.0); tangents.append(1.0); tangents.append(1.0)
					indices.append(base_idx4+0); indices.append(base_idx4+1); indices.append(base_idx4+2)
					indices.append(base_idx4+0); indices.append(base_idx4+2); indices.append(base_idx4+3)

				var n_south = -1
				if lz + 1 < cache_z:
					n_south = cache[(lx * size_y * cache_z) + (ly * cache_z) + (lz + 1)]
				if n_south == -1 or n_south == BlockId.Type.AIR or n_south == BlockId.Type.TORCH:
					var base_idx5 = vertices.size()
					var yt = y + vis_top_h
					vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1))
					uvs.append(Vector2(x * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2((x + 1) * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2((x + 1) * WATER_UV_SCALE, y * WATER_UV_SCALE))
					uvs.append(Vector2(x * WATER_UV_SCALE, y * WATER_UV_SCALE))
					for _t in range(4):
						tangents.append(1.0); tangents.append(0.0); tangents.append(0.0); tangents.append(1.0)
					indices.append(base_idx5+0); indices.append(base_idx5+1); indices.append(base_idx5+2)
					indices.append(base_idx5+0); indices.append(base_idx5+2); indices.append(base_idx5+3)

				var n_north = -1
				if lz - 1 >= 0:
					n_north = cache[(lx * size_y * cache_z) + (ly * cache_z) + (lz - 1)]
				if n_north == -1 or n_north == BlockId.Type.AIR or n_north == BlockId.Type.TORCH:
					var base_idx6 = vertices.size()
					var yt = y + vis_top_h
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x+1, yt, z)); vertices.append(Vector3(x, y+1, z))
					normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1))
					uvs.append(Vector2(x * WATER_UV_SCALE, y * WATER_UV_SCALE))
					uvs.append(Vector2((x + 1) * WATER_UV_SCALE, y * WATER_UV_SCALE))
					uvs.append(Vector2((x + 1) * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					uvs.append(Vector2(x * WATER_UV_SCALE, yt * WATER_UV_SCALE))
					for _t in range(4):
						tangents.append(1.0); tangents.append(0.0); tangents.append(0.0); tangents.append(-1.0)
					indices.append(base_idx6+0); indices.append(base_idx6+1); indices.append(base_idx6+2)
					indices.append(base_idx6+0); indices.append(base_idx6+2); indices.append(base_idx6+3)

	if vertices.is_empty():
		return null

	return {
		"vertices": vertices,
		"normals": normals,
		"uvs": uvs,
		"tangents": tangents,
		"indices": indices,
		"origin_x": origin_x,
		"origin_z": origin_z,
	}

func build_combined_mesh_data(cache_dict: Dictionary) -> Dictionary:
	var terrain = build_mesh_data_from_cache(cache_dict)
	var water = build_water_mesh_data_from_cache(cache_dict)
	return {"terrain": terrain, "water": water}

func create_mesh_from_data(data) -> ArrayMesh:
	if data == null:
		return null
	if not data is Dictionary:
		return null
	if data.has("terrain"):
		data = data.get("terrain")
		if data == null:
			return null
	var vertices = data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		return null
	var normals = data.get("normals", PackedVector3Array())
	var colors = data.get("colors", PackedColorArray())
	var indices = data.get("indices", PackedInt32Array())

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func create_water_mesh_from_data(data) -> ArrayMesh:
	if data == null:
		return null
	if not data is Dictionary:
		return null
	if data.has("water"):
		data = data.get("water")
		if data == null:
			return null
	var vertices = data.get("vertices", PackedVector3Array())
	if vertices.is_empty():
		return null
	var normals = data.get("normals", PackedVector3Array())
	var uvs = data.get("uvs", PackedVector2Array())
	var tangents = data.get("tangents", PackedFloat32Array())
	var indices = data.get("indices", PackedInt32Array())

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not tangents.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func build_mesh(origin_x: int, origin_z: int, get_block_fn: Callable, height_map: Array = []) -> ArrayMesh:
	var cache_dict = build_cache(origin_x, origin_z, get_block_fn)
	var data = build_mesh_data_from_cache(cache_dict)
	return create_mesh_from_data(data)
