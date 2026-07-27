extends Node3D

# Wildes - 200x200 block world generator + editable voxel world
# Now supports mining/placing, layered terrain (grass -> dirt -> stone), and dynamic chunk rebuilding.
# Still grouped chunk geometry for responsiveness (100 chunks, shared material).

@export var world_size: int = 200
@export var chunk_size: int = 20
@export var water_level: int = 5
@export var max_height: int = 20
@export var build_extra: int = 16 # how high you can build above max_height
@export var seed_value: int = 1337
@export var tree_density: float = 0.012
@export var show_water: bool = true
@export_group("Ambient Occlusion & Shadows")
@export var enable_ao: bool = true
@export var ao_darkness: float = 0.22 # per-level darkening (0.18-0.28)
@export var enable_shadows: bool = true
@export var shadow_cast_distance: float = 220.0

enum BlockType { GRASS, SAND, STONE, DIRT, LOG, LEAVES, TORCH }

const COL_GRASS_TOP: Color = Color(0.52, 0.67, 0.40)
const COL_GRASS_SIDE: Color = Color(0.42, 0.36, 0.28)
const COL_DIRT: Color = Color(0.46, 0.38, 0.30)
const COL_SAND: Color = Color(0.86, 0.80, 0.62)
const COL_STONE: Color = Color(0.66, 0.66, 0.63)
const COL_LOG: Color = Color(0.38, 0.29, 0.21)
const COL_LOG_TOP: Color = Color(0.42, 0.33, 0.24)
const COL_LEAVES: Color = Color(0.36, 0.52, 0.30)
const COL_LEAVES_DARK: Color = Color(0.32, 0.46, 0.27)
const COL_TORCH: Color = Color(0.78, 0.62, 0.42)
const COL_TORCH_FLAME: Color = Color(1.0, 0.92, 0.68) # less orange, warm white

var noise_hills: FastNoiseLite
var noise_detail: FastNoiseLite
var noise_biome: FastNoiseLite
var rng: RandomNumberGenerator

var height_map: Array = []
var type_map: Array = []

# Initial trees
var tree_blocks: Array = [] # {pos:Vector3i, type:int}
# freeze fix: avoid String formatting, use Vector3i dict only
var tree_block_fast: Dictionary = {} # Vector3i -> type fast, avoids string fmt

# Editable overrides with per-cell revision for anti-stale rebuilds
var placed_blocks: Dictionary = {} # Vector3i -> BlockType
var removed_blocks: Dictionary = {} # Vector3i -> true (air)
var cell_revisions: Dictionary = {} # Vector3i -> int revision

# cache highest solid top per xz column, invalidated on edits
var _highest_cache: Dictionary = {} # Vector2i(x,z) -> int highest y solid, -1 if none

var chunk_instances: Dictionary = {} # "cx_cz" -> MeshInstance3D
var dirty_chunks: Dictionary = {} # "cx_cz" -> Vector2i(cx,cz)
var _rebuild_scheduled: bool = false

var terrain_shader: Shader
var water_shader: Shader
var terrain_material: ShaderMaterial

var max_build_y: int = 0
var sun_shadow_map: Array = [] # [x][z] -> float 0.55 shadowed, 1.0 lit

# --- Torch system - per-light OmniLight3D creation ---
# Each torch spawns its own cheap visual + OmniLight. No voxel BFS, lighting via shadows.
const TORCH_OMNI_RANGE: float = 9.0
var _torches: Dictionary = {}
var torch_attachments: Dictionary = {}
var torch_container: Node3D
var torch_instances: Dictionary = {} # Vector3i -> Node3D (visual + light)
var torch_light_nodes: Dictionary = {} # Vector3i -> OmniLight3D (per torch)
var torch_base_material: StandardMaterial3D
var torch_flame_material: StandardMaterial3D
var torch_stem_mesh: BoxMesh
var torch_flame_mesh: BoxMesh
var _shadow_update_timer: float = 0.5
const MAX_SHADOW_TORCHES: int = 4 # of all torches, closest 4 cast soft shadows for quality
const TORCH_SHADOW_UPDATE_INTERVAL: float = 0.6

signal block_changed(pos: Vector3i, old_type, new_type, revision: int)

func _ready():
	print("[Wildes] Generating %dx%d world (seed %d) ..." % [world_size, world_size, seed_value])
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	max_build_y = max_height + build_extra + 8 # room for trees + building
	_setup_noises()
	_generate_height_and_type()
	_generate_tree_blocks()
	# Static sun shadow map disabled per feedback - using only AO + real-time drop shadows
	# _generate_sun_shadow_map()
	# Keep sun_shadow_map empty to avoid accidental use
	sun_shadow_map.clear()
	_prepare_materials()
	_setup_torch_system()
	_generate_chunks()
	_create_water_plane()
	_create_bounds_floor()
	print("[Wildes] World ready: %d chunks, %d tree blocks" % [chunk_instances.size(), tree_blocks.size()])

func _generate_sun_shadow_map():
	# Precompute large-scale terrain self-shadowing from sun direction (NE high)
	# Sun from NE (hx ~0.809, hz~-0.587) casting shadows to SW, slope 0.34 up towards sun
	sun_shadow_map.resize(world_size)
	for x in range(world_size):
		sun_shadow_map[x] = []
		sun_shadow_map[x].resize(world_size)
		# init lit
		for z in range(world_size):
			sun_shadow_map[x][z] = 1.0
	# tree max height per column
	var tree_max: Dictionary = {}
	for tb in tree_blocks:
		var p = tb["pos"] as Vector3i
		var key = Vector2i(p.x, p.z)
		if tree_max.has(key):
			if p.y > tree_max[key]:
				tree_max[key] = p.y
		else:
			tree_max[key] = p.y
	var sun_hx = 0.809
	var sun_hz = -0.587
	var slope = 0.34
	var max_dist = 28
	for x in range(world_size):
		for z in range(world_size):
			var y0 = height_map[x][z]
			var tk = Vector2i(x, z)
			if tree_max.has(tk):
				y0 = max(y0, tree_max[tk])
			var ray_y = float(y0) + 1.0
			var shadowed = false
			for s in range(1, max_dist+1):
				var sx = int(round(x + sun_hx * float(s)))
				var sz = int(round(z + sun_hz * float(s)))
				if sx <0 or sx >= world_size or sz <0 or sz >= world_size:
					continue
				var bh = height_map[sx][sz]
				var bkey = Vector2i(sx, sz)
				if tree_max.has(bkey):
					bh = max(bh, tree_max[bkey])
				var r_y = ray_y + float(s) * slope
				if float(bh) >= r_y - 0.4:
					shadowed = true
					break
			sun_shadow_map[x][z] = 0.52 if shadowed else 1.0

