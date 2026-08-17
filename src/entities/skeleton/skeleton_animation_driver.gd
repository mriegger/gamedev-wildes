extends EntityAnimationDriver
class_name SkeletonAnimationDriver

const IDLE: StringName = &"Idle"
const WALK: StringName = &"Walk"
const HIDE: StringName = &"Hide"
const HIT: StringName = &"Hit"
const DEATH: StringName = &"Death"
const HIT_SECONDS: float = 0.18
const DEATH_SECONDS: float = 0.58

var animator: BlockyHumanoidAnimator
var _animation_state: ActorAnimationState = ActorAnimationState.new()
var _current_state: StringName = IDLE
var _hit_elapsed: float = HIT_SECONDS
var _hit_direction: Vector3 = Vector3.BACK
var _hiding: bool = false
var _dying: bool = false
var _death_elapsed: float = 0.0
var _previous_yaw: float = 0.0
var _visual_origin_position: Vector3
var _visual_origin_rotation: Vector3
var _visual_origin_scale: Vector3

func setup(p_actor: Node3D):
	super.setup(p_actor)
	animator = get_parent() as BlockyHumanoidAnimator
	assert(animator != null)
	_previous_yaw = model_root.rotation.y
	_visual_origin_position = animator.position
	_visual_origin_rotation = animator.rotation
	_visual_origin_scale = animator.scale
	_animation_state.grounded = actor.get(&"on_ground") as bool
	animator.setup(_animation_state)
	animator.set_tuning_transform(BlockyHumanoidAnimator.TUNING_BODY, Vector3.ZERO, Vector3(4.0, 0.0, 0.0), Vector3.ONE)
	animator.set_tuning_transform(BlockyHumanoidAnimator.TUNING_LEFT_ARM, Vector3.ZERO, Vector3(-5.0, 0.0, -3.0), Vector3.ONE)
	animator.set_tuning_transform(BlockyHumanoidAnimator.TUNING_RIGHT_ARM, Vector3.ZERO, Vector3(-5.0, 0.0, 3.0), Vector3.ONE)

func play_attack(duration: float):
	assert(duration > 0.0)

func set_hiding(hiding: bool):
	_hiding = hiding

func play_hit(local_hit_direction: Vector3 = Vector3.BACK):
	if _dying:
		return
	_hit_direction = local_hit_direction.normalized() if not local_hit_direction.is_zero_approx() else Vector3.BACK
	_hit_elapsed = 0.0

func play_death():
	_dying = true
	_death_elapsed = 0.0
	_hit_elapsed = HIT_SECONDS
	_current_state = DEATH

func is_death_complete() -> bool:
	return _dying and _death_elapsed >= DEATH_SECONDS

func get_death_time_remaining() -> float:
	assert(_dying)
	return maxf(DEATH_SECONDS - _death_elapsed, 0.0)

func advance(delta: float):
	assert(actor != null and animator != null)
	_reset_visual_transform()
	if _dying:
		_death_elapsed = minf(_death_elapsed + delta, DEATH_SECONDS)
		_animation_state.set_motion(Vector3.ZERO, 0.0, false, true, 0.0, 0.0, false, Vector3.ZERO)
		animator.advance_animation(delta)
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
	_animation_state.set_motion(local_velocity, speed_ratio, false, grounded, 0.0, turn_rate, false, Vector3.ZERO)
	animator.advance_animation(delta)
	_advance_hit_timer(delta)
	_apply_hit_pose()
	_apply_hide_pose()
	_select_state(planar_speed)

func get_current_state() -> StringName:
	return _current_state

func _advance_hit_timer(delta: float):
	if _hit_elapsed < HIT_SECONDS:
		_hit_elapsed = minf(_hit_elapsed + delta, HIT_SECONDS)

func _apply_hit_pose():
	if _hit_elapsed >= HIT_SECONDS:
		return
	var progress := clampf(_hit_elapsed / HIT_SECONDS, 0.0, 1.0)
	var weight := sin(progress * PI)
	animator.position = _visual_origin_position + _hit_direction * (0.16 * weight) + Vector3.UP * (0.06 * weight)
	animator.rotation = _visual_origin_rotation + Vector3(
		deg_to_rad(10.0) * _hit_direction.z * weight,
		0.0,
		-deg_to_rad(14.0) * _hit_direction.x * weight
	)
	animator.scale = _visual_origin_scale * Vector3(1.0 + 0.04 * weight, 1.0 - 0.07 * weight, 1.0 + 0.04 * weight)

func _apply_hide_pose():
	if not _hiding:
		return
	animator.position += Vector3(0.0, -0.16, -0.04)
	animator.rotation += Vector3(deg_to_rad(9.0), 0.0, 0.0)
	animator.scale *= Vector3(1.06, 0.86, 1.06)

func _apply_death_pose():
	var progress := smoothstep(0.0, 1.0, _death_elapsed / DEATH_SECONDS)
	var fold := smoothstep(0.0, 1.0, minf(progress / 0.45, 1.0))
	var fall := smoothstep(0.0, 1.0, maxf((progress - 0.18) / 0.82, 0.0))
	animator.position = _visual_origin_position + Vector3(0.0, -0.34 * fold + 0.26 * fall, 0.2 * fall)
	animator.rotation = _visual_origin_rotation + Vector3(deg_to_rad(88.0) * fall, 0.0, deg_to_rad(9.0) * fold * (1.0 - fall))
	animator.scale = _visual_origin_scale * Vector3(1.0 + 0.08 * fold, 1.0 - 0.24 * fold, 1.0 + 0.08 * fold)

func _select_state(planar_speed: float):
	if _hit_elapsed < HIT_SECONDS:
		_current_state = HIT
	elif _hiding:
		_current_state = HIDE
	elif planar_speed > 0.1:
		_current_state = WALK
	else:
		_current_state = IDLE

func _reset_visual_transform():
	animator.position = _visual_origin_position
	animator.rotation = _visual_origin_rotation
	animator.scale = _visual_origin_scale
