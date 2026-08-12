extends EntityAnimationDriver
class_name SheepAnimationDriver

const IDLE: StringName = &"Idle"
const WALK: StringName = &"Walk"
const FLEE: StringName = &"Flee"
const HIT: StringName = &"Hit"
const DEATH: StringName = &"Death"
const HIT_SECONDS: float = 0.2
const DEATH_SECONDS: float = 0.6
const WALK_CYCLE_SECONDS: float = 0.64
const FLEE_CYCLE_SECONDS: float = 0.34

var _visual: Node3D
var _rig_root: Node3D
var _body_pivot: Node3D
var _head_pivot: Node3D
var _left_ear_pivot: Node3D
var _right_ear_pivot: Node3D
var _tail_pivot: Node3D
var _leg_pivots: Array[Node3D] = []
var _leg_origins: Array[Vector3] = []
var _animation_state: ActorAnimationState = ActorAnimationState.new()
var _current_state: StringName = IDLE
var _fleeing: bool = false
var _elapsed: float = 0.0
var _gait_phase: float = 0.0
var _hit_elapsed: float = HIT_SECONDS
var _hit_direction: Vector3 = Vector3.BACK
var _dying: bool = false
var _death_elapsed: float = 0.0
var _previous_yaw: float = 0.0
var _rig_origin_position: Vector3
var _rig_origin_rotation: Vector3
var _body_origin_position: Vector3
var _body_origin_rotation: Vector3
var _body_origin_scale: Vector3
var _head_origin_rotation: Vector3
var _left_ear_origin_rotation: Vector3
var _right_ear_origin_rotation: Vector3
var _tail_origin_rotation: Vector3

func setup(p_actor: Node3D):
	super.setup(p_actor)
	_visual = get_parent() as Node3D
	assert(_visual != null)
	_rig_root = _visual.get_node(^"RigRoot") as Node3D
	_body_pivot = _rig_root.get_node(^"BodyPivot") as Node3D
	_head_pivot = _body_pivot.get_node(^"HeadAnchor/HeadPivot") as Node3D
	_left_ear_pivot = _head_pivot.get_node(^"LeftEarPivot") as Node3D
	_right_ear_pivot = _head_pivot.get_node(^"RightEarPivot") as Node3D
	_tail_pivot = _body_pivot.get_node(^"TailPivot") as Node3D
	_leg_pivots.assign([
		_rig_root.get_node(^"FrontLeftHip/LegPivot") as Node3D,
		_rig_root.get_node(^"FrontRightHip/LegPivot") as Node3D,
		_rig_root.get_node(^"RearLeftHip/LegPivot") as Node3D,
		_rig_root.get_node(^"RearRightHip/LegPivot") as Node3D,
	])
	_rig_origin_position = _rig_root.position
	_rig_origin_rotation = _rig_root.rotation
	_body_origin_position = _body_pivot.position
	_body_origin_rotation = _body_pivot.rotation
	_body_origin_scale = _body_pivot.scale
	_head_origin_rotation = _head_pivot.rotation
	_left_ear_origin_rotation = _left_ear_pivot.rotation
	_right_ear_origin_rotation = _right_ear_pivot.rotation
	_tail_origin_rotation = _tail_pivot.rotation
	for leg_pivot in _leg_pivots:
		_leg_origins.append(leg_pivot.rotation)
	_previous_yaw = model_root.rotation.y
	_animation_state.grounded = actor.get(&"on_ground") as bool

func set_fleeing(active: bool):
	_fleeing = active

func play_hit(local_hit_direction: Vector3 = Vector3.BACK):
	if _dying:
		return
	_hit_direction = local_hit_direction.normalized() if not local_hit_direction.is_zero_approx() else Vector3.BACK
	_hit_elapsed = 0.0

func play_death():
	_dying = true
	_death_elapsed = 0.0
	_fleeing = false
	_hit_elapsed = HIT_SECONDS
	_current_state = DEATH

func is_death_complete() -> bool:
	return _dying and _death_elapsed >= DEATH_SECONDS

func get_death_time_remaining() -> float:
	assert(_dying)
	return maxf(DEATH_SECONDS - _death_elapsed, 0.0)

func advance(delta: float):
	assert(actor != null and _visual != null)
	_elapsed += delta
	_reset_pose()
	if _dying:
		_death_elapsed = minf(_death_elapsed + delta, DEATH_SECONDS)
		_apply_death_pose()
		_current_state = DEATH
		return
	var world_velocity: Vector3 = actor.get(&"velocity")
	var model_basis := model_root.global_transform.basis.orthonormalized()
	var local_velocity := model_basis.inverse() * world_velocity
	var planar_speed := Vector2(world_velocity.x, world_velocity.z).length()
	var max_speed: float = actor.get(&"max_speed")
	var speed_ratio := clampf(planar_speed / maxf(max_speed, 0.001), 0.0, 1.0)
	var current_yaw := model_root.rotation.y
	var turn_rate := wrapf(current_yaw - _previous_yaw, -PI, PI) / maxf(delta, 0.0001)
	_previous_yaw = current_yaw
	var grounded: bool = actor.get(&"on_ground")
	_animation_state.set_motion(local_velocity, speed_ratio, _fleeing, grounded, 0.0, turn_rate, false, Vector3.ZERO)
	_advance_hit(delta)
	_advance_gait(delta, speed_ratio)
	_apply_body_pose(speed_ratio)
	_apply_leg_pose(speed_ratio)
	_apply_head_pose(speed_ratio)
	_apply_hit_pose()
	_select_state(planar_speed)

func get_current_state() -> StringName:
	return _current_state