var noise_forest: FastNoiseLite
var noise_ridges: FastNoiseLite

func _setup_noises():
	noise_hills = FastNoiseLite.new()
	noise_hills.seed = seed_value
	noise_hills.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_hills.frequency = 0.012
	noise_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise_hills.fractal_octaves = 4
	noise_hills.fractal_lacunarity = 2.0
	noise_hills.fractal_gain = 0.45
	noise_detail = FastNoiseLite.new()
	noise_detail.seed = seed_value + 101
	noise_detail.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_detail.frequency = 0.045
	noise_detail.fractal_octaves = 2
	noise_detail.fractal_gain = 0.5
	noise_biome = FastNoiseLite.new()
	noise_biome.seed = seed_value + 202
	noise_biome.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_biome.frequency = 0.006
	noise_biome.fractal_octaves = 3
	noise_forest = FastNoiseLite.new()
	noise_forest.seed = seed_value + 303
	noise_forest.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_forest.frequency = 0.022
	noise_forest.fractal_octaves = 3
	noise_ridges = FastNoiseLite.new()
	noise_ridges.seed = seed_value + 404
	noise_ridges.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_ridges.frequency = 0.018
	noise_ridges.fractal_octaves = 2

func _generate_height_and_type():
	height_map.resize(world_size)
	type_map.resize(world_size)
	for x in range(world_size):
		height_map[x] = []
		height_map[x].resize(world_size)
		type_map[x] = []
		type_map[x].resize(world_size)
	
	var meadow_center = Vector2(world_size*0.5, world_size*0.5)
	var meadow_radius = 24.0
	var meadow_target_h = 9.5
	
	for x in range(world_size):
		for z in range(world_size):
			var n_hills = noise_hills.get_noise_2d(float(x), float(z))
			var n_detail = noise_detail.get_noise_2d(float(x), float(z)) * 0.6
			var n_biome = noise_biome.get_noise_2d(float(x)*0.5, float(z)*0.5) * 0.8
			var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
			var ridge = 1.0 - abs(n_ridge_raw) # 0..1, 1 = ridge line
			var h = 9.0 + n_hills * 6.5 + n_detail * 1.8 + n_biome * 2.2
			# stone ridges - lift where ridge powerful
			if ridge > 0.72:
				h += (ridge - 0.72) * 8.0
			var cx = (float(x) - world_size*0.5) / world_size
			var cz = (float(z) - world_size*0.5) / world_size
			var dist_edge = sqrt(cx*cx + cz*cz)
			h -= dist_edge * 2.2
			
			# open meadow around spawn - flatten and gentle
			var d_center = Vector2(x,z).distance_to(meadow_center)
			if d_center < meadow_radius:
				var t = 1.0 - d_center / meadow_radius
				# lerp towards meadow_target_h
				h = lerp(h, meadow_target_h, t * 0.75)
			
			var ih = int(round(h))
			ih = clamp(ih, 2, max_height)
			height_map[x][z] = ih
	
	# Types: meadow, lowland sand, ridges stone, rest grass with overlooks
	for x in range(world_size):
		for z in range(world_size):
			var h = height_map[x][z]
			var max_diff = 0
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >=0 and nx < world_size and nz >=0 and nz < world_size:
					var dh = abs(height_map[nx][nz] - h)
					if dh > max_diff:
						max_diff = dh
			
			var n_forest = noise_forest.get_noise_2d(float(x), float(z))
			var n_ridge_raw = noise_ridges.get_noise_2d(float(x), float(z))
			var ridge = 1.0 - abs(n_ridge_raw)
			var d_center = Vector2(x,z).distance_to(meadow_center)
			
			var t: int
			# meadow override near spawn
			if d_center < meadow_radius - 2.0:
				t = BlockType.GRASS
			elif h <= water_level + 1:
				t = BlockType.SAND
			elif h <= water_level + 2:
				# sandy lowlands - wider basins where biome low
				var lowland = noise_biome.get_noise_2d(float(x)*0.3, float(z)*0.3)
				if lowland < 0.0 or d_center < meadow_radius + 8.0:
					# transition sand->grass, but keep lowlands sandy
					if h <= water_level + 2 and lowland < -0.15:
						t = BlockType.SAND
					else:
						t = BlockType.GRASS if lowland > -0.1 else BlockType.SAND
				else:
					t = BlockType.SAND
			else:
				# stone ridges - guaranteed exposed stone
				if ridge > 0.78 and h >= 11:
					t = BlockType.STONE
				elif ridge > 0.70 and h >= 13 and n_forest < 0.2:
					t = BlockType.STONE
				elif h >= 15:
					var stone_chance = (h - 14) * 0.26
					if rng.randf() < stone_chance or max_diff >= 3:
						t = BlockType.STONE
					else:
						t = BlockType.GRASS
				elif max_diff >= 3:
					t = BlockType.STONE
				elif max_diff == 2 and rng.randf() < 0.5:
					t = BlockType.STONE
				else:
					t = BlockType.GRASS
			type_map[x][z] = t
	
	# occasional clear overlooks - flat stone/grass plateaus with view, no trees
	for i in range(12):
		var ox = rng.randi_range(30, world_size-30)
		var oz = rng.randi_range(30, world_size-30)
		var h = height_map[ox][oz]
		if h < 12:
			continue
		# must be relatively flat peak
		var flat = true
		for dx in range(-2,3):
			for dz in range(-2,3):
				var nx = ox+dx
				var nz = oz+dz
				if nx<0 or nx>=world_size or nz<0 or nz>=world_size:
					continue
				if abs(height_map[nx][nz] - h) > 1:
					flat = false
		if not flat:
			continue
		# carve overlook plateau radius 3
		for dx in range(-3,4):
			for dz in range(-3,4):
				var nx = ox+dx
				var nz = oz+dz
				if nx<0 or nx>=world_size or nz<0 or nz>=world_size:
					continue
				if Vector2(dx,dz).length() > 3.2:
					continue
				height_map[nx][nz] = h
				# top stone for overlook edge, grass inside
				if Vector2(dx,dz).length() > 2.0:
					type_map[nx][nz] = BlockType.STONE
				else:
					type_map[nx][nz] = BlockType.GRASS
	
	# guarantee wood and stone (so player never spawns without resources)
	var stone_count = 0
	var grass_count = 0
	for x in range(world_size):
		for z in range(world_size):
			if type_map[x][z] == BlockType.STONE:
				stone_count +=1
			if type_map[x][z] == BlockType.GRASS:
				grass_count +=1
	if stone_count < 250:
		# convert highest 300 cells to stone ridges
		var cells = []
		for x in range(world_size):
			for z in range(world_size):
				if type_map[x][z] != BlockType.STONE:
					cells.append(Vector3i(x, height_map[x][z], z))
		cells.sort_custom(func(a,b): return a.y > b.y)
		for k in range(min(300, cells.size())):
			var c = cells[k]
			type_map[c.x][c.z] = BlockType.STONE

