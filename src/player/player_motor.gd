extends CharacterBody3D
class_name PlayerMotor

## PlayerMotor - typed DI, uses move_and_slide, swept collision, no step_height, no auto-repeat jump

@export var move_speed: float = 5.5
@export var jump_velocity: float = 9.0
@export var gravity: float = 20.0
@export var player_width: float = 0.6
@export var player_height: float = 1.8

var world: WorldController = null
var voxel_world: VoxelWorld = null
var camera_rig: CameraRig = null
var camera_3d: Camera3D = null
var inventory_model: InventoryModel = null

var on_ground: bool = false
var model_root: Node3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func setup(p_world: WorldController, p_voxel_world: VoxelWorld, p_camera_rig: CameraRig, p_camera_3d: Camera3D, p_inventory: InventoryModel):
	world = p_world
	voxel_world = p_voxel_world
	camera_rig = p_camera_rig
	camera_3d = p_camera_3d
	inventory_model = p_inventory
	if voxel_world and (global_position == Vector3.ZERO or global_position.length() < 1.0):
		var sp = voxel_world.get_spawn_position()
		global_position = sp + Vector3(0, 0.1, 0)
	_ensure_collision_shape()
	_ensure_model()
	print("[PlayerMotor] Ready at %s world=%s model=%s cam_rig=%s inv=%s" % [global_position, world != null, voxel_world != null, camera_rig != null, inventory_model != null])

func _ready():
	_ensure_collision_shape()
	_ensure_model()
	if voxel_world == null:
		print("[PlayerMotor] _ready waiting for injection")

func _ensure_collision_shape():
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		add_child(collision_shape)
	if collision_shape.shape == null:
		var shape = CapsuleShape3D.new()
		shape.radius = player_width * 0.5
		shape.height = player_height
		collision_shape.shape = shape
		collision_shape.position = Vector3(0, player_height * 0.5, 0)

func _ensure_model():
	if model_root == null:
		model_root = get_node_or_null("ModelRoot") as Node3D
	if model_root == null:
		model_root = Node3D.new()
		model_root.name = "ModelRoot"
		add_child(model_root)
	_create_blocky_model()

func _create_blocky_model():
	if model_root.get_child_count() > 0:
		return
	var torso = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(0.6, 0.7, 0.35)
	torso.mesh = box
	torso.position = Vector3(0, 0.95, 0)
	torso.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.49, 0.78)
	torso.material_override = mat
	model_root.add_child(torso)
	var head = MeshInstance3D.new()
	var head_box = BoxMesh.new()
	head_box.size = Vector3(0.5, 0.5, 0.5)
	head.mesh = head_box
	head.position = Vector3(0, 1.55, 0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var hmat = StandardMaterial3D.new()
	hmat.albedo_color = Color(0.92, 0.80, 0.62)
	head.material_override = hmat
	model_root.add_child(head)
	for side in [-1, 1]:
		var leg = MeshInstance3D.new()
		var leg_box = BoxMesh.new()
		leg_box.size = Vector3(0.22, 0.6, 0.24)
		leg.mesh = leg_box
		leg.position = Vector3(side * 0.15, 0.3, 0)
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var lmat = StandardMaterial3D.new()
		lmat.albedo_color = Color(0.28, 0.28, 0.32)
		leg.material_override = lmat
		model_root.add_child(leg)
	for side in [-1, 1]:
		var arm = MeshInstance3D.new()
		var arm_box = BoxMesh.new()
		arm_box.size = Vector3(0.2, 0.55, 0.2)
		arm.mesh = arm_box
		arm.position = Vector3(side * 0.4, 0.95, 0)
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var amat = StandardMaterial3D.new()
		amat.albedo_color = Color(0.92, 0.80, 0.62)
		arm.material_override = amat
		model_root.add_child(arm)

func _physics_process(delta):
	if voxel_world == null:
		# attempt late injection via world if available
		if world and world.voxel_model:
			voxel_world = world.voxel_model
		else:
			return
	_handle_movement(delta)

func _handle_movement(delta):
	if not on_ground:
		velocity.y -= gravity * delta

	var input_dir = _get_input_dir()
	var cam_forward = Vector3.ZERO
	var cam_right = Vector3.ZERO
	if camera_rig:
		cam_forward = camera_rig.get_flat_forward()
		cam_right = camera_rig.get_flat_right()
	elif camera_3d:
		var basis = camera_3d.global_transform.basis
		cam_forward = -basis.z
		cam_forward.y = 0
		cam_forward = cam_forward.normalized()
		cam_right = basis.x
		cam_right.y = 0
		cam_right = cam_right.normalized()
	else:
		cam_forward = Vector3(0, 0, -1)
		cam_right = Vector3(1, 0, 0)

	var move_vec = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		move_vec = (cam_right * input_dir.x + cam_forward * input_dir.y)
		move_vec = move_vec.normalized() * move_speed
		if move_vec.length() > 0.1 and model_root:
			var yaw = atan2(move_vec.x, move_vec.z)
			model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, delta * 10.0)

	velocity.x = move_vec.x
	velocity.z = move_vec.z

	# Remove KEY_SPACE auto-repeat, use just pressed only
	if Input.is_action_just_pressed("jump"):
		if on_ground:
			velocity.y = jump_velocity
			on_ground = false

	# Swept collision to prevent tunneling (substeps), includes ceiling handling
	_swept_collision(velocity * delta)

	if velocity.y <= 0.0 and _is_on_ground():
		on_ground = true
		velocity.y = 0.0
	else:
		on_ground = false

	# Clamp world bounds
	global_position.x = clamp(global_position.x, 0.5, world.world_size - 0.5)
	global_position.z = clamp(global_position.z, 0.5, world.world_size - 0.5)

	if global_position.y < -10:
		global_position = voxel_world.get_spawn_position()
		velocity = Vector3.ZERO
		on_ground = false

