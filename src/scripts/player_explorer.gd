extends Node3D
class_name PlayerExplorer

# Blocky explorer:
# - camera-relative WASD, space hop
# - Q/E handled by camera rig (quarter turns)
# - Left hold to mine, right click to place
# - Cursor selects reachable block or adjacent placement cell (raycast)
# - 9 hotbar, collects grass dirt stone sand wood leaves, 1:1

@export var move_speed: float = 5.0
@export var jump_velocity: float = 8.5
@export var gravity: float = 20.0
@export var reach: float = 6.0
@export var mine_hold_time: float = 0.35
@export var place_cooldown: float = 0.18
@export var player_width: float = 0.6
@export var player_height: float = 1.8
@export var step_height: float = 1.0

var velocity: Vector3 = Vector3.ZERO
var on_ground: bool = false

var world: Node = null
var camera: Camera3D = null
var camera_rig: Node3D = null

# Raycast targeting
var target_block: Vector3i = Vector3i(-999,-999,-999)
var target_has: bool = false
var placement_block: Vector3i = Vector3i(-999,-999,-999)
var placement_has: bool = false
var last_ray_normal: Vector3i = Vector3i.UP

# Mining state
var is_mining: bool = false
var mine_timer: float = 0.0
var mine_target: Vector3i = Vector3i(-999,-999,-999)
var mine_target_rev: int = -1

var place_timer: float = 0.0

# Inventory / hotbar
# 9 slots: {type: BlockType, count: int} or null
var hotbar: Array = []
var selected_slot: int = 0

var model_root: Node3D
var selection_box: Node3D
var ghost_block: MeshInstance3D
var _selection_edge_mats: Array = []

var chip_script = preload("res://scripts/block_chip.gd")
var shared_chip_mesh: BoxMesh
var shared_chip_mats: Dictionary = {} # type -> StandardMaterial
var shared_pop_mesh: BoxMesh

# freeze fix: cache highest solid top per column (Vector2i), avoids per-frame scanning
var _highest_top_cache: Dictionary = {} # Vector2i -> float top (y+1) or -9999
var _highest_y_cache: Dictionary = {} # Vector2i -> int y

func _ready():
	add_to_group("player")
	hotbar.resize(9)
	for i in range(9):
		hotbar[i] = null
	
	world = get_node_or_null("../World")
	if world == null:
		world = get_parent().get_node_or_null("World")
	camera_rig = get_node_or_null("../CameraRig")
	if camera_rig == null:
		camera_rig = get_tree().get_first_node_in_group("camera_rig")
	if camera_rig:
		camera = camera_rig.get_node_or_null("Pitch/Camera3D")
	if camera == null:
		camera = get_viewport().get_camera_3d()
	
	# spawn at world spawn pos
	if world and world.has_method("get_spawn_position"):
		var sp = world.get_spawn_position()
		global_position = sp
		# ensure above ground
		global_position.y += 0.1
	
	shared_chip_mesh = BoxMesh.new()
	shared_chip_mesh.size = Vector3(0.12, 0.12, 0.06)
	shared_pop_mesh = BoxMesh.new()
	shared_pop_mesh.size = Vector3(0.9,0.9,0.9)
	for t in [0,1,2,3,4,5,6]:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = _color_for_type(t)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 0.9
		shared_chip_mats[t] = mat
	
	_create_model()
	_create_selection()
	_create_ghost()
	
	# give starter torches in hotbar slot 7 (index 6) and some WOOD
	hotbar[6] = {"type": 6, "count": 16} # TORCH x16
	hotbar[0] = {"type": 0, "count": 12}
	hotbar[1] = {"type": 2, "count": 8}
	
	# connect to world edits to invalidate top cache
	if world and world.has_signal("block_changed"):
		world.block_changed.connect(_on_world_block_changed)
	
	print("[Player] Ready at ", global_position)

func _on_world_block_changed(pos: Vector3i, _old_type, _new_type, _rev: int):
	# invalidate cached top for this xz column
	var key = Vector2i(pos.x, pos.z)
	_highest_top_cache.erase(key)
	_highest_y_cache.erase(key)
	# also neighbors may need? No, only this column's top.
	# For ground detection we also check 4-wide footprint, but that will be re-cached on demand.

var contact_shadow: MeshInstance3D

