extends RefCounted
class_name ChunkMesher

var chunk_size: int = 20
var max_build_y: int = 36
var seed_value: int = 1337
var enable_ao: bool = true
var ao_table: Array = [1.0, 0.86, 0.72, 0.58]

var block_catalog: BlockCatalog
var _top_colors = PackedColorArray()
var _side_colors = PackedColorArray()

func _init(p_chunk_size: int, p_max_y: int, p_seed: int, p_ao: bool, p_block_catalog: BlockCatalog):
	chunk_size = p_chunk_size
	max_build_y = p_max_y
	seed_value = p_seed
	enable_ao = p_ao
	block_catalog = p_block_catalog
	_rebuild_color_cache()

func _rebuild_color_cache():
	_top_colors.resize(BlockId.Type.COUNT)
	_side_colors.resize(BlockId.Type.COUNT)
	for type_id in range(BlockId.Type.COUNT):
		var def = block_catalog.get_definition(type_id)
		_top_colors[type_id] = def.top_color
		_side_colors[type_id] = def.side_color

func build_mesh_data_from_cache(cache_dict: Dictionary) -> Variant:
	var cache: PackedInt32Array = cache_dict.get("cache", PackedInt32Array())
	var origin_x: int = cache_dict.get("origin_x", 0)
	var origin_z: int = cache_dict.get("origin_z", 0)
	var size_x: int = cache_dict.get("size_x", chunk_size)
	var size_z: int = cache_dict.get("size_z", chunk_size)
	var size_y: int = cache_dict.get("size_y", clamp(max_build_y, 6, 128))
	var cache_x: int = cache_dict.get("cache_x", size_x + 2)
	var cache_z: int = cache_dict.get("cache_z", size_z + 2)

	if cache.is_empty():
		return null

	var end_x = origin_x + size_x
	var end_z = origin_z + size_z

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	var local_seed = seed_value
	var local_enable_ao = enable_ao
	var local_ao_table = ao_table
	var local_top_colors = _top_colors
	var local_side_colors = _side_colors

	var size_y_local = size_y
	var cache_z_local = cache_z
	var cache_x_local = cache_x
	var origin_x_local = origin_x
	var origin_z_local = origin_z
	var sy_cz = size_y_local * cache_z_local

	var sqrt2 = sqrt(2.0)
	var horiz_table: Array = [
		sqrt2, 1.0, sqrt2,
		1.0, 0.0, 1.0,
		sqrt2, 1.0, sqrt2
	]

	var du_top = [-1, 1, 1, -1]
	var dv_top = [-1, -1, 1, 1]
	var cx_off_top = [0, 1, 1, 0]
	var cz_off_top = [0, 0, 1, 1]

	var du_bot = [-1, 1, 1, -1]
	var dv_bot = [1, 1, -1, -1]

	var shadow_cache: Dictionary = {}

	for x in range(origin_x, end_x):
		var lx = x - origin_x_local + 1
		var lx_sycz = lx * sy_cz
		var lx_p1_sycz = -1
		var lx_m1_sycz = -1
		if lx + 1 < cache_x_local:
			lx_p1_sycz = (lx + 1) * sy_cz
		if lx - 1 >= 0:
			lx_m1_sycz = (lx - 1) * sy_cz

		for z in range(origin_z, end_z):
			var lz = z - origin_z_local + 1
			var h = (x * 73856093) ^ (z * 19349663) ^ local_seed
			h = abs(h) % 1000
			var var_off = (float(h) / 1000.0 - 0.5) * 0.08
			var var_off_half = var_off * 0.5
			var var_off_side = var_off * 0.6

			for y in range(size_y_local):
				var ly = y
				var cache_idx = lx_sycz + ly * cache_z_local + lz
				if cache_idx < 0 or cache_idx >= cache.size():
					continue
				var block_type = cache[cache_idx]
				if block_type == -1:
					continue
				if block_type == BlockId.Type.AIR or block_type == BlockId.Type.TORCH or block_type == BlockId.Type.WATER:
					continue
				if block_type < 0 or block_type >= local_top_colors.size():
					continue
				var def_top = local_top_colors[block_type]
				var def_side = local_side_colors[block_type]
				var top_col: Color
				var side_col: Color
				if block_type == BlockId.Type.LOG or block_type == BlockId.Type.LEAVES:
					top_col = def_top + Color(var_off_half, var_off_half, var_off_half)
					side_col = def_side
				else:
					top_col = def_top + Color(var_off, var_off, var_off)
					side_col = def_side + Color(var_off_side, var_off_side, var_off_side)

				var n_top = -1
				var yp1_in_range = ly + 1 < size_y_local
				var y_plus = y + 1
				if yp1_in_range:
					var idx_top = lx_sycz + (ly + 1) * cache_z_local + lz
					if idx_top >= 0 and idx_top < cache.size():
						n_top = cache[idx_top]
				var top_visible = (n_top == -1 or n_top == BlockId.Type.AIR or n_top == BlockId.Type.TORCH or n_top == BlockId.Type.WATER)
				if top_visible:
					var v0 = Vector3(x, y + 1, z)
					var v1 = Vector3(x + 1, y + 1, z)
					var v2 = Vector3(x + 1, y + 1, z + 1)
					var v3 = Vector3(x, y + 1, z + 1)
					var ao_vals = [0, 0, 0, 0]
					var sh_vals = [1.0, 1.0, 1.0, 1.0]
					for i in range(4):
						var sx = x + du_top[i]
						var sz_ = z + dv_top[i]
						var s1 = false
						var s2 = false
						var cs = false
						if yp1_in_range and y_plus >= 0 and y_plus < size_y_local:
							var clx1 = sx - origin_x_local + 1
							var clz2 = sz_ - origin_z_local + 1
							if clx1 >= 0 and clx1 < cache_x_local:
								var idx1 = clx1 * sy_cz + y_plus * cache_z_local + lz
								if idx1 >= 0 and idx1 < cache.size():
									var vv = cache[idx1]
									if vv != -1 and vv != BlockId.Type.AIR and vv != BlockId.Type.TORCH and vv != BlockId.Type.WATER:
										s1 = true
							if clz2 >= 0 and clz2 < cache_z_local:
								var idx2 = lx_sycz + y_plus * cache_z_local + clz2
								if idx2 >= 0 and idx2 < cache.size():
									var vv2 = cache[idx2]
									if vv2 != -1 and vv2 != BlockId.Type.AIR and vv2 != BlockId.Type.TORCH and vv2 != BlockId.Type.WATER:
										s2 = true
							if clx1 >= 0 and clx1 < cache_x_local and clz2 >= 0 and clz2 < cache_z_local:
								var idxc = clx1 * sy_cz + y_plus * cache_z_local + clz2
								if idxc >= 0 and idxc < cache.size():
									var vvc = cache[idxc]
									if vvc != -1 and vvc != BlockId.Type.AIR and vvc != BlockId.Type.TORCH and vvc != BlockId.Type.WATER:
										cs = true
						var ao = 0
						if s1 and s2:
							ao = 3
						else:
							if s1: ao += 1
							if s2: ao += 1
							if cs: ao += 1
						ao_vals[i] = ao

						var vx = x + cx_off_top[i]
						var vz_ = z + cz_off_top[i]
						var skey = Vector3i(vx, y, vz_)
						var cached_sh = shadow_cache.get(skey, null)
						if cached_sh != null:
							sh_vals[i] = cached_sh
						else:
							var best_sh = 1.0
							for ox_idx in range(3):
								var ox = ox_idx - 1
								var wwx = vx + ox
								var clx_s = wwx - origin_x_local + 1
								if clx_s < 0 or clx_s >= cache_x_local:
									continue
								var clx_s_sycz = clx_s * sy_cz
								for oz_idx in range(3):
									if best_sh <= 0.721:
										break
									var oz = oz_idx - 1
									var horiz = horiz_table[ox_idx * 3 + oz_idx]
									var wwz = vz_ + oz
									var clz_s = wwz - origin_z_local + 1
									if clz_s < 0 or clz_s >= cache_z_local:
										continue
									var base_no_y = clx_s_sycz + clz_s
									for dy in range(2, 8):
										var wy2 = y + dy
										if wy2 >= 128:
											break
										if wy2 < 0 or wy2 >= size_y_local:
											continue
										var idx_s = base_no_y + wy2 * cache_z_local
										if idx_s < 0 or idx_s >= cache.size():
											continue
										var vvs = cache[idx_s]
										if vvs != -1 and vvs != BlockId.Type.AIR and vvs != BlockId.Type.TORCH and vvs != BlockId.Type.WATER:
											var vert = dy - 1
											var f = 0.72 + float(vert - 1) * 0.06 + horiz * 0.10
											if f > 0.97:
												f = 0.97
											if f < best_sh:
												best_sh = f
											break
								if best_sh <= 0.721:
									break
							shadow_cache[skey] = best_sh
							sh_vals[i] = best_sh
					var base_idx = vertices.size()
					vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
					normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0))
					for ci in range(4):
						var b = local_ao_table[ao_vals[ci]] if local_enable_ao else 1.0
						var sh = sh_vals[ci]
						colors.append(Color(top_col.r * b * sh, top_col.g * b * sh, top_col.b * b * sh, top_col.a))
					indices.append(base_idx+0); indices.append(base_idx+1); indices.append(base_idx+2)
					indices.append(base_idx+0); indices.append(base_idx+2); indices.append(base_idx+3)

				var n_bot = -1
				var ym1_in_range = ly - 1 >= 0
				var y_minus = y - 1
				if ym1_in_range:
					var idx_bot = lx_sycz + (ly - 1) * cache_z_local + lz
					if idx_bot >= 0 and idx_bot < cache.size():
						n_bot = cache[idx_bot]
				var bot_visible = (n_bot == -1 or n_bot == BlockId.Type.AIR or n_bot == BlockId.Type.TORCH or n_bot == BlockId.Type.WATER)
				if bot_visible and y > 0:
					var bcol = side_col * 0.92
					var ao2 = [0, 0, 0, 0]
					for i in range(4):
						var sx = x + du_bot[i]
						var sz_ = z + dv_bot[i]
						var s1 = false
						var s2 = false
						var cs = false
						if ym1_in_range and y_minus >= 0 and y_minus < size_y_local:
							var clx1 = sx - origin_x_local + 1
							var clz2 = sz_ - origin_z_local + 1
							if clx1 >= 0 and clx1 < cache_x_local:
								var idx1 = clx1 * sy_cz + y_minus * cache_z_local + lz
								if idx1 >= 0 and idx1 < cache.size():
									var vv = cache[idx1]
									if vv != -1 and vv != BlockId.Type.AIR and vv != BlockId.Type.TORCH and vv != BlockId.Type.WATER:
										s1 = true
							if clz2 >= 0 and clz2 < cache_z_local:
								var idx2 = lx_sycz + y_minus * cache_z_local + clz2
								if idx2 >= 0 and idx2 < cache.size():
									var vv2 = cache[idx2]
									if vv2 != -1 and vv2 != BlockId.Type.AIR and vv2 != BlockId.Type.TORCH and vv2 != BlockId.Type.WATER:
										s2 = true
							if clx1 >= 0 and clx1 < cache_x_local and clz2 >= 0 and clz2 < cache_z_local:
								var idxc = clx1 * sy_cz + y_minus * cache_z_local + clz2
								if idxc >= 0 and idxc < cache.size():
									var vvc = cache[idxc]
									if vvc != -1 and vvc != BlockId.Type.AIR and vvc != BlockId.Type.TORCH and vvc != BlockId.Type.WATER:
										cs = true
						var ao = 0
						if s1 and s2:
							ao = 3
						else:
							if s1: ao += 1
							if s2: ao += 1
							if cs: ao += 1
						ao2[i] = ao
					var base_idx2 = vertices.size()
					vertices.append(Vector3(x, y, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x, y, z))
					normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0))
					for ci in range(4):
						var b = local_ao_table[ao2[ci]] if local_enable_ao else 1.0
						colors.append(Color(bcol.r * b, bcol.g * b, bcol.b * b, bcol.a))
					indices.append(base_idx2+0); indices.append(base_idx2+1); indices.append(base_idx2+2)
					indices.append(base_idx2+0); indices.append(base_idx2+2); indices.append(base_idx2+3)

				var n_east = -1
				if lx_p1_sycz != -1:
					var idx_e = lx_p1_sycz + ly * cache_z_local + lz
					if idx_e >= 0 and idx_e < cache.size():
						n_east = cache[idx_e]
				if n_east == -1 or n_east == BlockId.Type.AIR or n_east == BlockId.Type.TORCH or n_east == BlockId.Type.WATER:
					var base_idx3 = vertices.size()
					vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z)); vertices.append(Vector3(x+1, y, z))
					normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0))
					for ci in range(4):
						colors.append(side_col)
					indices.append(base_idx3+0); indices.append(base_idx3+1); indices.append(base_idx3+2)
					indices.append(base_idx3+0); indices.append(base_idx3+2); indices.append(base_idx3+3)

				var n_west = -1
				if lx_m1_sycz != -1:
					var idx_w = lx_m1_sycz + ly * cache_z_local + lz
					if idx_w >= 0 and idx_w < cache.size():
						n_west = cache[idx_w]
				if n_west == -1 or n_west == BlockId.Type.AIR or n_west == BlockId.Type.TORCH or n_west == BlockId.Type.WATER:
					var base_idx4 = vertices.size()
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x, y+1, z)); vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0))
					for ci in range(4):
						colors.append(side_col)
					indices.append(base_idx4+0); indices.append(base_idx4+1); indices.append(base_idx4+2)
					indices.append(base_idx4+0); indices.append(base_idx4+2); indices.append(base_idx4+3)

				var n_south = -1
				if lz + 1 < cache_z_local:
					var idx_s = lx_sycz + ly * cache_z_local + (lz + 1)
					if idx_s >= 0 and idx_s < cache.size():
						n_south = cache[idx_s]
				if n_south == -1 or n_south == BlockId.Type.AIR or n_south == BlockId.Type.TORCH or n_south == BlockId.Type.WATER:
					var base_idx5 = vertices.size()
					vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1))
					for ci in range(4):
						colors.append(side_col)
					indices.append(base_idx5+0); indices.append(base_idx5+1); indices.append(base_idx5+2)
					indices.append(base_idx5+0); indices.append(base_idx5+2); indices.append(base_idx5+3)

				var n_north = -1
				if lz - 1 >= 0:
					var idx_n = lx_sycz + ly * cache_z_local + (lz - 1)
					if idx_n >= 0 and idx_n < cache.size():
						n_north = cache[idx_n]
				if n_north == -1 or n_north == BlockId.Type.AIR or n_north == BlockId.Type.TORCH or n_north == BlockId.Type.WATER:
					var base_idx6 = vertices.size()
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x+1, y+1, z)); vertices.append(Vector3(x, y+1, z))
					normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1))
					for ci in range(4):
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

