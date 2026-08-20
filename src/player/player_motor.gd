extends Node3D
class_name PlayerMotor

const _TURN_RESPONSE: float = 10.0

signal water_step_committed(position: Vector3, planar_velocity: Vector2)
signal jump_committed

@export_range(0.01, 30.0, 0.01) var move_speed: float = 5.5
@export_range(0.01, 30.0, 0.01) var sprint_speed: float = 8.0
@export_range(0.01, 30.0, 0.01) var jump_velocity: float = 9.0
@export_range(0.01, 1.0, 0.001) var jump_windup_seconds: float = 0.11
@export_range(0.0, 100.0, 0.01) var gravity: float = 30.0
@export_range(0.1, 5.0, 0.01) var player_width: float = 0.6
@export_range(0.1, 10.0, 0.01) var player_height: float = 1.8

@onready var interactor: PlayerInteractor = $Interactor as PlayerInteractor
@onready var targeting_view: TargetingView = $TargetingView as TargetingView
@onready var animation_driver: PlayerAnimationDriver = $AnimationDriver as PlayerAnimationDriver
@onready var model_root: Node3D = $ModelRoot as Node3D
@onready var slime_attachment_anchors: Array[Marker3D] = [
	$ModelRoot/SlimeAttachmentAnchors/Left as Marker3D,
	$ModelRoot/SlimeAttachmentAnchors/Right as Marker3D,
	$ModelRoot/SlimeAttachmentAnchors/Back as Marker3D,
	$ModelRoot/SlimeAttachmentAnchors/Front as Marker3D,
]
@onready var held_item_view: HeldItemView = $ModelRoot/PlayerVisual/RigRoot/BodySecondary/BodyAction/TorsoBase/RightShoulder/RightArmBase/RightArmAction/RightHandSocket as HeldItemView
@onready var _footsteps: PlayerFootsteps = $Footsteps as PlayerFootsteps
@onready var _action_audio: PlayerActionAudio = $ActionAudio as PlayerActionAudio
@onready var _hammer_shockwave: HammerShockwaveView = $HammerShockwave as HammerShockwaveView
@onready var _sword_swing_arc: SwordSwingArcView = $SwordSwingArc as SwordSwingArcView
@onready var bow_draw_progress_bar: BowDrawProgressBar3D = $BowDrawProgress as BowDrawProgressBar3D
@onready var armor_view: PlayerArmorView = $ModelRoot/PlayerVisual/ArmorView as PlayerArmorView
@onready var stat_modifier_clock: StatModifierClock = $StatModifierClock as StatModifierClock

var voxel_space: VoxelSpace = null
var camera_rig: CameraRig = null
var _input_buffer: InputBuffer = null
var stats: ActorStats
var _inventory_model: InventoryModel = null
var _respawn_position: Vector3 = Vector3.ZERO
var _is_setup: bool = false

var on_ground: bool = false
var is_sprinting: bool = false
var ground_y: float = VoxelSpace.NO_SURFACE_Y
var velocity: Vector3 = Vector3.ZERO
var jump_anticipation: float = 0.0

var _jump_windup_remaining: float = 0.0
var _jump_ready: bool = false
var _defeated: bool = false

func setup(
	p_camera_rig: CameraRig,
	p_inventory: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_action_executors: PlayerActionExecutors,
	p_input_buffer: InputBuffer,
	p_stats: ActorStats,
	p_combat: MeleeCombatCoordinator,
	p_entity_runtime: EntityRuntime,
	p_block_interaction_handler: Callable = Callable(),
	p_block_break_validator: Callable = Callable(),
):
	assert(p_camera_rig != null)
	assert(p_inventory != null)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory)
	assert(p_action_executors != null)
	assert(p_input_buffer != null)
	assert(p_stats != null)
	assert(p_stats.has_stat(&"movement_speed_multiplier"))
	assert(p_inventory_loadout.actor_stats == p_stats)
	assert(p_combat != null)
	assert(p_entity_runtime != null)
	if _is_setup:
		assert(camera_rig == p_camera_rig)
		assert(_inventory_model == p_inventory)
		assert(interactor.action_executors == p_action_executors)
		assert(_input_buffer == p_input_buffer)
		assert(stats == p_stats)
		assert(interactor.combat == p_combat)
		assert(interactor.entity_runtime == p_entity_runtime)
		return
	camera_rig = p_camera_rig
	_inventory_model = p_inventory
	_input_buffer = p_input_buffer
	stats = p_stats
	stat_modifier_clock.setup(stats)
	interactor.setup(
		p_camera_rig.camera,
		self,
		p_inventory,
		p_inventory_loadout,
		p_action_executors,
		p_input_buffer,
		p_combat,
		p_entity_runtime,
		p_block_interaction_handler,
		p_block_break_validator,
	)
	targeting_view.setup(self, interactor)
	animation_driver.setup(self, interactor)
	held_item_view.setup(p_inventory)
	_footsteps.setup(self, animation_driver.animator.profile)
	_footsteps.step_committed.connect(_on_step_committed)
	_action_audio.setup(animation_driver, interactor, p_inventory, p_combat)
	_hammer_shockwave.setup(interactor, p_camera_rig)
	_sword_swing_arc.setup(interactor, self)
	bow_draw_progress_bar.set_body_height(player_height)
	armor_view.setup(p_inventory)
	_is_setup = true