func _create_model():
	model_root = Node3D.new()
	model_root.name = "ModelRoot"
	add_child(model_root)
	
	# Blocky body: torso 0.6w x 0.7h x 0.35d
	var torso = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.7, 0.35)
	torso.mesh = box
	torso.position = Vector3(0, 0.95, 0)
	torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.49, 0.78) # blue shirt
	mat.roughness = 0.9
	torso.material_override = mat
	model_root.add_child(torso)
	
	# Head 0.5 cube
	var head = MeshInstance3D.new()
	var head_box = BoxMesh.new()
	head_box.size = Vector3(0.5, 0.5, 0.5)
	head.mesh = head_box
	head.position = Vector3(0, 1.55, 0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var hmat = StandardMaterial3D.new()
	hmat.albedo_color = Color(0.92, 0.80, 0.62) # skin
	hmat.roughness = 0.9
	head.material_override = hmat
	model_root.add_child(head)
	
	# Legs
	for side in [-1,1]:
		var leg = MeshInstance3D.new()
		var leg_box = BoxMesh.new()
		leg_box.size = Vector3(0.22, 0.6, 0.24)
		leg.mesh = leg_box
		leg.position = Vector3(side*0.15, 0.3, 0)
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var lmat = StandardMaterial3D.new()
		lmat.albedo_color = Color(0.28, 0.28, 0.32)
		leg.material_override = lmat
		model_root.add_child(leg)
	
	# Arms
	for side in [-1,1]:
		var arm = MeshInstance3D.new()
		var arm_box = BoxMesh.new()
		arm_box.size = Vector3(0.2, 0.55, 0.2)
		arm.mesh = arm_box
		arm.position = Vector3(side*0.4, 0.95, 0)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var amat = StandardMaterial3D.new()
		amat.albedo_color = Color(0.92, 0.80, 0.62)
		arm.material_override = amat
		model_root.add_child(arm)

	# Contact blob shadow - soft radial AO under feet (smooth, not blocky)
	contact_shadow = MeshInstance3D.new()
	contact_shadow.name = "ContactShadow"
	var plane = PlaneMesh.new()
	plane.size = Vector2(1.4, 1.4)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	contact_shadow.mesh = plane
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var blob_shader = load("res://shaders/blob_shadow.gdshader")
	var smat: Material
	if blob_shader != null:
		var sh_mat = ShaderMaterial.new()
		sh_mat.shader = blob_shader
		sh_mat.set_shader_parameter("shadow_color", Color(0.06, 0.06, 0.06, 0.55))
		smat = sh_mat
	else:
		var stdm = StandardMaterial3D.new()
		stdm.albedo_color = Color(0.08, 0.08, 0.08, 0.55)
		stdm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		stdm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		stdm.cull_mode = BaseMaterial3D.CULL_DISABLED
		smat = stdm
	contact_shadow.material_override = smat
	add_child(contact_shadow)

var crack_box: MeshInstance3D
var chip_container: Node3D
var breaking_block: MeshInstance3D

func _create_selection():
	# Robust yellow wire outline: 12 thin boxes as edges - never gray, depth-tested, no shader discard needed
	var edge_thickness = 0.045
	var hs = 0.5125 # half size for 1.025 cube
	selection_box = Node3D.new()
	selection_box.name = "SelectionBox"
	_selection_edge_mats.clear()

	var edge_mat = StandardMaterial3D.new()
	edge_mat.albedo_color = Color(1.0, 0.92, 0.08, 1.0)
	edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	edge_mat.no_depth_test = false
	var base_mat = edge_mat

	var edges_def = [
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, hs, hs)},
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, hs, -hs)},
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, -hs, hs)},
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, -hs, -hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(hs, 0, hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(hs, 0, -hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(-hs, 0, hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(-hs, 0, -hs)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(hs, hs, 0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(hs, -hs, 0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(-hs, hs, 0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(-hs, -hs, 0)},
	]

	for ed in edges_def:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = ed["size"]
		mi.mesh = bm
		mi.position = ed["pos"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m = base_mat.duplicate() as StandardMaterial3D
		mi.material_override = m
		_selection_edge_mats.append(m)
		selection_box.add_child(mi)

	selection_box.visible = false
	if world:
		world.add_child(selection_box)
	else:
		get_parent().add_child(selection_box)
	
	# Breaking visual: expand the block texture itself (not new effect)
	breaking_block = MeshInstance3D.new()
	breaking_block.name = "BreakingBlock"
	var bb_mesh = BoxMesh.new()
	bb_mesh.size = Vector3(1.01, 1.01, 1.01)
	breaking_block.mesh = bb_mesh
	breaking_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bb_mat = StandardMaterial3D.new()
	bb_mat.albedo_color = Color(0.66, 0.66, 0.63, 1.0)
	bb_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	bb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	breaking_block.material_override = bb_mat
	breaking_block.visible = false
	if world:
		world.add_child(breaking_block)
	else:
		get_parent().add_child(breaking_block)
	
	# Keep crack_box but unused - hidden, no breaking effect
	crack_box = MeshInstance3D.new()
	crack_box.name = "CrackBox"
	var cb = BoxMesh.new()
	cb.size = Vector3(1.01, 1.01, 1.01)
	crack_box.mesh = cb
	crack_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack_box.visible = false
	var cstd = StandardMaterial3D.new()
	cstd.albedo_color = Color(0,0,0,0.0)
	cstd.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cstd.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	crack_box.material_override = cstd
	if world:
		world.add_child(crack_box)
	else:
		get_parent().add_child(crack_box)
	
	# Chip container kept for compatibility but no particles spawned
	chip_container = Node3D.new()
	chip_container.name = "ChipContainer"
	if world:
		world.add_child(chip_container)
	else:
		get_parent().add_child(chip_container)

func _create_ghost():
	# Placement ghost - translucent preview showing actual block color, not gray
	ghost_block = MeshInstance3D.new()
	ghost_block.name = "GhostBlock"
	var b = BoxMesh.new()
	b.size = Vector3(1.0, 1.0, 1.0)
	ghost_block.mesh = b
	ghost_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.67, 0.4, 0.48)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = false
	ghost_block.material_override = mat
	ghost_block.visible = false
	if world:
		world.add_child(ghost_block)
	else:
		get_parent().add_child(ghost_block)

func _physics_process(delta):
	if world == null:
		return
	_handle_movement(delta)
	_handle_raycast()
	_handle_mining_placing(delta)
	_update_selection_visuals()
	_update_contact_shadow()

func _update_contact_shadow():
	if contact_shadow == null:
		return
	var g = _get_ground_y(global_position)
	if g == -9999.0:
		contact_shadow.visible = false
		return
	contact_shadow.visible = true
	# place slightly above ground to avoid z-fighting
	contact_shadow.global_position = Vector3(global_position.x, g + 0.02, global_position.z)
	# scale opacity based on distance to ground (fade when jumping)
	var dist = global_position.y - g
	var alpha = clamp(1.0 - dist * 0.8, 0.0, 0.55)
	var plane_mesh = contact_shadow.mesh as PlaneMesh
	if plane_mesh:
		var size_factor = clamp(1.4 - dist * 0.18, 0.5, 1.4)
		plane_mesh.size = Vector2(size_factor, size_factor)
	var mat = contact_shadow.material_override
	if mat is ShaderMaterial:
		mat.set_shader_parameter("shadow_color", Color(0.06, 0.06, 0.06, alpha))
	elif mat is StandardMaterial3D:
		mat.albedo_color = Color(0.08, 0.08, 0.08, alpha)

func _handle_movement(delta):
	# gravity
	if not on_ground:
		velocity.y -= gravity * delta
	
	# input
	var input_dir = _get_input_dir() # Vector2 (x right, z forward) camera-relative? We'll compute world dir
	var cam_forward = Vector3.ZERO
	var cam_right = Vector3.ZERO
	if camera_rig and camera_rig.has_method("get_flat_forward"):
		cam_forward = camera_rig.get_flat_forward()
		cam_right = camera_rig.get_flat_right()
	elif camera:
		var basis = camera.global_transform.basis
		cam_forward = -basis.z
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		cam_right = basis.x
		cam_right.y = 0
		cam_right = cam_right.normalized()
	else:
		cam_forward = Vector3(0,0,-1)
		cam_right = Vector3(1,0,0)
	
	var move_vec = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		move_vec = (cam_right * input_dir.x + cam_forward * input_dir.y)
		move_vec = move_vec.normalized() * move_speed
		# rotate model to face move dir
		if move_vec.length() > 0.1 and model_root:
			var yaw = atan2(move_vec.x, move_vec.z)
			model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, delta * 10.0)
	
	# apply horizontal velocity (x,z)
	velocity.x = move_vec.x
	velocity.z = move_vec.z
	
	# jumping
	if Input.is_action_just_pressed("jump") or Input.is_key_pressed(KEY_SPACE):
		if on_ground:
			velocity.y = jump_velocity
			on_ground = false
	
	# move with collision - ensures snap to actual block height
	var motion = velocity * delta
	motion = _move_with_collision(motion)
	
	# re-evaluate ground after move
	if _is_on_ground():
		on_ground = true
		if velocity.y <= 0:
			velocity.y = 0
	else:
		if motion.y == 0 and velocity.y < 0:
			# hit ceiling or still falling but blocked
			on_ground = _is_on_ground()
		elif velocity.y > 0:
			on_ground = false
		else:
			# falling
			on_ground = false
	
	# clamp to world bounds
	global_position.x = clamp(global_position.x, 0.5, world.world_size - 0.5 if world else 199.5)
	global_position.z = clamp(global_position.z, 0.5, world.world_size - 0.5 if world else 199.5)
	if global_position.y < -10:
		# respawn
		if world and world.has_method("get_spawn_position"):
			global_position = world.get_spawn_position()

func _get_input_dir() -> Vector2:
	var x = 0.0
	var y = 0.0
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D) or Input.is_action_pressed("pan_right"):
		x += 1.0
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A) or Input.is_action_pressed("pan_left"):
		x -= 1.0
	if Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_W) or Input.is_action_pressed("pan_up"):
		y += 1.0
	if Input.is_action_pressed("move_back") or Input.is_key_pressed(KEY_S) or Input.is_action_pressed("pan_down"):
		y -= 1.0
	# normalize if needed later
	var v = Vector2(x,y)
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _move_with_collision(motion: Vector3) -> Vector3:
	# Pure gravity-based movement - no layer latch, only tiny landing correction
	var pos = global_position
	
	# X - no auto step-up of full blocks (prevents latch jump to new layer), only small slab tolerance
	if motion.x != 0:
		var new_pos = pos + Vector3(motion.x, 0, 0)
		if _collides_at(new_pos, true):
			motion.x = 0
		else:
			pos.x = new_pos.x
	
	# Z
	if motion.z != 0:
		var new_pos = pos + Vector3(0,0,motion.z)
		if _collides_at(new_pos, true):
			motion.z = 0
		else:
			pos.z = new_pos.z
	
	# Y with real gravity - only snap when within 0.25 of ground, otherwise fall
	if motion.y != 0:
		var new_pos = pos + Vector3(0,motion.y,0)
		if motion.y < 0:
			var ground = _get_ground_y(new_pos)
			if ground == -9999.0:
				ground = _get_ground_y(pos)
			# natural landing: only when crossing ground within small tolerance, not from 1+ blocks above
			if ground != -9999.0 and new_pos.y <= ground + 0.08 and new_pos.y >= ground - 0.6:
				pos.y = ground
				motion.y = 0
			elif _collides_at(new_pos, false):
				# hit ceiling or block inside
				if new_pos.y < pos.y:
					# falling into something
					var gy = _get_ground_y(new_pos)
					if gy != -9999.0 and abs(gy - new_pos.y) < 0.5:
						pos.y = gy
						motion.y = 0
					else:
						motion.y = 0
				else:
					motion.y = 0
			else:
				pos.y = new_pos.y
		else:
			# jumping up
			if _collides_at(new_pos, false):
				motion.y = 0
			else:
				pos.y = new_pos.y
	
	global_position = pos
	return motion