func build_water_mesh_data_from_cache(cache_dict: Dictionary) -> Variant:
	var cache: PackedInt32Array = cache_dict.get("cache", PackedInt32Array())
	var origin_x: int = cache_dict.get("origin_x", 0)
	var origin_z: int = cache_dict.get("origin_z", 0)
	var size_x: int = cache_dict.get("size_x", chunk_size)
	var size_z: int = cache_dict.get("size_z", chunk_size)
	var size_y: int = cache_dict.get("size_y", clamp(max_build_y, 6, 128))
	var cache_x: int = cache_dict.get("cache_x", size_x + 2)
	var cache_z: int = cache_dict.get("cache_z", size_z + 2)

	if cache.is_empty():
		return null

	var end_x = origin_x + size_x
	var end_z = origin_z + size_z

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var tangents := PackedFloat32Array()
	var indices := PackedInt32Array()

	const WATER_SURFACE_HEIGHT: float = 0.75
	const WATER_UV_SCALE: float = 0.12

	var sy_cz = size_y * cache_z
	for x in range(origin_x, end_x):
		var lx = x - origin_x + 1
		var lx_sycz = lx * sy_cz
		for z in range(origin_z, end_z):
			var lz = z - origin_z + 1
			for y in range(size_y):
				var ly = y
				var cache_idx = lx_sycz + ly * cache_z + lz
				if cache_idx < 0 or cache_idx >= cache.size():
					continue
				if cache[cache_idx] != BlockId.Type.WATER:
					continue

				var n_top = -1
				if ly + 1 < size_y:
					n_top = cache[lx_sycz + (ly + 1) * cache_z + lz]
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
					n_bot = cache[lx_sycz + (ly - 1) * cache_z + lz]
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
					vertices.append(Vector3(x, yt, z+1)); vertices.append(Vector3(x+1, yt, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x, y, z+1))
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
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x+1, yt, z)); vertices.append(Vector3(x, yt, z))
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
