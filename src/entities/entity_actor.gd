extends Node3D
class_name EntityActor

signal melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile)

@export_node_path("Node") var animation_driver_path: NodePath
@export_node_path("Node") var visual_fader_path: NodePath

@onready var model_root: Node3D = $ModelRoot as Node3D

var runtime_id: int = -1
var definition: EntityDefinition
var voxel_world: VoxelWorld
var velocity: Vector3 = Vector3.ZERO
var on_ground: bool = true
var max_speed: float = 1.0
var animation_driver: EntityAnimationDriver
var visual_fader: EntityVisualFader

func _ready():
	set_process(false)

func setup(p_runtime_id: int, p_definition: EntityDefinition, p_voxel_world: VoxelWorld, _behavior_seed: int):
	assert(p_runtime_id >= 0)
	assert(p_definition != null)
	assert(p_voxel_world != null)
	runtime_id = p_runtime_id
	definition = p_definition
	voxel_world = p_voxel_world
	animation_driver = get_node(animation_driver_path) as EntityAnimationDriver
	visual_fader = get_node(visual_fader_path) as EntityVisualFader
	assert(animation_driver != null)
	assert(visual_fader != null)
	animation_driver.setup(self)
	visual_fader.setup(model_root)
	set_process(true)

func tick(_delta: float, _player_position: Vector3, _separation_velocity: Vector3, _navigation_search_budget: NavigationSearchBudget):
	assert(false)

func supports_behavior(_behavior: EntityBehaviorDefinition) -> bool:
	return false

func has_valid_presentation() -> bool:
	if animation_driver_path.is_empty() or visual_fader_path.is_empty():
		return false
	var visual_root := get_node_or_null(^"ModelRoot") as Node3D
	var candidate_animation_driver := get_node_or_null(animation_driver_path) as EntityAnimationDriver
	var candidate_visual_fader := get_node_or_null(visual_fader_path) as EntityVisualFader
	return (
		visual_root != null
		and candidate_animation_driver != null
		and candidate_visual_fader != null
		and candidate_visual_fader.can_fade(visual_root)
	)

func _process(delta: float):
	animation_driver.advance(delta)

func advance_visual_fade(delta: float) -> bool:
	assert(visual_fader != null)
	return visual_fader.advance(delta)

func begin_despawn_fade():
	assert(visual_fader != null)
	set_process(false)
	visual_fader.begin_fade_out()

func get_visual_opacity() -> float:
	assert(visual_fader != null)
	return visual_fader.get_opacity()

func play_attack(duration: float):
	animation_driver.play_attack(duration)

func play_hit(local_hit_direction: Vector3):
	animation_driver.play_hit(local_hit_direction)

func record_melee_contact(world_hit_direction: Vector3):
	assert(world_hit_direction.is_finite() and not world_hit_direction.is_zero_approx())
	var model_basis := model_root.global_transform.basis.orthonormalized()
	play_hit(model_basis.inverse() * world_hit_direction)

func apply_path_follow_result(result: VoxelPathFollowResult, delta: float, jump_velocity: float) -> Vector3:
	if result.should_jump:
		velocity.y = jump_velocity
	if result.desired_velocity.is_zero_approx():
		return Vector3.ZERO
	var direction := result.desired_velocity.normalized()
	var target_yaw := atan2(direction.x, direction.z)
	model_root.rotation.y = lerp_angle(model_root.rotation.y, target_yaw, minf(delta * 8.0, 1.0))
	return result.desired_velocity

func limit_planar_velocity(desired_velocity: Vector3, speed_limit: float) -> Vector3:
	var planar_velocity := Vector2(desired_velocity.x, desired_velocity.z)
	if planar_velocity.length() <= speed_limit:
		return desired_velocity
	planar_velocity = planar_velocity.normalized() * speed_limit
	desired_velocity.x = planar_velocity.x
	desired_velocity.z = planar_velocity.y
	return desired_velocity

func advance_voxel_motion(delta: float, desired_velocity: Vector3, gravity: float):
	velocity.x = desired_velocity.x
	velocity.z = desired_velocity.z
	if not on_ground:
		velocity.y -= gravity * delta
	var result := VoxelBodySolver.sweep(voxel_world, global_position, velocity, velocity * delta, definition.body_width, definition.body_height)
	global_position = result.position
	velocity = result.velocity
	var ground_y := VoxelBodySolver.get_ground_y(voxel_world, global_position, definition.body_width)
	on_ground = velocity.y <= 0.0 and ground_y != VoxelWorld.NO_SURFACE_Y and absf(ground_y - global_position.y) < 0.12
	if on_ground:
		velocity.y = 0.0

func get_world_bounds() -> AABB:
	assert(definition != null)
	var half_width := definition.body_width * 0.5
	return AABB(
		global_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(definition.body_width, definition.body_height, definition.body_width)
	)