func _collides_at(pos: Vector3, ignore_ground: bool = true) -> bool:
	var min_x = floor(pos.x - player_width*0.5)
	var max_x = floor(pos.x + player_width*0.5)
	var min_y = floor(pos.y)
	var max_y = floor(pos.y + player_height - 0.001)
	var min_z = floor(pos.z - player_width*0.5)
	var max_z = floor(pos.z + player_width*0.5)
	for x in range(int(min_x), int(max_x)+1):
		for y in range(int(min_y), int(max_y)+1):
			for z in range(int(min_z), int(max_z)+1):
				if world and world.is_solid(Vector3i(x,y,z)):
					if ignore_ground:
						var block_top = float(y)+1.0
						if block_top <= pos.y + 0.05:
							continue
					return true
	return false

func _highest_solid_top_at(x: int, z: int) -> float:
	if world == null:
		return -9999.0
	var key = Vector2i(x, z)
	if _highest_top_cache.has(key):
		return _highest_top_cache[key]
	# use world's cached highest if available (avoids String formatting)
	var top: float = -9999.0
	if world.has_method("get_highest_top"):
		top = world.get_highest_top(x, z)
	else:
		# fallback scan using Vector3i dict only (no String)
		for y in range(world.max_build_y - 1, -1, -1):
			if world.is_solid(Vector3i(x, y, z)):
				top = float(y) + 1.0
				break
	_highest_top_cache[key] = top
	return top