func _get_input_dir() -> Vector2:
	var x = 0.0
	var y = 0.0
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_D):
		x += 1.0
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_A):
		x -= 1.0
	if Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_W):
		y += 1.0
	if Input.is_action_pressed("move_back") or Input.is_key_pressed(KEY_S):
		y -= 1.0
	var v = Vector2(x, y)
	if v.length() > 1.0:
		v = v.normalized()
	return v

func _swept_collision(motion: Vector3):
	# Substeps for each axis to avoid tunneling, especially vertical fast fall
	var pos = global_position

	# X axis substeps
	if motion.x != 0:
		var steps_x = int(ceil(abs(motion.x) / 0.4)) + 1
		var step_x = motion.x / float(steps_x)
		for _i in range(steps_x):
			var test = pos + Vector3(step_x, 0, 0)
			if _collides_at(test, true):
				velocity.x = 0
				break
			pos.x = test.x
		global_position.x = pos.x

	# Z axis substeps
	if motion.z != 0:
		var steps_z = int(ceil(abs(motion.z) / 0.4)) + 1
		var step_z = motion.z / float(steps_z)
		for _i in range(steps_z):
			var test = pos + Vector3(0, 0, step_z)
			if _collides_at(test, true):
				velocity.z = 0
				break
			pos.z = test.z
		global_position.z = pos.z
		pos = global_position

	# Y swept with tight tolerance so feet hit ground
	if motion.y != 0:
		if motion.y < 0:
			var steps_y = int(ceil(abs(motion.y) / 0.25)) + 1
			var step_y = motion.y / float(steps_y)
			for _i in range(steps_y):
				var test = pos + Vector3(0, step_y, 0)
				var ground = _get_ground_y(test)
				if ground != -9999.0 and test.y <= ground + 0.03 and test.y >= ground - 0.4:
					pos.y = ground
					velocity.y = 0
					break
				if _collides_at(test, false):
					var gy = _get_ground_y(test)
					if gy != -9999.0 and abs(gy - test.y) < 0.15:
						pos.y = gy
					velocity.y = 0
					break
				pos.y = test.y
			global_position.y = pos.y
		else:
			var steps_y = int(ceil(abs(motion.y) / 0.25)) + 1
			var step_y = motion.y / float(steps_y)
			for _i in range(steps_y):
				var test = pos + Vector3(0, step_y, 0)
				if _collides_at(test, false):
					velocity.y = 0
					break
				pos.y = test.y
			global_position.y = pos.y

func _collides_at(pos: Vector3, ignore_ground: bool = true) -> bool:
	if voxel_world == null:
		return false
	var min_x = floor(pos.x - player_width * 0.5)
	var max_x = floor(pos.x + player_width * 0.5)
	var min_y = floor(pos.y)
	var max_y = floor(pos.y + player_height - 0.001)
	var min_z = floor(pos.z - player_width * 0.5)
	var max_z = floor(pos.z + player_width * 0.5)
	for x in range(int(min_x), int(max_x) + 1):
		for y in range(int(min_y), int(max_y) + 1):
			for z in range(int(min_z), int(max_z) + 1):
				if voxel_world.is_solid(Vector3i(x, y, z)):
					if ignore_ground:
						var block_top = float(y) + 1.0
						if block_top <= pos.y + 0.05:
							continue
					return true
	return false

func _get_ground_y(pos: Vector3) -> float:
	if voxel_world == null:
		return -9999.0
	# Tighter tolerances so feet actually hit ground
	var min_x = floor(pos.x - player_width * 0.5 + 0.04)
	var max_x = floor(pos.x + player_width * 0.5 - 0.04)
	var min_z = floor(pos.z - player_width * 0.5 + 0.04)
	var max_z = floor(pos.z + player_width * 0.5 - 0.04)
	var best = -9999.0
	var feet_y = int(floor(pos.y + 0.08))
	for x in range(int(min_x), int(max_x) + 1):
		for z in range(int(min_z), int(max_z) + 1):
			var top = voxel_world.get_highest_top(x, z)
			if top != -9999.0 and top <= pos.y + 0.08 and top >= pos.y - 1.2:
				if top > best:
					best = top
				continue
			for dy in range(0, 6):
				var y = feet_y - dy
				if voxel_world.is_solid(Vector3i(x, y, z)):
					var top2 = float(y) + 1.0
					if top2 <= pos.y + 0.08 and top2 > best:
						best = top2
					break
	return best

func _is_on_ground() -> bool:
	var g = _get_ground_y(global_position)
	if g == -9999.0:
		return false
	# Tight tolerance for feet hitting ground
	return abs(g - global_position.y) < 0.12