func _generate_tree_blocks():
	tree_blocks.clear()
	tree_block_fast.clear()
	_highest_cache.clear()
	var positions: Array = []
	var meadow_center = Vector2(world_size*0.5, world_size*0.5)
	var meadow_radius = 24.0
	
	for x in range(4, world_size-4):
		for z in range(4, world_size-4):
			if type_map[x][z] != BlockType.GRASS:
				continue
			var h = height_map[x][z]
			if h <= water_level + 2:
				continue
			var d_center = Vector2(x,z).distance_to(meadow_center)
			# open meadow around spawn - no trees
			if d_center < meadow_radius - 2.0:
				continue
			
			var max_diff = 0
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx >=0 and nx < world_size and nz >=0 and nz < world_size:
					max_diff = max(max_diff, abs(height_map[nx][nz] - h))
			if max_diff > 1:
				continue
			
			# wooded rises - higher + forest noise = denser woods
			var n_forest = noise_forest.get_noise_2d(float(x), float(z))
			var forest_factor = clamp((n_forest + 0.2) * 1.2, 0.0, 1.2)
			var height_factor = clamp((h - 9.0) / 6.0, 0.2, 1.0) # rises more wooded
			var effective_density = tree_density * (0.6 + forest_factor * 0.9 + height_factor * 0.5)
			
			# overlooks should stay clear
			if h >= 13 and max_diff == 0 and rng.randf() < 0.15:
				continue # leave overlook clear
			
			if rng.randf() > effective_density:
				continue
			
			var too_close = false
			for p in positions:
				if abs(p.x - x) < 4 and abs(p.y - z) < 4:
					if Vector2i(x,z).distance_to(p) < 4.5:
						too_close = true
						break
			if too_close:
				continue
			positions.append(Vector2i(x,z))
			_add_tree_at(x, h, z)
	
	# guarantee wood - at least 60 trees so wandering always finds wood
	if positions.size() < 60:
		var tries = 0
		while positions.size() < 60 and tries < 5000:
			tries += 1
			var x = rng.randi_range(10, world_size-10)
			var z = rng.randi_range(10, world_size-10)
			if type_map[x][z] != BlockType.GRASS:
				continue
			if Vector2(x,z).distance_to(meadow_center) < meadow_radius:
				continue
			var h = height_map[x][z]
			if h <= water_level + 2:
				continue
			var too_close = false
			for p in positions:
				if Vector2i(x,z).distance_to(p) < 4.5:
					too_close = true
					break
			if too_close:
				continue
			positions.append(Vector2i(x,z))
			_add_tree_at(x, h, z)

func _add_tree_at(x: int, ground_h: int, z: int):
	var trunk_h = 3 + (rng.randi() % 2)
	var trunk_top = ground_h + trunk_h
	for y in range(ground_h + 1, ground_h + 1 + trunk_h):
		_add_tree_block(Vector3i(x, y, z), BlockType.LOG)
	var leaves_base_y = trunk_top + 1
	for dx in range(-1,2):
		for dz in range(-1,2):
			var nx = x + dx
			var nz = z + dz
			if nx <0 or nx >= world_size or nz <0 or nz >= world_size:
				continue
			_add_tree_block(Vector3i(nx, leaves_base_y, nz), BlockType.LEAVES)
	for dx in range(-1,2):
		for dz in range(-1,2):
			if abs(dx) == 1 and abs(dz) == 1 and rng.randf() < 0.5:
				continue
			var nx = x + dx
			var nz = z + dz
			if nx <0 or nx >= world_size or nz <0 or nz >= world_size:
				continue
			_add_tree_block(Vector3i(nx, leaves_base_y + 1, nz), BlockType.LEAVES)
	_add_tree_block(Vector3i(x, leaves_base_y + 2, z), BlockType.LEAVES)

func _add_tree_block(p: Vector3i, t: int):
	# use Vector3i dict only, no String formatting per frame
	if tree_block_fast.has(p):
		return
	tree_block_fast[p] = t
	tree_blocks.append({"pos": p, "type": t})

func _prepare_materials():
	terrain_shader = load("res://shaders/terrain.gdshader")
	if terrain_shader == null:
		push_error("Failed to load terrain.gdshader")
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = terrain_shader
	if terrain_material:
		terrain_material.set_shader_parameter("world_size", float(world_size))
		terrain_material.set_shader_parameter("haze_color", Vector3(0.75, 0.87, 0.94))
	water_shader = load("res://shaders/water.gdshader")