func get_highest_y_at(x: int, z: int) -> int:
	var key = Vector2i(x, z)
	if _highest_y_cache.has(key):
		return _highest_y_cache[key]
	if world and world.has_method("get_highest_solid_y"):
		var y = world.get_highest_solid_y(x, z)
		_highest_y_cache[key] = y
		return y
	var top = _highest_solid_top_at(x, z)
	var y = int(top - 1.0) if top != -9999.0 else -1
	_highest_y_cache[key] = y
	return y

func _ground_top_at_pos(pos: Vector3) -> float:
	# average ground under player footprint (takes highest) - uses cache
	var min_x = floor(pos.x - player_width*0.5 + 0.08)
	var max_x = floor(pos.x + player_width*0.5 - 0.08)
	var min_z = floor(pos.z - player_width*0.5 + 0.08)
	var max_z = floor(pos.z + player_width*0.5 - 0.08)
	var best = -9999.0
	for x in range(int(min_x), int(max_x)+1):
		for z in range(int(min_z), int(max_z)+1):
			var t = _highest_solid_top_at(x, z)
			if t > best:
				best = t
	return best

func _is_on_ground() -> bool:
	var pos = global_position
	var g = _get_ground_y(pos)
	if g == -9999.0:
		return false
	return abs(g - pos.y) < 0.4

