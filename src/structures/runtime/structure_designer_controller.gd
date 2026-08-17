extends Node3D
class_name StructureDesignerController

const REACH: float = 6.0
const MAX_PITCH_RADIANS: float = deg_to_rad(89.0)

@export_range(0.01, 30.0, 0.01) var move_speed: float = 6.0
@export_range(0.01, 60.0, 0.01) var accelerated_speed: float = 14.0
@export_range(0.01, 1.0, 0.01) var mouse_sensitivity: float = 0.12
@export_range(0.1, 5.0, 0.01) var body_width: float = 0.6
@export_range(0.1, 10.0, 0.01) var body_height: float = 1.8

@onready var pitch: Node3D = $Pitch as Node3D
@onready var camera: Camera3D = $Pitch/Camera3D as Camera3D

var velocity: Vector3 = Vector3.ZERO

var _voxel_space: VoxelSpace
var _input_enabled: bool = false
var _mouse_capture_enabled: bool = true

func _ready() -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)

func setup(voxel_space: VoxelSpace) -> void:
	assert(is_node_ready())
	assert(voxel_space != null)
	assert(_voxel_space == null)
	_voxel_space = voxel_space
	reset_to_spawn()

func reset_to_spawn() -> void:
	assert(_voxel_space != null)
	global_position = _voxel_space.get_spawn_position()
	velocity = Vector3.ZERO

func set_camera_active(active: bool) -> void:
	camera.current = active

func set_input_enabled(enabled: bool) -> void:
	_input_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
	set_physics_process(enabled)
	set_process_unhandled_input(enabled)
	_apply_mouse_mode()

func set_mouse_capture_enabled(enabled: bool) -> void:
	_mouse_capture_enabled = enabled
	_apply_mouse_mode()

func get_centered_raycast() -> VoxelRaycastHit:
	if _voxel_space == null:
		return null
	return VoxelRaycast.cast(_voxel_space, camera.global_position, -camera.global_transform.basis.z, REACH)

func body_intersects_cell(cell: Vector3i) -> bool:
	var body_min := Vector3(
		global_position.x - body_width * 0.5,
		global_position.y,
		global_position.z - body_width * 0.5,
	)
	var body_max := Vector3(
		global_position.x + body_width * 0.5,
		global_position.y + body_height,
		global_position.z + body_width * 0.5,
	)
	var cell_min := Vector3(cell)
	var cell_max := cell_min + Vector3.ONE
	if body_max.x <= cell_min.x or body_min.x >= cell_max.x:
		return false
	if body_max.y <= cell_min.y or body_min.y >= cell_max.y:
		return false
	if body_max.z <= cell_min.z or body_min.z >= cell_max.z:
		return false
	return true

func apply_flight_input(move_input: Vector2, vertical_input: float, accelerated: bool, delta: float) -> void:
	assert(_voxel_space != null)
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var movement := right * move_input.x + forward * -move_input.y + Vector3.UP * vertical_input
	if movement.length_squared() > 1.0:
		movement = movement.normalized()
	var speed := accelerated_speed if accelerated else move_speed
	velocity = movement * speed
	var result := VoxelBodySolver.sweep(
		_voxel_space,
		global_position,
		velocity,
		velocity * delta,
		body_width,
		body_height,
	)
	global_position = result.position
	velocity = result.velocity

func apply_mouse_look(relative_motion: Vector2) -> void:
	rotation.y = wrapf(rotation.y - deg_to_rad(relative_motion.x * mouse_sensitivity), -PI, PI)
	pitch.rotation.x = clampf(
		pitch.rotation.x - deg_to_rad(relative_motion.y * mouse_sensitivity),
		-MAX_PITCH_RADIANS,
		MAX_PITCH_RADIANS,
	)

func _physics_process(delta: float) -> void:
	if _voxel_space == null:
		return
	var move_input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	var vertical_input := Input.get_action_strength(&"jump") - Input.get_action_strength(&"structure_designer_descend")
	apply_flight_input(move_input, vertical_input, Input.is_action_pressed(&"sprint"), delta)

func _unhandled_input(event: InputEvent) -> void:
	if not _input_enabled or not _mouse_capture_enabled:
		return
	if event is InputEventMouseMotion:
		apply_mouse_look((event as InputEventMouseMotion).relative)
		get_viewport().set_input_as_handled()

func _apply_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _input_enabled and _mouse_capture_enabled else Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and _input_enabled and _mouse_capture_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