func bind_entity_runtime(p_entity_runtime: EntityRuntime) -> void:
	assert(_is_setup)
	interactor.bind_entity_runtime(p_entity_runtime)

func setup_harvesting(harvest_coordinator: HarvestCoordinator) -> void:
	assert(_is_setup and harvest_coordinator != null)
	interactor.setup_harvesting(harvest_coordinator)
	_action_audio.setup_harvesting(harvest_coordinator)

func setup_consumption(consumption_coordinator: ItemConsumptionCoordinator) -> void:
	assert(_is_setup and consumption_coordinator != null)
	interactor.setup_consumption(consumption_coordinator)
	_action_audio.setup_consumption(consumption_coordinator)

func setup_projectiles(projectile_runtime: ArrowProjectileRuntime) -> void:
	assert(_is_setup and projectile_runtime != null)
	interactor.setup_projectiles(projectile_runtime)

func get_facing_direction() -> Vector3:
	var forward := model_root.global_transform.basis.z
	forward.y = 0.0
	return Vector3.BACK if forward.is_zero_approx() else forward.normalized()

func bind_space(p_space: VoxelSpace, presentation_root: Node, spawn_position: Vector3, editable_voxel_world: VoxelWorld = null):
	assert(_is_setup)
	assert(p_space != null)
	assert(presentation_root != null)
	assert(editable_voxel_world == null or editable_voxel_world == p_space)
	voxel_space = p_space
	_respawn_position = spawn_position
	velocity = Vector3.ZERO
	on_ground = false
	ground_y = VoxelSpace.NO_SURFACE_Y
	_jump_windup_remaining = 0.0
	_jump_ready = false
	jump_anticipation = 0.0
	interactor.bind_space(p_space, editable_voxel_world)
	targeting_view.bind_space(p_space, presentation_root)

func unbind_space():
	if voxel_space == null:
		return
	interactor.unbind_space()
	targeting_view.unbind_space()
	voxel_space = null
	velocity = Vector3.ZERO
	on_ground = false
	ground_y = VoxelSpace.NO_SURFACE_Y
	_jump_windup_remaining = 0.0
	_jump_ready = false
	jump_anticipation = 0.0
	if _input_buffer != null:
		_input_buffer.clear_gameplay()

func respawn_at(spawn_position: Vector3):
	assert(spawn_position.is_finite())
	assert(stats != null and stats.has_stat(&"hp"))
	assert(_input_buffer != null)
	_reset_motion_at(spawn_position)
	is_sprinting = false
	interactor.cancel_actions()
	_input_buffer.clear_gameplay()
	var health_restored := stats.set_current_hp(stats.get_value(&"hp"))
	assert(health_restored)
	_defeated = false

func enter_defeated_state():
	assert(_input_buffer != null)
	assert(stats != null and stats.is_dead())
	if _defeated:
		return
	_defeated = true
	velocity = Vector3.ZERO
	is_sprinting = false
	_jump_windup_remaining = 0.0
	_jump_ready = false
	jump_anticipation = 0.0
	interactor.cancel_actions()
	_input_buffer.clear_gameplay()

func is_defeated() -> bool:
	return _defeated

func _reset_motion_at(position: Vector3):
	global_position = position
	velocity = Vector3.ZERO
	ground_y = VoxelBodySolver.get_ground_y(voxel_space, global_position, player_width)
	on_ground = false
	_jump_windup_remaining = 0.0
	_jump_ready = false
	jump_anticipation = 0.0

func _physics_process(delta):
	if voxel_space == null or _defeated:
		return
	_handle_movement(delta)

func is_in_water() -> bool:
	if voxel_space == null:
		return false
	return voxel_space.get_block_id_at(_get_feet_cell()) == BlockId.Type.WATER