func _get_ground_y(pos: Vector3) -> float:
	# find highest solid below or at pos.y + small tolerance (for landing)
	# optimized: use cached top when close, else scan only few levels
	var min_x = floor(pos.x - player_width*0.5 + 0.08)
	var max_x = floor(pos.x + player_width*0.5 - 0.08)
	var min_z = floor(pos.z - player_width*0.5 + 0.08)
	var max_z = floor(pos.z + player_width*0.5 - 0.08)
	var best = -9999.0
	var feet_y = int(floor(pos.y + 0.15))
	for x in range(int(min_x), int(max_x)+1):
		for z in range(int(min_z), int(max_z)+1):
			# if top cache is close to feet, use it
			var cached_top = _highest_solid_top_at(x, z)
			if cached_top != -9999.0 and cached_top <= pos.y + 0.15 and cached_top >= pos.y - 2.0:
				if cached_top > best:
					best = cached_top
				continue
			# else check a few levels below feet
			for dy in range(0, 6):
				var y = feet_y - dy
				if world and world.is_solid(Vector3i(x, y, z)):
					var top = float(y) + 1.0
					if top <= pos.y + 0.15:
						if top > best:
							best = top
					break
	return best

# -------- Raycast for mining/placing --------
# Normal gameplay: camera raycasts block under cursor, player 6-block radius gates mine/place
var can_mine_target: bool = false
var can_place_target: bool = false

func _handle_raycast():
	target_has = false
	placement_has = false
	can_mine_target = false
	can_place_target = false
	if camera == null or world == null:
		return
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var best_hit: Vector3i
	var best_place: Vector3i
	var best_normal: Vector3i = Vector3i.UP
	var found = false
	
	# Primary: precise voxel raycast from camera through mouse cursor
	# Camera is ~70 units away (orbit_distance), so need 120 to reach ground
	var vres = _voxel_raycast(ray_origin, ray_dir, 120.0)
	if vres != null:
		best_hit = vres["hit_pos"] as Vector3i
		best_place = vres["place_pos"] as Vector3i
		best_normal = vres["face_normal"] as Vector3i
		found = true
	
	# Fallback: only if voxel ray missed, try column directly under mouse ray origin (orthographic stable)
	# This avoids using player Y which caused jump to down blocks near player
	if not found:
		var cx = int(floor(ray_origin.x))
		var cz = int(floor(ray_origin.z))
		if cx >= 0 and cz >= 0 and cx < world.world_size and cz < world.world_size:
			var top = _highest_solid_top_at(cx, cz)
			if top != -9999.0:
				var by = int(top - 1.0)
				var col_hit = Vector3i(cx, by, cz)
				if world.is_solid(col_hit):
					best_hit = col_hit
					best_place = col_hit + Vector3i.UP
					best_normal = Vector3i.UP
					found = true
		# If still not found, try intersection with ground plane at y=0 for extra stability
		if not found and abs(ray_dir.y) > 0.001:
			var t = (0.0 - ray_origin.y) / ray_dir.y
			if t >= 0.0 and t < 600.0:
				var inter = ray_origin + ray_dir * t
				var cx2 = int(floor(inter.x))
				var cz2 = int(floor(inter.z))
				if cx2 >= 0 and cz2 >= 0 and cx2 < world.world_size and cz2 < world.world_size:
					var top2 = _highest_solid_top_at(cx2, cz2)
					if top2 != -9999.0:
						var by2 = int(top2 - 1.0)
						var col_hit2 = Vector3i(cx2, by2, cz2)
						if world.is_solid(col_hit2):
							best_hit = col_hit2
							best_place = col_hit2 + Vector3i.UP
							best_normal = Vector3i.UP
							found = true
	
	if not found:
		return
	
	target_block = best_hit
	target_has = true
	last_ray_normal = best_normal
	placement_block = best_place
	
	var d_hit = global_position.distance_to(Vector3(best_hit.x+0.5, best_hit.y+0.5, best_hit.z+0.5))
	can_mine_target = d_hit <= 6.0
	
	if world.get_block_at(best_place) == null:
		# for torch, allow placement even if player collides? torch is walk-through, so ignore player collision for torches
		var placing_torch = false
		var sel = get_selected_block_type()
		if sel != null and sel == 6:
			placing_torch = true
		if placing_torch or not _placement_collides_player(best_place):
			placement_has = true
			can_place_target = global_position.distance_to(Vector3(best_place.x+0.5, best_place.y+0.5, best_place.z+0.5)) <= 6.0
		else:
			placement_has = false
			can_place_target = false
	else:
		placement_has = false
		can_place_target = false