func _setup_torch_system():
	torch_container = Node3D.new()
	torch_container.name = "TorchContainer"
	add_child(torch_container)
	
	torch_base_material = StandardMaterial3D.new()
	torch_base_material.albedo_color = COL_TORCH
	torch_base_material.roughness = 0.9
	torch_base_material.emission_enabled = false
	
	torch_flame_material = StandardMaterial3D.new()
	torch_flame_material.albedo_color = COL_TORCH_FLAME
	torch_flame_material.emission_enabled = true
	torch_flame_material.emission = COL_TORCH_FLAME
	torch_flame_material.emission_energy_multiplier = 1.2
	torch_flame_material.roughness = 0.6
	
	# Shared meshes for cheap visuals
	torch_stem_mesh = BoxMesh.new()
	torch_stem_mesh.size = Vector3(0.08, 0.45, 0.08)
	torch_flame_mesh = BoxMesh.new()
	torch_flame_mesh.size = Vector3(0.14, 0.14, 0.14)
	
	print("[Wildes] Torch system ready - per-light Omni creation")

func _process(_delta):
	if dirty_chunks.size() > 0:
		_flush_dirty_chunks()
	
	_shadow_update_timer -= _delta
	if _shadow_update_timer <= 0.0:
		_shadow_update_timer = TORCH_SHADOW_UPDATE_INTERVAL
		_update_torch_shadows_per_light()

func _update_torch_shadows_per_light():
	# Per spec: each OmniLight should have shadows enabled with DUAL_PARABOLOID and soft settings
	if _torches.is_empty():
		return
	# In headless tests, skip enabling shadows to avoid render device allocation hangs
	if DisplayServer.get_name() == "headless":
		return
	for tpos in torch_light_nodes.keys():
		var light = torch_light_nodes[tpos] as OmniLight3D
		if not light or not is_instance_valid(light):
			continue
		# Ensure spec values are applied even if previously culled
		light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light.shadow_enabled = true
		light.shadow_reverse_cull_face = false
		light.shadow_bias = 0.03
		light.shadow_normal_bias = 0.2
		light.shadow_opacity = 0.5
		light.shadow_blur = 1.0

func _queue_chunk_rebuild(cx: int, cz: int):
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	if cx <0 or cz <0 or cx >= chunks_x or cz >= chunks_z:
		return
	var key = "%d_%d" % [cx, cz]
	dirty_chunks[key] = Vector2i(cx, cz)
	# rebuild will happen next _process to avoid hitch during mine

func _flush_dirty_chunks():
	# Rebuild up to 2 chunks per frame to keep responsive, no light job now
	var max_per_frame = 2
	var rebuilt = 0
	var keys = dirty_chunks.keys()
	for k in keys:
		if rebuilt >= max_per_frame:
			break
		var v = dirty_chunks[k] as Vector2i
		dirty_chunks.erase(k)
		_rebuild_chunk_immediate(v.x, v.y)
		rebuilt += 1

func _generate_chunks():
	chunk_instances.clear()
	dirty_chunks.clear()
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	for cx in range(chunks_x):
		for cz in range(chunks_z):
			_rebuild_chunk_immediate(cx, cz)

# ---------------- Voxel API ----------------

func _base_terrain_type_at(x: int, y: int, z: int):
	# returns BlockType or null if no base terrain at that y
	if x <0 or x >= world_size or z <0 or z >= world_size:
		return null
	var h = height_map[x][z]
	if y > h or y < 0:
		return null
	var top_t = type_map[x][z]
	if top_t == BlockType.SAND:
		return BlockType.SAND
	if top_t == BlockType.STONE:
		return BlockType.STONE
	if top_t == BlockType.GRASS:
		if y == h:
			return BlockType.GRASS
		elif y >= h - 2:
			return BlockType.DIRT
		else:
			return BlockType.STONE
	if top_t == BlockType.DIRT:
		return BlockType.DIRT
	return top_t

func get_block_at(p: Vector3i):
	if p.y < 0:
		return BlockType.STONE
	if p.x < 0 or p.x >= world_size or p.z < 0 or p.z >= world_size or p.y >= max_build_y:
		return null
	if placed_blocks.has(p):
		return placed_blocks[p]
	if removed_blocks.has(p):
		return null
	# Vector3i dict only, no String formatting (freeze fix)
	if tree_block_fast.has(p):
		return tree_block_fast[p]
	return _base_terrain_type_at(p.x, p.y, p.z)

# --- Block queries for torch system ---
func is_solid(p: Vector3i) -> bool:
	# Torch is not solid for physics / AO / collision, but is occupado for placement logic elsewhere
	var bt = get_block_at(p)
	if bt == null:
		return false
	if bt == BlockType.TORCH:
		return false
	return true

func is_occupied(p: Vector3i) -> bool:
	# Any block including torch occupies the cell for placement blocking and raycast
	return get_block_at(p) != null

func is_opaque(p: Vector3i) -> bool:
	# For torch light propagation - blocks that block light
	var bt = get_block_at(p)
	if bt == null:
		return false
	if bt == BlockType.TORCH:
		return false
	# Leaves could be semi-transparent but for simplicity treat as opaque to satisfy "blocked by blocks"
	return true

func is_raycast_solid(p: Vector3i) -> bool:
	# For selection raycast: torch is targetable
	return get_block_at(p) != null

func is_world_edge(p: Vector3i) -> bool:
	# reject edits at world border to avoid holes / physics escapes
	if p.x <= 0 or p.x >= world_size -1:
		return true
	if p.z <= 0 or p.z >= world_size -1:
		return true
	return false

func get_revision(p: Vector3i) -> int:
	return cell_revisions.get(p, 0)

func _increment_revision(p: Vector3i) -> int:
	var rev = cell_revisions.get(p, 0) + 1
	cell_revisions[p] = rev
	return rev

func is_breakable(p: Vector3i) -> bool:
	if p.y < 0:
		return false
	if is_world_edge(p):
		return false
	# breakable includes torch (even though not solid)
	return get_block_at(p) != null

# --- highest cache for freeze fix ---
func _invalidate_highest_cache(x: int, z: int):
	_highest_cache.erase(Vector2i(x, z))

