extends EntityActor
class_name StoneGolemActor

const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")

var brain: StoneGolemBrain

var _behavior: StoneGolemBehaviorDefinition
var _stone_golem_animation: StoneGolemAnimationDriver
var _visibility_sensor: VoxelPlayerVisibilitySensorType

func supports_behavior(behavior: EntityBehaviorDefinition) -> bool:
	return behavior is StoneGolemBehaviorDefinition

func setup(
	p_runtime_id: int,
	p_definition: EntityDefinition,
	p_voxel_space: VoxelSpace,
	behavior_seed: int,
	navigation_limits: EntityNavigationLimits,
) -> void:
	super.setup(p_runtime_id, p_definition, p_voxel_space, behavior_seed, navigation_limits)
	_behavior = p_definition.behavior as StoneGolemBehaviorDefinition
	assert(_behavior != null)
	brain = StoneGolemBrain.new(_behavior)
	_stone_golem_animation = animation_driver as StoneGolemAnimationDriver
	assert(_stone_golem_animation != null)
	_visibility_sensor = VoxelPlayerVisibilitySensorType.new(voxel_space, _behavior.detection_range, definition.body_height, runtime_id)

func tick(
	delta: float,
	observation: EntityTargetObservation,
	_separation_velocity: Vector3,
	_navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	assert(observation != null and observation.validate())
	var player_visible := _visibility_sensor.advance(delta, global_position, observation.player_position)
	brain.advance(delta, global_position, observation, player_visible)
	_stone_golem_animation.set_alerted(brain.is_alerted())
	advance_voxel_motion(delta, Vector3.ZERO, _behavior.gravity)
