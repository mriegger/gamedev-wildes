extends RefCounted
class_name StoneGolemBrain

const StoneGolemBehaviorDefinitionType := preload("res://entities/stone_golem/stone_golem_behavior_definition.gd")
const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")

enum State {
	DORMANT,
}

var state: State = State.DORMANT

func _init(definition: StoneGolemBehaviorDefinitionType) -> void:
	assert(definition != null)
	assert(StoneGolemBehaviorDefinitionType.is_valid_gravity(definition.gravity))

func advance(delta: float, self_position: Vector3, observation: EntityTargetObservationType) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	assert(self_position.is_finite())
	assert(observation != null and observation.validate())