func _voxel_raycast(origin: Vector3, dir: Vector3, max_dist: float):
	# Amanatides & Woo - uses raycast solid that includes torches
	dir = dir.normalized()
	if dir.length_squared() < 0.0001:
		return null
	var current = Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))
	
	# If origin inside solid, nudge forward a bit
	if world and world.has_method("is_raycast_solid") and world.is_raycast_solid(current):
		if not (world.has_method("is_solid") and not world.is_solid(current) and world.get_block_at(current) != null):
			# inside torch? still nudge
			pass
		origin = origin + dir * 0.6
		current = Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))
	elif world and world.is_solid(current):
		origin = origin + dir * 0.6
		current = Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))
	
	var step_x = 1 if dir.x >=0 else -1
	var step_y = 1 if dir.y >=0 else -1
	var step_z = 1 if dir.z >=0 else -1
	
	var t_max_x: float
	var t_max_y: float
	var t_max_z: float
	var t_delta_x: float
	var t_delta_y: float
	var t_delta_z: float
	
	var frac_x = origin.x - floor(origin.x)
	var frac_y = origin.y - floor(origin.y)
	var frac_z = origin.z - floor(origin.z)
	
	if dir.x != 0:
		t_delta_x = abs(1.0 / dir.x)
		if step_x > 0:
			t_max_x = (1.0 - frac_x) * t_delta_x
		else:
			t_max_x = frac_x * t_delta_x
	else:
		t_max_x = 999999.0
		t_delta_x = 999999.0
	
	if dir.y != 0:
		t_delta_y = abs(1.0 / dir.y)
		if step_y > 0:
			t_max_y = (1.0 - frac_y) * t_delta_y
		else:
			t_max_y = frac_y * t_delta_y
	else:
		t_max_y = 999999.0
		t_delta_y = 999999.0
	
	if dir.z != 0:
		t_delta_z = abs(1.0 / dir.z)
		if step_z > 0:
			t_max_z = (1.0 - frac_z) * t_delta_z
		else:
			t_max_z = frac_z * t_delta_z
	else:
		t_max_z = 999999.0
		t_delta_z = 999999.0
	
	var traveled = 0.0
	var last_pos = current
	
	for i in range(int(max_dist*3 + 10)): # max steps
		var is_hit = false
		if world:
			if world.has_method("is_raycast_solid"):
				is_hit = world.is_raycast_solid(current)
			else:
				is_hit = world.is_solid(current)
		if is_hit:
			# hit
			var face_normal: Vector3i
			if last_pos.x != current.x:
				face_normal = Vector3i(-step_x, 0,0)
			elif last_pos.y != current.y:
				face_normal = Vector3i(0, -step_y,0)
			else:
				face_normal = Vector3i(0,0,-step_z)
			# place pos is last empty
			var place_pos = last_pos
			# if origin started inside, we might have last_pos also solid? Check
			var place_is_solid = false
			if world:
				if world.has_method("is_raycast_solid"):
					place_is_solid = world.is_raycast_solid(place_pos)
				else:
					place_is_solid = world.is_solid(place_pos)
			if place_is_solid:
				place_pos = current + face_normal # adjacent
			return {"hit_pos": current, "place_pos": place_pos, "face_normal": face_normal}
		
		# advance
		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				last_pos = current
				current.x += step_x
				traveled = t_max_x
				t_max_x += t_delta_x
			else:
				last_pos = current
				current.z += step_z
				traveled = t_max_z
				t_max_z += t_delta_z
		else:
			if t_max_y < t_max_z:
				last_pos = current
				current.y += step_y
				traveled = t_max_y
				t_max_y += t_delta_y
			else:
				last_pos = current
				current.z += step_z
				traveled = t_max_z
				t_max_z += t_delta_z
		
		if traveled > max_dist:
			break
	
	return null

func _placement_collides_player(p: Vector3i) -> bool:
	var player_aabb_min = Vector3(global_position.x - player_width*0.5, global_position.y, global_position.z - player_width*0.5)
	var player_aabb_max = Vector3(global_position.x + player_width*0.5, global_position.y + player_height, global_position.z + player_width*0.5)
	var block_min = Vector3(float(p.x), float(p.y), float(p.z))
	var block_max = block_min + Vector3(1,1,1)
	# AABB intersect?
	if player_aabb_max.x <= block_min.x or player_aabb_min.x >= block_max.x:
		return false
	if player_aabb_max.y <= block_min.y or player_aabb_min.y >= block_max.y:
		return false
	if player_aabb_max.z <= block_min.z or player_aabb_min.z >= block_max.z:
		return false
	return true

