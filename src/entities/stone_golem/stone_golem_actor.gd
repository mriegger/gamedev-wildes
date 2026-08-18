extends EntityActor
class_name StoneGolemActor

var brain: StoneGolemBrain

var _behavior: StoneGolemBehaviorDefinition

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
	max_speed = _behavior.movement_speed
	assert(animation_driver is StoneGolemAnimationDriver)

func tick(
	delta: float,
	observation: EntityTargetObservation,
	_separation_velocity: Vector3,
	_navigation_search_budget: NavigationSearchBudget,
) -> void:
	assert(brain != null and voxel_space != null)
	brain.advance(delta, global_position, observation)
	assert(brain.state == StoneGolemBrain.State.DORMANT)
	advance_voxel_motion(delta, Vector3.ZERO, _behavior.gravity)
