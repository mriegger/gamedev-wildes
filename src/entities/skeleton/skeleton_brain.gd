extends RefCounted
class_name SkeletonBrain

enum State {
	ROAM,
	SEARCH_COVER,
	HIDE,
}

var state: State = State.ROAM

var _definition: SkeletonBehaviorDefinition
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _movement_goal: Vector3 = Vector3.ZERO
var _roam_goal_remaining: float = 0.0

func _init(definition: SkeletonBehaviorDefinition, seed_value: int):
	assert(definition != null)
	_definition = definition
	_rng.seed = seed_value

func advance(delta: float, self_position: Vector3, player_position: Vector3, current_position_hidden: bool):
	if is_player_in_detection_range(self_position, player_position):
		state = State.HIDE if current_position_hidden else State.SEARCH_COVER
		return
	state = State.ROAM
	_roam_goal_remaining = maxf(_roam_goal_remaining - delta, 0.0)
	if _roam_goal_remaining <= 0.0:
		_select_roam_goal(self_position)

func get_movement_goal() -> Vector3:
	return _movement_goal

func is_player_in_detection_range(self_position: Vector3, player_position: Vector3) -> bool:
	var horizontal_offset := Vector2(player_position.x - self_position.x, player_position.z - self_position.z)
	return horizontal_offset.length_squared() <= _definition.detection_range * _definition.detection_range

func reject_movement_goal(self_position: Vector3):
	if state == State.ROAM:
		_select_roam_goal(self_position)

func _select_roam_goal(self_position: Vector3):
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(_definition.roam_radius * 0.35, _definition.roam_radius)
	_movement_goal = self_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
	_roam_goal_remaining = _definition.roam_goal_seconds
