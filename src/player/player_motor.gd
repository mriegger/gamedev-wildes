extends Node3D
class_name PlayerMotor

@export var move_speed: float = 5.5
@export var jump_velocity: float = 9.0
@export var gravity: float = 20.0
@export var player_width: float = 0.6
@export var player_height: float = 1.8

@onready var interactor: PlayerInteractor = $Interactor as PlayerInteractor
@onready var targeting_view: TargetingView = $TargetingView as TargetingView

var voxel_world: VoxelWorld = null
var camera_rig: CameraRig = null
var _input_buffer: InputBuffer = null

var on_ground: bool = false
var ground_y: float = VoxelWorld.NO_SURFACE_Y
var velocity: Vector3 = Vector3.ZERO
var model_root: Node3D

func setup(p_world: WorldController, p_camera_rig: CameraRig, p_inventory: InventoryModel, p_input_buffer: InputBuffer):
	voxel_world = p_world.voxel_model
	camera_rig = p_camera_rig
	_input_buffer = p_input_buffer
	interactor.setup(voxel_world, p_camera_rig.camera, self, p_inventory, p_input_buffer)
	targeting_view.setup(p_world, voxel_world, self, interactor)

func _ready():
	_ensure_model()

func _ensure_model():
	if model_root == null:
		var existing = get_node_or_null("ModelRoot") as Node3D
		if existing != null:
			model_root = existing
		else:
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
		return
	_handle_movement(delta)

func _handle_movement(delta):
	if not on_ground:
		velocity.y -= gravity * delta

	var input_dir = _input_buffer.move_dir
	var move_vec = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		var camera_basis = camera_rig.get_camera_basis()
		var cam_forward = -camera_basis.z
		cam_forward.y = 0
		if cam_forward.length_squared() < 0.0001:
			cam_forward = Vector3(0, 0, -1)
		else:
			cam_forward = cam_forward.normalized()
		var cam_right = camera_basis.x
		cam_right.y = 0
		if cam_right.length_squared() < 0.0001:
			cam_right = Vector3(1, 0, 0)
		else:
			cam_right = cam_right.normalized()
		move_vec = (cam_right * input_dir.x + cam_forward * input_dir.y)
		move_vec = move_vec.normalized() * move_speed
		if move_vec.length() > 0.1 and model_root:
			var yaw = atan2(move_vec.x, move_vec.z)
			model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, delta * 10.0)

	velocity.x = move_vec.x
	velocity.z = move_vec.z

	var ib = _input_buffer
	if ib.consume_jump():
		if on_ground:
			velocity.y = jump_velocity
			on_ground = false

	_swept_collision(velocity * delta)

	ground_y = _get_ground_y(global_position)
	if velocity.y <= 0.0 and ground_y != VoxelWorld.NO_SURFACE_Y and abs(ground_y - global_position.y) < 0.12:
		on_ground = true
		velocity.y = 0.0
	else:
		on_ground = false

	if global_position.y < -10:
		global_position = voxel_world.get_spawn_position()
		ground_y = _get_ground_y(global_position)
		velocity = Vector3.ZERO
		on_ground = false

func _swept_collision(motion: Vector3):
	var pos = global_position

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

	if motion.y != 0:
		if motion.y < 0:
			var steps_y = int(ceil(abs(motion.y) / 0.25)) + 1
			var step_y = motion.y / float(steps_y)
			for _i in range(steps_y):
				var test = pos + Vector3(0, step_y, 0)
				var ground = _get_ground_y(test)
				if ground != VoxelWorld.NO_SURFACE_Y and test.y <= ground + 0.03 and test.y >= ground - 0.4:
					pos.y = ground
					velocity.y = 0
					break
				if _collides_at(test, false):
					var gy = _get_ground_y(test)
					if gy != VoxelWorld.NO_SURFACE_Y and abs(gy - test.y) < 0.15:
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

func _collides_at(pos: Vector3, ignore_ground: bool) -> bool:
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
		return VoxelWorld.NO_SURFACE_Y
	var min_x = floor(pos.x - player_width * 0.5 + 0.04)
	var max_x = floor(pos.x + player_width * 0.5 - 0.04)
	var min_z = floor(pos.z - player_width * 0.5 + 0.04)
	var max_z = floor(pos.z + player_width * 0.5 - 0.04)
	var best = VoxelWorld.NO_SURFACE_Y
	var feet_y = int(floor(pos.y + 0.08))
	for x in range(int(min_x), int(max_x) + 1):
		for z in range(int(min_z), int(max_z) + 1):
			var top = voxel_world.get_highest_top(x, z)
			if top != VoxelWorld.NO_SURFACE_Y and top <= pos.y + 0.08 and top >= pos.y - 1.2:
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