func _advance_hit(delta: float):
	if _hit_elapsed < HIT_SECONDS:
		_hit_elapsed = minf(_hit_elapsed + delta, HIT_SECONDS)

func _advance_gait(delta: float, speed_ratio: float):
	if not _animation_state.grounded or speed_ratio <= 0.01:
		return
	var cycle_seconds := FLEE_CYCLE_SECONDS if _fleeing else WALK_CYCLE_SECONDS
	_gait_phase = fmod(_gait_phase + delta * TAU / cycle_seconds * speed_ratio, TAU)

func _apply_body_pose(speed_ratio: float):
	if not _animation_state.grounded:
		_body_pivot.rotation.x = _body_origin_rotation.x - deg_to_rad(7.0)
		return
	if speed_ratio <= 0.01:
		var breath := sin(_elapsed * TAU / 2.6)
		_body_pivot.position.y = _body_origin_position.y + breath * 0.012
		_body_pivot.rotation.z = _body_origin_rotation.z + deg_to_rad(1.5) * breath
		_body_pivot.scale = _body_origin_scale * Vector3(1.0 - breath * 0.008, 1.0 + breath * 0.012, 1.0 - breath * 0.008)
		return
	var stride := sin(_gait_phase)
	var bounce := absf(stride)
	var bounce_height := 0.085 if _fleeing else 0.035
	var pitch_degrees := 7.0 if _fleeing else 3.0
	_body_pivot.position.y = _body_origin_position.y + bounce * bounce_height * speed_ratio
	_body_pivot.rotation.x = _body_origin_rotation.x + deg_to_rad(pitch_degrees) * stride * speed_ratio
	_body_pivot.rotation.z = _body_origin_rotation.z + deg_to_rad(2.5) * cos(_gait_phase) * speed_ratio

func _apply_leg_pose(speed_ratio: float):
	if not _animation_state.grounded:
		for index in _leg_pivots.size():
			_leg_pivots[index].rotation.x = _leg_origins[index].x - deg_to_rad(20.0)
		return
	var amplitude := deg_to_rad(44.0 if _fleeing else 27.0) * speed_ratio
	for index in _leg_pivots.size():
		var phase_offset := 0.0 if index in [0, 3] else PI
		_leg_pivots[index].rotation.x = _leg_origins[index].x + sin(_gait_phase + phase_offset) * amplitude

func _apply_head_pose(speed_ratio: float):
	if speed_ratio <= 0.01:
		var idle_nod := sin(_elapsed * 0.9)
		_head_pivot.rotation.x = _head_origin_rotation.x + deg_to_rad(7.0) * idle_nod
		_head_pivot.rotation.y = _head_origin_rotation.y + deg_to_rad(9.0) * sin(_elapsed * 0.47)
	else:
		var stabilization := sin(_gait_phase) * speed_ratio
		_head_pivot.rotation.x = _head_origin_rotation.x - deg_to_rad(5.0 if _fleeing else 2.0) * stabilization
	var ear_weight := 1.0 if _fleeing else 0.35
	_left_ear_pivot.rotation.z = _left_ear_origin_rotation.z - deg_to_rad(12.0) * ear_weight
	_right_ear_pivot.rotation.z = _right_ear_origin_rotation.z + deg_to_rad(12.0) * ear_weight
	_tail_pivot.rotation.x = _tail_origin_rotation.x + sin(_elapsed * (15.0 if _fleeing else 4.0)) * deg_to_rad(18.0 if _fleeing else 5.0)

func _apply_hit_pose():
	if _hit_elapsed >= HIT_SECONDS:
		return
	var progress := clampf(_hit_elapsed / HIT_SECONDS, 0.0, 1.0)
	var weight := sin(progress * PI)
	_rig_root.position = _rig_origin_position + _hit_direction * (0.14 * weight) + Vector3.UP * (0.055 * weight)
	_rig_root.rotation = _rig_origin_rotation + Vector3(
		deg_to_rad(8.0) * _hit_direction.z * weight,
		0.0,
		-deg_to_rad(12.0) * _hit_direction.x * weight
	)
	_body_pivot.scale = _body_origin_scale * Vector3(1.0 + 0.07 * weight, 1.0 - 0.1 * weight, 1.0 + 0.07 * weight)

func _apply_death_pose():
	var progress := smoothstep(0.0, 1.0, _death_elapsed / DEATH_SECONDS)
	_rig_root.position = _rig_origin_position + Vector3(0.12 * progress, 0.38 * progress, 0.0)
	_rig_root.rotation = _rig_origin_rotation + Vector3(0.0, 0.0, deg_to_rad(90.0) * progress)
	for index in range(_leg_pivots.size()):
		var side := -1.0 if index in [0, 2] else 1.0
		_leg_pivots[index].rotation.x = _leg_origins[index].x + deg_to_rad(22.0) * side * progress

func _select_state(planar_speed: float):
	if _hit_elapsed < HIT_SECONDS:
		_current_state = HIT
	elif _fleeing:
		_current_state = FLEE
	elif planar_speed > 0.1:
		_current_state = WALK
	else:
		_current_state = IDLE

func _reset_pose():
	_rig_root.position = _rig_origin_position
	_rig_root.rotation = _rig_origin_rotation
	_body_pivot.position = _body_origin_position
	_body_pivot.rotation = _body_origin_rotation
	_body_pivot.scale = _body_origin_scale
	_head_pivot.rotation = _head_origin_rotation
	_left_ear_pivot.rotation = _left_ear_origin_rotation
	_right_ear_pivot.rotation = _right_ear_origin_rotation
	_tail_pivot.rotation = _tail_origin_rotation
	for index in _leg_pivots.size():
		_leg_pivots[index].rotation = _leg_origins[index]