func get_highest_solid_y(x: int, z: int) -> int:
	# cached top y lookup, Vector3i dict only, no String formatting (freeze fix)
	# Torch ignored for ground detection
	if x < 0 or x >= world_size or z < 0 or z >= world_size:
		return -1
	var key = Vector2i(x, z)
	if _highest_cache.has(key):
		return _highest_cache[key]
	for y in range(max_build_y - 1, -1, -1):
		var p = Vector3i(x, y, z)
		var bt = get_block_at(p)
		if bt != null and bt != BlockType.TORCH:
			_highest_cache[key] = y
			return y
	_highest_cache[key] = -1
	return -1

func get_highest_top(x: int, z: int) -> float:
	var y = get_highest_solid_y(x, z)
	if y == -1:
		return -9999.0
	return float(y) + 1.0

func try_mine_block(p: Vector3i):
	if is_world_edge(p):
		return null
	if not is_breakable(p):
		return null
	var old_type = get_block_at(p)
	if old_type == null:
		return null
	if placed_blocks.has(p):
		placed_blocks.erase(p)
	else:
		removed_blocks[p] = true
		if tree_block_fast.has(p):
			tree_block_fast.erase(p)
	_invalidate_highest_cache(p.x, p.z)
	
	var rev = _increment_revision(p)
	_rebuild_chunks_affected_by(p)
	
	if old_type == BlockType.TORCH:
		_torches.erase(p)
		torch_attachments.erase(p)
		_remove_torch_visual(p)
	
	block_changed.emit(p, old_type, null, rev)
	return {"type": old_type, "revision": rev}

func try_place_block(p: Vector3i, block_type: int, attach_dir: Vector3i = Vector3i.ZERO) -> bool:
	if p.y < 0 or p.y >= max_build_y:
		return false
	if p.x <0 or p.x >= world_size or p.z <0 or p.z >= world_size:
		return false
	if is_world_edge(p):
		return false
	if is_occupied(p):
		return false
	# Torch placement rule: require adjacent opaque block for support
	if block_type == BlockType.TORCH:
		var has_support = false
		for d in [Vector3i.UP, Vector3i.DOWN, Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,0,1), Vector3i(0,0,-1)]:
			if is_opaque(p + d) or is_solid(p + d):
				# also check if support is any solid terrain (including below)
				has_support = true
				break
		# allow placement on ground if y==0? but we already check adjacency, for floating torch we still require support
		if not has_support:
			# fallback: allow if directly on top of solid below (common case)
			if not is_opaque(p + Vector3i.DOWN):
				return false
	# commit placement
	if removed_blocks.has(p):
		removed_blocks.erase(p)
	placed_blocks[p] = block_type
	_invalidate_highest_cache(p.x, p.z)
	
	var rev = _increment_revision(p)
	
	if block_type == BlockType.TORCH:
		_torches[p] = true
		torch_attachments[p] = attach_dir
		_spawn_torch_visual(p, attach_dir)
		# Cheap: no terrain rebuild at all for torch (visual only)
	else:
		_rebuild_chunks_affected_by(p)
	
	block_changed.emit(p, null, block_type, rev)
	return true

func try_place_torch(p: Vector3i, attach_dir: Vector3i) -> bool:
	return try_place_block(p, BlockType.TORCH, attach_dir)

func _rebuild_chunks_affected_by(p: Vector3i):
	# Optimized: queue instead of immediate to spread hitch (was causing 119ms spike)
	var cx = int(floor(float(p.x) / float(chunk_size)))
	var cz = int(floor(float(p.z) / float(chunk_size)))
	_queue_chunk_rebuild(cx, cz)
	# neighbor chunks if on border - also queued
	if p.x % chunk_size == 0:
		_queue_chunk_rebuild(cx-1, cz)
	if (p.x+1) % chunk_size == 0:
		_queue_chunk_rebuild(cx+1, cz)
	if p.z % chunk_size == 0:
		_queue_chunk_rebuild(cx, cz-1)
	if (p.z+1) % chunk_size == 0:
		_queue_chunk_rebuild(cx, cz+1)

func _rebuild_chunk(cx: int, cz: int):
	_queue_chunk_rebuild(cx, cz)

func _rebuild_chunk_immediate(cx: int, cz: int):
	var chunks_x = int(ceil(float(world_size) / float(chunk_size)))
	var chunks_z = int(ceil(float(world_size) / float(chunk_size)))
	if cx <0 or cz <0 or cx >= chunks_x or cz >= chunks_z:
		return
	var origin_x = cx * chunk_size
	var origin_z = cz * chunk_size
	var mesh = _build_chunk_mesh_generic(origin_x, origin_z)
	var key = "%d_%d" % [cx, cz]
	if chunk_instances.has(key):
		var mi: MeshInstance3D = chunk_instances[key]
		if mesh == null:
			mi.mesh = null
		else:
			mi.mesh = mesh
	else:
		var mi = MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = terrain_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.name = "Chunk_%d_%d" % [cx, cz]
		add_child(mi)
		chunk_instances[key] = mi

# ---------------- Torch lighting propagation with occlusion (optimized) ----------------
# Torch lighting BFS removed - torches are cheap visual data only, lighting via OmniLight shadows
func get_torch_light_at(_p: Vector3i) -> int:
	return 0

