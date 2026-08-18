extends RefCounted
class_name VoxelPlayerVisibilitySensor

const SAMPLE_INTERVAL_SECONDS: float = 0.125
const PHASE_COUNT: int = 8
const MAX_OBSERVER_EYE_HEIGHT: float = 1.4
const PLAYER_TARGET_HEIGHT: float = 0.9

var _voxel_space: VoxelSpace
var _detection_range_squared: float
var _observer_eye_height: float
var _player_visible: bool = false
var _line_of_sight_sampled: bool = false
var _sample_remaining: float = 0.0

func _init(voxel_space: VoxelSpace, detection_range: float, observer_body_height: float, phase_id: int) -> void:
	assert(voxel_space != null)
	assert(is_finite(detection_range) and detection_range > 0.0)
	assert(is_finite(observer_body_height) and observer_body_height > 0.0)
	assert(phase_id >= 0)
	_voxel_space = voxel_space
	_detection_range_squared = detection_range * detection_range
	_observer_eye_height = minf(observer_body_height * 0.8, MAX_OBSERVER_EYE_HEIGHT)
	_sample_remaining = SAMPLE_INTERVAL_SECONDS * float(phase_id % PHASE_COUNT) / float(PHASE_COUNT)

func advance(delta: float, observer_position: Vector3, player_position: Vector3) -> bool:
	assert(is_finite(delta) and delta >= 0.0)
	assert(observer_position.is_finite() and player_position.is_finite())
	_line_of_sight_sampled = false
	_sample_remaining -= delta
	var sample_due := _sample_remaining <= 0.0
	if sample_due:
		_sample_remaining = fposmod(_sample_remaining, SAMPLE_INTERVAL_SECONDS)
		if is_zero_approx(_sample_remaining):
			_sample_remaining = SAMPLE_INTERVAL_SECONDS
	if observer_position.distance_squared_to(player_position) > _detection_range_squared:
		_player_visible = false
		return false
	if not sample_due:
		return _player_visible
	var origin := observer_position + Vector3.UP * _observer_eye_height
	var target := player_position + Vector3.UP * PLAYER_TARGET_HEIGHT
	_line_of_sight_sampled = true
	_player_visible = VoxelLineOfSight.has_clear_path(_voxel_space, origin, target)
	return _player_visible

func did_sample_line_of_sight() -> bool:
	return _line_of_sight_sampled
