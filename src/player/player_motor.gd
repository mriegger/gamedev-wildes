extends Node3D
class_name PlayerMotor

@export_range(0.01, 30.0, 0.01) var move_speed: float = 5.5
@export_range(0.01, 30.0, 0.01) var sprint_speed: float = 8.0
@export_range(0.0, 30.0, 0.01) var jump_velocity: float = 9.0
@export_range(0.01, 1.0, 0.001) var jump_windup_seconds: float = 0.11
@export_range(0.0, 100.0, 0.01) var gravity: float = 30.0
@export_range(0.1, 5.0, 0.01) var player_width: float = 0.6
@export_range(0.1, 10.0, 0.01) var player_height: float = 1.8

@onready var interactor: PlayerInteractor = $Interactor as PlayerInteractor
@onready var targeting_view: TargetingView = $TargetingView as TargetingView
@onready var animation_driver: PlayerAnimationDriver = $AnimationDriver as PlayerAnimationDriver
@onready var model_root: Node3D = $ModelRoot as Node3D
@onready var held_item_view: HeldItemView = $ModelRoot/PlayerVisual/RigRoot/BodySecondary/BodyAction/TorsoBase/RightShoulder/RightArmBase/RightArmAction/RightHandSocket as HeldItemView
@onready var _footsteps: PlayerFootsteps = $Footsteps as PlayerFootsteps
@onready var _action_audio: PlayerActionAudio = $ActionAudio as PlayerActionAudio
@onready var stat_modifier_clock: StatModifierClock = $StatModifierClock as StatModifierClock

var voxel_world: VoxelWorld = null
var camera_rig: CameraRig = null
var _input_buffer: InputBuffer = null
var stats: ActorStats
var _active_item_modifier_instance_id: StringName

var on_ground: bool = false
var is_sprinting: bool = false
var ground_y: float = VoxelWorld.NO_SURFACE_Y
var velocity: Vector3 = Vector3.ZERO
var jump_anticipation: float = 0.0

var _jump_windup_remaining: float = 0.0
var _jump_ready: bool = false

func setup(p_world: WorldController, p_camera_rig: CameraRig, p_inventory: InventoryModel, p_input_buffer: InputBuffer, p_stats: ActorStats):
	voxel_world = p_world.voxel_model
	camera_rig = p_camera_rig
	_input_buffer = p_input_buffer
	stats = p_stats
	stat_modifier_clock.setup(stats)
	interactor.setup(voxel_world, p_camera_rig.camera, self, p_inventory, p_input_buffer)
	targeting_view.setup(p_world, voxel_world, self, interactor)
	animation_driver.setup(self, interactor)
	held_item_view.setup(p_inventory)
	_footsteps.setup(self, animation_driver.animator.profile)
	_action_audio.setup(animation_driver, interactor)
	p_inventory.inventory_changed.connect(_refresh_selected_item_modifiers.bind(p_inventory))
	_refresh_selected_item_modifiers(p_inventory)

func _refresh_selected_item_modifiers(inventory: InventoryModel):
	if not _active_item_modifier_instance_id.is_empty():
		stats.remove_modifiers_from_item_instance(_active_item_modifier_instance_id)
	_active_item_modifier_instance_id = &""
	var item_id = inventory.get_selected_item_id()
	if item_id == null:
		return
	var definition := inventory.item_catalog.get_definition(item_id)
	if definition.stat_modifiers.is_empty():
		return
	_active_item_modifier_instance_id = StringName("hotbar_%d" % inventory.selected_slot)
	assert(stats.replace_item_modifiers(definition.id, _active_item_modifier_instance_id, definition.stat_modifiers))

func _physics_process(delta):
	if voxel_world == null:
		return
	_handle_movement(delta)

func _handle_movement(delta):
	if not on_ground:
		velocity.y -= gravity * delta
		_jump_windup_remaining = 0.0
		_jump_ready = false
		jump_anticipation = 0.0
	var launch_ready = _jump_ready
	_jump_ready = false

	var input_dir = _input_buffer.move_dir
	var move_vec = Vector3.ZERO
	is_sprinting = _input_buffer.sprint_pressed and input_dir != Vector2.ZERO
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
		move_vec = move_vec.normalized() * (sprint_speed if is_sprinting else move_speed)
		if move_vec.length() > 0.1:
			var yaw = atan2(move_vec.x, move_vec.z)
			model_root.rotation.y = lerp_angle(model_root.rotation.y, yaw, delta * 10.0)

	velocity.x = move_vec.x
	velocity.z = move_vec.z

	var ib = _input_buffer
	if ib.consume_jump() and on_ground and _jump_windup_remaining <= 0.0 and not launch_ready:
		_jump_windup_remaining = jump_windup_seconds
	if _jump_windup_remaining > 0.0:
		jump_anticipation = 1.0 - _jump_windup_remaining / jump_windup_seconds
		_jump_windup_remaining -= delta
		if _jump_windup_remaining <= 0.0:
			_jump_windup_remaining = 0.0
			jump_anticipation = 1.0
			_jump_ready = true
	elif not launch_ready:
		jump_anticipation = 0.0

	var motion_result := VoxelBodySolver.sweep(voxel_world, global_position, velocity, velocity * delta, player_width, player_height)
	global_position = motion_result.position
	velocity = motion_result.velocity

	ground_y = VoxelBodySolver.get_ground_y(voxel_world, global_position, player_width)
	if velocity.y <= 0.0 and ground_y != VoxelWorld.NO_SURFACE_Y and abs(ground_y - global_position.y) < 0.12:
		on_ground = true
		velocity.y = 0.0
	else:
		on_ground = false
	if launch_ready:
		if on_ground:
			velocity.y = jump_velocity
			on_ground = false
		jump_anticipation = 0.0

	if global_position.y < -10:
		global_position = voxel_world.get_spawn_position()
		ground_y = VoxelBodySolver.get_ground_y(voxel_world, global_position, player_width)
		velocity = Vector3.ZERO
		on_ground = false
		_jump_windup_remaining = 0.0
		_jump_ready = false
		jump_anticipation = 0.0