# ---------------- Torch visuals - per-light Omni creation (cheap meshes) ----------------
func _spawn_torch_visual(pos: Vector3i, attach_dir: Vector3i):
	if torch_container == null:
		return
	_remove_torch_visual(pos)
	var root = Node3D.new()
	root.name = "Torch_%d_%d_%d" % [pos.x, pos.y, pos.z]
	var base_pos = Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5)
	if attach_dir != Vector3i.ZERO:
		var off = Vector3(attach_dir.x, attach_dir.y, attach_dir.z) * 0.32
		base_pos += off
		if attach_dir == Vector3i.DOWN:
			base_pos.y = pos.y + 0.15
	root.position = base_pos
	torch_container.add_child(root)
	
	# Stem - shared mesh
	var stem = MeshInstance3D.new()
	stem.mesh = torch_stem_mesh
	stem.position = Vector3(0, 0.05, 0)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stem.material_override = torch_base_material
	root.add_child(stem)
	
	# Flame - shared mesh
	var flame = MeshInstance3D.new()
	flame.mesh = torch_flame_mesh
	flame.position = Vector3(0, 0.38, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.material_override = torch_flame_material
	root.add_child(flame)
	
	# Per-torch OmniLight - reimplemented per request, shadows enabled as spec
	var light = OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = Color(1.0, 0.96, 0.88)
	light.light_energy = 0.72
	light.omni_range = TORCH_OMNI_RANGE
	light.omni_attenuation = 0.75
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.shadow_enabled = true
	light.shadow_reverse_cull_face = false
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 0.2
	light.shadow_opacity = 0.5
	light.shadow_blur = 1.0
	light.position = Vector3(0, 0.32, 0)
	root.add_child(light)
	
	torch_instances[pos] = root
	torch_light_nodes[pos] = light

func _remove_torch_visual(pos: Vector3i):
	if torch_instances.has(pos):
		var n = torch_instances[pos] as Node3D
		if n and is_instance_valid(n):
			n.queue_free()
		torch_instances.erase(pos)
	torch_light_nodes.erase(pos)
	torch_attachments.erase(pos)

func _build_chunk_mesh_generic(origin_x: int, origin_z: int) -> ArrayMesh:
	var end_x = min(origin_x + chunk_size, world_size)
	var end_z = min(origin_z + chunk_size, world_size)
	var size_x = chunk_size
	var size_z = chunk_size
	
	var local_max_y = 0
	for x in range(origin_x, end_x):
		for z in range(origin_z, end_z):
			var h = height_map[x][z]
			if h > local_max_y:
				local_max_y = h
	var size_y = clamp(local_max_y + 12, 6, max_build_y)
	
	var cache_x = size_x + 2
	var cache_z = size_z + 2
	var cache = []
	var total_cache = cache_x * size_y * cache_z
	cache.resize(total_cache)
	for lx in range(cache_x):
		for lz in range(cache_z):
			for ly in range(size_y):
				var wx = origin_x + lx -1
				var wz = origin_z + lz -1
				var wy = ly
				var v = get_block_at(Vector3i(wx, wy, wz))
				var idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				if v == null:
					cache[idx] = -1
				else:
					cache[idx] = v
	var ao_table = [1.0, 0.86, 0.72, 0.58]

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	
	var get_variation = func(x: int, z: int) -> float:
		var h = (x * 73856093) ^ (z * 19349663) ^ seed_value
		h = abs(h) % 1000
		return (float(h) / 1000.0 - 0.5) * 0.08
	
	var get_top_color = func(t: int, var_off: float) -> Color:
		match t:
			BlockType.GRASS: return Color(COL_GRASS_TOP.r + var_off, COL_GRASS_TOP.g + var_off, COL_GRASS_TOP.b + var_off)
			BlockType.SAND: return Color(COL_SAND.r + var_off, COL_SAND.g + var_off, COL_SAND.b + var_off*0.8)
			BlockType.STONE: return Color(COL_STONE.r + var_off, COL_STONE.g + var_off, COL_STONE.b + var_off)
			BlockType.DIRT: return Color(COL_DIRT.r + var_off, COL_DIRT.g + var_off, COL_DIRT.b + var_off)
			BlockType.LOG: return COL_LOG
			BlockType.LEAVES: return COL_LEAVES
			_: return Color(1,0,1)
	var get_side_color = func(t: int, var_off: float) -> Color:
		match t:
			BlockType.GRASS: return Color(COL_GRASS_SIDE.r + var_off*0.6, COL_GRASS_SIDE.g + var_off*0.6, COL_GRASS_SIDE.b + var_off*0.6)
			BlockType.SAND:
				var c = get_top_color.call(t, var_off)
				return Color(c.r * 0.94, c.g * 0.94, c.b * 0.94)
			BlockType.STONE:
				var c2 = get_top_color.call(t, var_off)
				return Color(c2.r * 0.92, c2.g * 0.92, c2.b * 0.92)
			BlockType.DIRT:
				var c3 = get_top_color.call(t, var_off)
				return Color(c3.r * 0.93, c3.g * 0.93, c3.b * 0.93)
			BlockType.LOG: return Color(COL_LOG.r * 0.95, COL_LOG.g * 0.95, COL_LOG.b * 0.95)
			BlockType.LEAVES: return Color(COL_LEAVES_DARK.r + var_off*0.5, COL_LEAVES_DARK.g + var_off*0.5, COL_LEAVES_DARK.b + var_off*0.5)
			_: return Color(1,0,1)

	for x in range(origin_x, end_x):
		var lx = x - origin_x + 1
		for z in range(origin_z, end_z):
			var lz = z - origin_z + 1
			var var_off = get_variation.call(x, z)
			for y in range(size_y):
				var ly = y
				var cache_idx = (lx * size_y * cache_z) + (ly * cache_z) + lz
				var block_type = cache[cache_idx]
				if block_type == -1:
					continue
				if block_type == BlockType.TORCH:
					continue
				var top_col = get_top_color.call(block_type, var_off if block_type != BlockType.LOG and block_type != BlockType.LEAVES else var_off*0.5)
				var side_col = get_side_color.call(block_type, var_off if block_type != BlockType.LOG and block_type != BlockType.LEAVES else var_off*0.5)

				# +Y top
				var n_top = -1
				if ly+1 < size_y:
					n_top = cache[(lx * size_y * cache_z) + ((ly+1) * cache_z) + lz]
				if n_top == -1 or n_top == BlockType.TORCH:
					var col = top_col
					if block_type == BlockType.LOG:
						col = COL_LOG_TOP + Color(var_off, var_off, var_off)
					var v0 = Vector3(x, y+1, z)
					var v1 = Vector3(x+1, y+1, z)
					var v2 = Vector3(x+1, y+1, z+1)
					var v3 = Vector3(x, y+1, z+1)
					var du = [-1, 1, 1, -1]
					var dv = [-1, -1, 1, 1]
					var ao_vals = [0,0,0,0]
					var sh_vals = [1.0,1.0,1.0,1.0]
					for i in range(4):
						var sx = x + du[i]
						var sz_ = z + dv[i]
						var s1=false
						var s2=false
						var cs=false
						var clx1 = sx - origin_x + 1
						if clx1>=0 and clx1<cache_x and y+1>=0 and y+1<size_y:
							var vv = cache[(clx1*size_y*cache_z)+((y+1)*cache_z)+lz]
							if vv!=-1 and vv!=BlockType.TORCH: s1=true
						var clz2 = sz_ - origin_z +1
						if clz2>=0 and clz2<cache_z and y+1>=0 and y+1<size_y:
							var vv2 = cache[(lx*size_y*cache_z)+((y+1)*cache_z)+clz2]
							if vv2!=-1 and vv2!=BlockType.TORCH: s2=true
						var clx_c = sx - origin_x +1
						var clz_c = sz_ - origin_z +1
						if clx_c>=0 and clx_c<cache_x and clz_c>=0 and clz_c<cache_z and y+1>=0 and y+1<size_y:
							var vvc = cache[(clx_c*size_y*cache_z)+((y+1)*cache_z)+clz_c]
							if vvc!=-1 and vvc!=BlockType.TORCH: cs=true
						var ao=0
						if s1 and s2: ao=3
						else:
							if s1: ao+=1
							if s2: ao+=1
							if cs: ao+=1
						ao_vals[i]=ao
						var vx = x + (1 if i==1 or i==2 else 0)
						var vz_ = z + (1 if i==2 or i==3 else 0)
						var best_sh = 1.0
						for ox in range(-1,2):
							for oz in range(-1,2):
								var horiz = sqrt(float(ox*ox+oz*oz))
								for dy in range(2,8):
									var wy2 = y+dy
									if wy2>=max_build_y: break
									var wwx = vx+ox
									var wwz = vz_+oz
									var clx_s = wwx - origin_x +1
									var clz_s = wwz - origin_z +1
									var solid=false
									if clx_s>=0 and clx_s<cache_x and clz_s>=0 and clz_s<cache_z and wy2>=0 and wy2<size_y:
										var vvs = cache[(clx_s*size_y*cache_z)+(wy2*cache_z)+clz_s]
										if vvs!=-1 and vvs!=BlockType.TORCH: solid=true
									if solid:
										var vert = dy-1
										var f = 0.72 + float(vert-1)*0.06 + horiz*0.10
										if f>0.97: f=0.97
										if f<best_sh: best_sh=f
										break
						sh_vals[i]=best_sh
					var base_idx = vertices.size()
					vertices.append(v0); vertices.append(v1); vertices.append(v2); vertices.append(v3)
					normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0)); normals.append(Vector3(0,1,0))
					for i in range(4):
						var b = ao_table[ao_vals[i]] if enable_ao else 1.0
						var sh = sh_vals[i]
						colors.append(Color(col.r*b*sh, col.g*b*sh, col.b*b*sh, col.a))
					indices.append(base_idx+0); indices.append(base_idx+1); indices.append(base_idx+2)
					indices.append(base_idx+0); indices.append(base_idx+2); indices.append(base_idx+3)

				# -Y
				var n_bot = -1
				if ly-1>=0:
					n_bot = cache[(lx*size_y*cache_z)+((ly-1)*cache_z)+lz]
				if n_bot==-1 or n_bot==BlockType.TORCH:
					if y>0:
						var bcol = side_col*0.92
						var du2 = [-1,1,1,-1]
						var dv2 = [1,1,-1,-1]
						var ao2 = [0,0,0,0]
						for i in range(4):
							var sx = x+du2[i]
							var sz_ = z+dv2[i]
							var s1=false
							var s2=false
							var cs=false
							var clx1 = sx - origin_x +1
							if clx1>=0 and clx1<cache_x and y-1>=0 and y-1<size_y:
								var vv=cache[(clx1*size_y*cache_z)+((y-1)*cache_z)+lz]
								if vv!=-1 and vv!=BlockType.TORCH: s1=true
							var clz2 = sz_ - origin_z +1
							if clz2>=0 and clz2<cache_z and y-1>=0 and y-1<size_y:
								var vv2=cache[(lx*size_y*cache_z)+((y-1)*cache_z)+clz2]
								if vv2!=-1 and vv2!=BlockType.TORCH: s2=true
							var clx_c = sx - origin_x +1
							var clz_c = sz_ - origin_z +1
							if clx_c>=0 and clx_c<cache_x and clz_c>=0 and clz_c<cache_z and y-1>=0 and y-1<size_y:
								var vvc=cache[(clx_c*size_y*cache_z)+((y-1)*cache_z)+clz_c]
								if vvc!=-1 and vvc!=BlockType.TORCH: cs=true
							var ao=0
							if s1 and s2: ao=3
							else:
								if s1: ao+=1
								if s2: ao+=1
								if cs: ao+=1
							ao2[i]=ao
						var base_idx2 = vertices.size()
						vertices.append(Vector3(x, y, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x, y, z))
						normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0)); normals.append(Vector3(0,-1,0))
						for i in range(4):
							var b = ao_table[ao2[i]] if enable_ao else 1.0
							colors.append(Color(bcol.r*b, bcol.g*b, bcol.b*b, bcol.a))
						indices.append(base_idx2+0); indices.append(base_idx2+1); indices.append(base_idx2+2)
						indices.append(base_idx2+0); indices.append(base_idx2+2); indices.append(base_idx2+3)

				# +X
				var n_east = -1
				if lx+1<cache_x:
					n_east = cache[((lx+1)*size_y*cache_z)+(ly*cache_z)+lz]
				if n_east==-1 or n_east==BlockType.TORCH:
					var aox=[0,0,0,0]
					for i in range(4):
						var dy = [-1,1,1,-1][i]
						var dz_ = [-1,-1,1,1][i]
						var s1=false
						var s2=false
						var cs=false
						var wy = y+dy
						if wy>=0 and wy<size_y:
							var vv=cache[((lx+1)*size_y*cache_z)+(wy*cache_z)+lz]
							if vv!=-1 and vv!=BlockType.TORCH: s1=true
						var wz_ = z+dz_
						var clz = wz_ - origin_z +1
						if clz>=0 and clz<cache_z:
							var vv2=cache[((lx+1)*size_y*cache_z)+(ly*cache_z)+clz]
							if vv2!=-1 and vv2!=BlockType.TORCH: s2=true
						if wy>=0 and wy<size_y and clz>=0 and clz<cache_z:
							var vvc=cache[((lx+1)*size_y*cache_z)+(wy*cache_z)+clz]
							if vvc!=-1 and vvc!=BlockType.TORCH: cs=true
						var ao=0
						if s1 and s2: ao=3
						else:
							if s1: ao+=1
							if s2: ao+=1
							if cs: ao+=1
						aox[i]=ao
					var base_idx3 = vertices.size()
					vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z)); vertices.append(Vector3(x+1, y, z))
					normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0)); normals.append(Vector3(1,0,0))
					for i in range(4):
						var b = ao_table[aox[3-i]] if enable_ao else 1.0
						colors.append(Color(side_col.r*b, side_col.g*b, side_col.b*b, side_col.a))
					indices.append(base_idx3+0); indices.append(base_idx3+1); indices.append(base_idx3+2)
					indices.append(base_idx3+0); indices.append(base_idx3+2); indices.append(base_idx3+3)

				# -X, +Z, -Z
				var n_west = -1
				if lx-1>=0:
					n_west = cache[((lx-1)*size_y*cache_z)+(ly*cache_z)+lz]
				if n_west==-1 or n_west==BlockType.TORCH:
					var base_idx4 = vertices.size()
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x, y+1, z)); vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0)); normals.append(Vector3(-1,0,0))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx4+0); indices.append(base_idx4+1); indices.append(base_idx4+2)
					indices.append(base_idx4+0); indices.append(base_idx4+2); indices.append(base_idx4+3)

				var n_south = -1
				if lz+1<cache_z:
					n_south = cache[(lx*size_y*cache_z)+(ly*cache_z)+(lz+1)]
				if n_south==-1 or n_south==BlockType.TORCH:
					var base_idx5 = vertices.size()
					vertices.append(Vector3(x, y+1, z+1)); vertices.append(Vector3(x+1, y+1, z+1)); vertices.append(Vector3(x+1, y, z+1)); vertices.append(Vector3(x, y, z+1))
					normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1)); normals.append(Vector3(0,0,1))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx5+0); indices.append(base_idx5+1); indices.append(base_idx5+2)
					indices.append(base_idx5+0); indices.append(base_idx5+2); indices.append(base_idx5+3)

				var n_north = -1
				if lz-1>=0:
					n_north = cache[(lx*size_y*cache_z)+(ly*cache_z)+(lz-1)]
				if n_north==-1 or n_north==BlockType.TORCH:
					var base_idx6 = vertices.size()
					vertices.append(Vector3(x, y, z)); vertices.append(Vector3(x+1, y, z)); vertices.append(Vector3(x+1, y+1, z)); vertices.append(Vector3(x, y+1, z))
					normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1)); normals.append(Vector3(0,0,-1))
					for i in range(4):
						colors.append(side_col)
					indices.append(base_idx6+0); indices.append(base_idx6+1); indices.append(base_idx6+2)
					indices.append(base_idx6+0); indices.append(base_idx6+2); indices.append(base_idx6+3)
	
	if vertices.is_empty():
		return null
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var st_mesh = ArrayMesh.new()
	st_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return st_mesh