func _handle_mining_placing(delta):
	place_timer -= delta
	var left_pressed = Input.is_action_pressed("mine") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	# Hold to mine - expands block texture itself, outline scales alongside
	# If holding and you move onto new block, cancel current and start new one immediately
	if left_pressed and target_has and can_mine_target:
		if not is_mining:
			mine_target = target_block
			mine_target_rev = world.get_revision(mine_target) if world.has_method("get_revision") else 0
			mine_timer = 0.0
			is_mining = true
		else:
			if mine_target != target_block:
				# Moved to new block while holding - cancel previous and start new instantly
				mine_target = target_block
				mine_target_rev = world.get_revision(mine_target) if world.has_method("get_revision") else 0
				mine_timer = 0.0
				# keep is_mining true, breaking visual will reset via _update_selection_visuals
			else:
				var cur_rev = world.get_revision(mine_target) if world.has_method("get_revision") else 0
				if cur_rev != mine_target_rev:
					is_mining = false
					mine_timer = 0.0
					mine_target = Vector3i(-999,-999,-999)
					mine_target_rev = -1
				else:
					mine_timer += delta
					if mine_timer >= mine_hold_time:
						_commit_mine(mine_target)
						mine_timer = 0.0
						is_mining = false
						mine_target = Vector3i(-999,-999,-999)
						mine_target_rev = -1
	else:
		if is_mining:
			is_mining = false
			mine_timer = 0.0
			mine_target = Vector3i(-999,-999,-999)
			mine_target_rev = -1
	
	# right click to place - player radius 6 determines if can place, camera is selector
	if Input.is_action_just_pressed("place") or Input.is_action_just_pressed("place_click") or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and place_timer <= 0.0):
		if placement_has and can_place_target and _can_place():
			_commit_place(placement_block)
			place_timer = place_cooldown
func _can_place() -> bool:
	if not placement_has or not can_place_target:
		return false
	var slot = hotbar[selected_slot]
	if slot == null:
		return false
	if slot["count"] <= 0:
		return false
	return true

func _commit_mine(pos: Vector3i):
	if world == null:
		return
	if world.has_method("get_revision") and mine_target_rev != -1:
		var cur = world.get_revision(pos)
		if cur != mine_target_rev:
			print("[Mine] Cancelled stale rev %d != %d at %s" % [cur, mine_target_rev, pos])
			mine_target = Vector3i(-999,-999,-999)
			mine_timer = 0.0
			is_mining = false
			mine_target_rev = -1
			return
	var result = world.try_mine_block(pos)
	if result != null:
		var mined_type = result["type"] if typeof(result) == TYPE_DICTIONARY else result
		# Block itself expands/contracts - no extra pop effect, just reset visuals
		if breaking_block:
			breaking_block.visible = false
			breaking_block.scale = Vector3.ONE
		if selection_box:
			selection_box.scale = Vector3.ONE
		_add_to_inventory(mined_type)
		print("[Mine] %s rev %s at %s" % [block_type_to_name(mined_type), result["revision"] if typeof(result)==TYPE_DICTIONARY else "?", pos])
		_handle_raycast()
		get_tree().call_group("hotbar_ui", "pop_slot", selected_slot)
	mine_target = Vector3i(-999,-999,-999)
	mine_timer = 0.0
	is_mining = false
	mine_target_rev = -1
func _commit_place(pos: Vector3i):
		if world == null:
			return
		if world.has_method("is_world_edge") and world.is_world_edge(pos):
			print("[Place] Rejected world edge at %s" % pos)
			return
		var slot = hotbar[selected_slot]
		if slot == null:
			return
		var type_to_place = slot["type"]
		var placed_ok = false
		# Torch requires attachment dir
		if type_to_place == 6: # TORCH
			# last_ray_normal is direction from hit to placement (outward). Support dir is opposite = last_ray_normal * -1? Actually support is hit block, which is -last_ray_normal direction from placement
			var support_dir = -last_ray_normal
			# store attach as support_dir (where torch attaches to)
			if world.has_method("try_place_torch"):
				placed_ok = world.try_place_torch(pos, support_dir)
			else:
				placed_ok = world.try_place_block(pos, type_to_place, support_dir)
		else:
			placed_ok = world.try_place_block(pos, type_to_place)
		if placed_ok:
			slot["count"] -= 1
			if slot["count"] <= 0:
				hotbar[selected_slot] = null
			print("[Place] %s at %s attach %s" % [block_type_to_name(type_to_place), pos, last_ray_normal if type_to_place==6 else ""])
			get_tree().call_group("hotbar_ui", "refresh")
			_handle_raycast()
		else:
			print("[Place] Failed at %s type %s" % [pos, block_type_to_name(type_to_place)])

# Inventory

func _add_to_inventory(block_type: int):
	# stacking: try find existing slot with same type
	for i in range(hotbar.size()):
		var s = hotbar[i]
		if s != null and s["type"] == block_type:
			s["count"] += 1
			get_tree().call_group("hotbar_ui", "refresh")
			return
	# find empty
	for i in range(hotbar.size()):
		if hotbar[i] == null:
			hotbar[i] = {"type": block_type, "count": 1}
			get_tree().call_group("hotbar_ui", "refresh")
			return
	# full - drop? ignore
	print("[Inventory] Full, cannot collect %s" % block_type_to_name(block_type))