func get_footstep_surface_block_id() -> int:
	if voxel_space == null:
		return BlockId.Type.AIR
	if is_in_water():
		return BlockId.Type.WATER
	if not on_ground:
		return BlockId.Type.AIR
	return VoxelBodySolver.get_supporting_block_id(voxel_space, global_position, player_width, ground_y)

func get_water_surface_position() -> Vector3:
	assert(is_in_water())
	var surface_cell := _get_feet_cell()
	while voxel_space.get_block_id_at(surface_cell + Vector3i.UP) == BlockId.Type.WATER:
		surface_cell += Vector3i.UP
	return Vector3(global_position.x, surface_cell.y + VoxelSpace.WATER_SURFACE_HEIGHT, global_position.z)

func get_world_bounds() -> AABB:
	var half_width := player_width * 0.5
	return AABB(
		global_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(player_width, player_height, player_width),
	)

func get_slime_attachment_anchor_count() -> int:
	return slime_attachment_anchors.size()

func get_slime_attachment_anchor_position(slot_index: int) -> Vector3:
	assert(slot_index >= 0 and slot_index < slime_attachment_anchors.size())
	return slime_attachment_anchors[slot_index].global_position

func get_movement_speed_multiplier() -> float:
	assert(stats != null and stats.has_stat(&"movement_speed_multiplier"))
	return stats.get_value(&"movement_speed_multiplier")

func get_effective_move_speed() -> float:
	return move_speed * get_movement_speed_multiplier()

func get_effective_sprint_speed() -> float:
	return sprint_speed * get_movement_speed_multiplier()

func get_locomotion_speed_ratio() -> float:
	var configured_speed := sprint_speed if is_sprinting else move_speed
	return clampf(Vector2(velocity.x, velocity.z).length() / configured_speed, 0.0, 1.0)

func _on_step_committed(surface_block_id: int) -> void:
	if surface_block_id == BlockId.Type.WATER and is_in_water():
		water_step_committed.emit(get_water_surface_position(), Vector2(velocity.x, velocity.z))

func _get_feet_cell() -> Vector3i:
	return Vector3i(
		floori(global_position.x),
		floori(global_position.y + 0.05),
		floori(global_position.z)
	)

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
		move_vec = move_vec.normalized() * (get_effective_sprint_speed() if is_sprinting else get_effective_move_speed())
		if move_vec.length() > 0.1:
			_turn_toward_movement(move_vec, delta)

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

	var motion_result := VoxelBodySolver.sweep(voxel_space, global_position, velocity, velocity * delta, player_width, player_height)
	global_position = motion_result.position
	velocity = motion_result.velocity

	ground_y = VoxelBodySolver.get_ground_y(voxel_space, global_position, player_width)
	if velocity.y <= 0.0 and ground_y != VoxelSpace.NO_SURFACE_Y and abs(ground_y - global_position.y) < 0.12:
		on_ground = true
		velocity.y = 0.0
	else:
		on_ground = false
	if launch_ready:
		if on_ground and is_finite(jump_velocity) and jump_velocity > 0.0:
			velocity.y = jump_velocity
			on_ground = false
			jump_committed.emit()
		jump_anticipation = 0.0

	if global_position.y < -10:
		_reset_motion_at(_respawn_position)

func face_direction(world_direction: Vector3):
	assert(world_direction.is_finite())
	var planar_direction := Vector3(world_direction.x, 0.0, world_direction.z)
	if planar_direction.is_zero_approx():
		return
	planar_direction = planar_direction.normalized()
	model_root.rotation.y = atan2(planar_direction.x, planar_direction.z)

func turn_toward_direction(world_direction: Vector3, delta: float):
	assert(world_direction.is_finite())
	assert(is_finite(delta) and delta >= 0.0)
	var planar_direction := Vector3(world_direction.x, 0.0, world_direction.z)
	if planar_direction.is_zero_approx():
		return
	planar_direction = planar_direction.normalized()
	var target_yaw := atan2(planar_direction.x, planar_direction.z)
	var turn_weight := 1.0 - exp(-_TURN_RESPONSE * delta)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, target_yaw, turn_weight)

func _turn_toward_movement(world_direction: Vector3, delta: float):
	if _selected_action_locks_cursor_facing():
		return
	turn_toward_direction(world_direction, delta)

func _selected_action_locks_cursor_facing() -> bool:
	if _inventory_model == null:
		return false
	var selected_item_id = _inventory_model.get_selected_item_id()
	if selected_item_id == null:
		return false
	var action := _inventory_model.item_catalog.get_definition(selected_item_id).primary_action
	if action is MeleeAttackActionDefinition:
		return not is_sprinting
	return action is BowDrawActionDefinition and interactor.is_drawing_bow()