func _create_water_plane():
	if not show_water:
		return
	var water_mesh = PlaneMesh.new()
	water_mesh.size = Vector2(world_size, world_size)
	water_mesh.subdivide_depth = 1
	water_mesh.subdivide_width = 1
	var mi = MeshInstance3D.new()
	mi.mesh = water_mesh
	mi.name = "WaterPlane"
	mi.position = Vector3(world_size*0.5, float(water_level)+0.45, world_size*0.5)
	var mat: Material
	if water_shader != null:
		var sm = ShaderMaterial.new()
		sm.shader = water_shader
		mat = sm
	else:
		var stdm = StandardMaterial3D.new()
		stdm.albedo_color = Color(0.43, 0.68, 0.78, 0.42)
		stdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		stdm.roughness = 0.2
		mat = stdm
	if mat is StandardMaterial3D:
		mat.transparency = StandardMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.43, 0.68, 0.78, 0.44)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _create_bounds_floor():
	# Disabled to avoid gray/brown band artifacts in orthographic top-down.
	# Previously showed a box under world that appeared as thick band.
	return
	var floor_mesh = BoxMesh.new()
	floor_mesh.size = Vector3(world_size + 4, 2.0, world_size + 4)
	var mi = MeshInstance3D.new()
	mi.mesh = floor_mesh
	mi.position = Vector3(world_size*0.5, -1.0, world_size*0.5)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.30, 0.24)
	mat.roughness = 1.0
	mi.material_override = mat
	mi.name = "GroundBase"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# Helpers for spawn - open meadow guaranteed
func get_spawn_position() -> Vector3:
	var cx = world_size / 2
	var cz = world_size / 2
	var meadow_radius = 24.0
	var best = Vector3(cx+0.5, 10.5, cz+0.5)
	var best_score = 9999.0
	for dx in range(-int(meadow_radius), int(meadow_radius)+1):
		for dz in range(-int(meadow_radius), int(meadow_radius)+1):
			var x = cx + dx
			var z = cz + dz
			if x<2 or x>=world_size-2 or z<2 or z>=world_size-2:
				continue
			if Vector2(x,z).distance_to(Vector2(cx,cz)) > meadow_radius:
				continue
			if type_map[x][z] != BlockType.GRASS:
				continue
			var h = height_map[x][z]
			var slope = 0
			for d in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
				var nx = x + d.x
				var nz = z + d.y
				if nx>=0 and nx<world_size and nz>=0 and nz<world_size:
					slope = max(slope, abs(height_map[nx][nz]-h))
			if slope>0:
				continue # perfectly flat meadow for spawn
			var score = abs(dx)+abs(dz)
			if score < best_score:
				best_score = score
				best = Vector3(x+0.5, float(h)+1.0, z+0.5)
	return best