func block_type_to_name(t: int) -> String:
		match t:
			0: return "Grass"
			1: return "Sand"
			2: return "Stone"
			3: return "Dirt"
			4: return "Wood"
			5: return "Leaves"
			6: return "Torch"
			_: return "Unknown"

func get_selected_block_type():
	var s = hotbar[selected_slot]
	if s == null:
		return null
	return s["type"]

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx = event.keycode - KEY_1
			selected_slot = idx
			get_tree().call_group("hotbar_ui", "refresh")

func _color_for_type(t: int) -> Color:
		match t:
			0: return Color(0.52,0.67,0.40)
			1: return Color(0.86,0.80,0.62)
			2: return Color(0.66,0.66,0.63)
			3: return Color(0.46,0.38,0.30)
			4: return Color(0.38,0.29,0.21)
			5: return Color(0.36,0.52,0.30)
			6: return Color(0.94,0.75,0.28) # Torch
			_: return Color(0.8,0.2,0.8)

# Removed particles and crack breaking effect - now using expand/contract animation

func _update_selection_visuals():
	var has_block = get_selected_block_type() != null
	var left_holding = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_action_pressed("mine")
	
	var show_mining_outline = false
	var show_ghost = false
	
	if has_block:
		if left_holding or is_mining:
			show_mining_outline = target_has
			show_ghost = false
		else:
			show_mining_outline = false
			show_ghost = placement_has
	else:
		show_mining_outline = target_has
		show_ghost = false
	
	# --- Yellow outline + block texture expands/contracts (no extra effect) ---
	if show_mining_outline and selection_box and target_has:
		selection_box.visible = true
		var center = Vector3(float(target_block.x)+0.5, float(target_block.y)+0.5, float(target_block.z)+0.5)
		selection_box.global_position = center
		if breaking_block:
			breaking_block.global_position = center
		
		var pulse = 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 1.8 * TAU)
		var target_color: Color
		if can_mine_target:
			target_color = Color(1.0, 0.92, 0.08, 0.95 * pulse)
		else:
			target_color = Color(1.0, 0.32, 0.22, 0.55 * pulse)
		if _selection_edge_mats.size() > 0:
			for em in _selection_edge_mats:
				if em is StandardMaterial3D:
					em.albedo_color = target_color
		
		# Expand the block texture itself, and outline alongside to prevent flashing
		if is_mining and can_mine_target:
			if breaking_block:
				breaking_block.visible = true
				var bt = world.get_block_at(target_block) if world else null
				if bt != null:
					var c = _color_for_type(bt)
					var bmat = breaking_block.material_override
					if bmat is StandardMaterial3D:
						bmat.albedo_color = c
				var progress = clamp(mine_timer / mine_hold_time, 0.0, 1.0)
				# 0 -> 1 -> 0 expand then contract back to original shape (texture itself)
				var expand = 0.12 * sin(progress * PI)
				var s = 1.0 + expand
				breaking_block.scale = Vector3(s, s, s)
				# Scale yellow outline alongside with same factor to avoid flashing/z-fighting
				selection_box.scale = Vector3(s, s, s)
		else:
			if breaking_block:
				breaking_block.visible = false
				breaking_block.scale = Vector3.ONE
			selection_box.scale = Vector3.ONE
	else:
		if selection_box:
			selection_box.visible = false
			selection_box.scale = Vector3.ONE
		if breaking_block:
			breaking_block.visible = false
			breaking_block.scale = Vector3.ONE
		if crack_box:
			crack_box.visible = false
	
	# Ghost: translucent preview of actual block type - torch gets small preview
	if show_ghost and ghost_block and placement_has:
		var sel_type = get_selected_block_type()
		if sel_type == null:
			ghost_block.visible = false
		else:
			ghost_block.visible = true
			var base_center = Vector3(float(placement_block.x)+0.5, float(placement_block.y)+0.5, float(placement_block.z)+0.5)
			# offset ghost slightly towards support if torch
			if sel_type == 6:
				var support_dir = -last_ray_normal
				base_center += Vector3(support_dir.x, support_dir.y, support_dir.z) * 0.32
				if support_dir == Vector3i.DOWN:
					base_center.y = placement_block.y + 0.15
				# small torch shape for ghost
				(ghost_block.mesh as BoxMesh).size = Vector3(0.12, 0.55, 0.12)
			else:
				(ghost_block.mesh as BoxMesh).size = Vector3(1.0, 1.0, 1.0)
			ghost_block.global_position = base_center
			var gmat = ghost_block.material_override
			var c = _color_for_type(sel_type)
			if gmat is StandardMaterial3D:
				if can_place_target:
					gmat.albedo_color = Color(c.r, c.g, c.b, 0.48)
				else:
					gmat.albedo_color = Color(c.r, c.g, c.b, 0.18)
	else:
		if ghost_block:
			ghost_block.visible = false
			ghost_block.visible = false
