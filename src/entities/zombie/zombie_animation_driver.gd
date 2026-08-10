extends EntityAnimationDriver
class_name ZombieAnimationDriver

const IDLE: StringName = &"Idle"
const WALK: StringName = &"Walk"
const CHASE: StringName = &"Chase"
const ATTACK: StringName = &"Attack"
const HIT: StringName = &"Hit"
const HIT_SECONDS: float = 0.22

var animator: BlockyHumanoidAnimator
var _animation_state: ActorAnimationState = ActorAnimationState.new()
var _current_state: StringName = IDLE
var _chasing: bool = false
var _attacking: bool = false
var _attack_elapsed: float = 0.0
var _attack_duration: float = 0.0
var _attack_direction: int = 1
var _hit_elapsed: float = HIT_SECONDS
var _hit_direction: Vector3 = Vector3.BACK
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
	animator.set_tuning_transform(BlockyHumanoidAnimator.TUNING_BODY, Vector3.ZERO, Vector3(6.0, 0.0, 0.0), Vector3.ONE)
	animator.set_tuning_transform(BlockyHumanoidAnimator.TUNING_LEFT_ARM, Vector3.ZERO, Vector3(-68.0, 0.0, -4.0), Vector3.ONE)
	animator.set_tuning_transform(BlockyHumanoidAnimator.TUNING_RIGHT_ARM, Vector3.ZERO, Vector3(-68.0, 0.0, 4.0), Vector3.ONE)

func set_chasing(active: bool):
	_chasing = active

func play_attack(duration: float):
	assert(duration > 0.0)
	_attacking = true
	_attack_elapsed = 0.0
	_attack_duration = duration
	_attack_direction *= -1
	_hit_elapsed = HIT_SECONDS
	animator.play_attack(duration, _attack_direction)

func play_hit(local_hit_direction: Vector3 = Vector3.BACK):
	_hit_direction = local_hit_direction.normalized() if not local_hit_direction.is_zero_approx() else Vector3.BACK
	_hit_elapsed = 0.0
	_attacking = false
	_attack_elapsed = 0.0
	_attack_duration = 0.0
	animator.cancel_attack()

func advance(delta: float):
	assert(actor != null and animator != null)
	_reset_visual_transform()
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
	var sprinting := _chasing and planar_speed > 0.1
	_animation_state.set_motion(local_velocity, speed_ratio, sprinting, grounded, 0.0, turn_rate, false, Vector3.ZERO)
	animator.advance_animation(delta)
	_advance_action_timers(delta)
	_apply_attack_pose()
	_apply_hit_pose()
	_select_state(planar_speed)

func get_current_state() -> StringName:
	return _current_state

func _advance_action_timers(delta: float):
	if _attacking:
		_attack_elapsed += delta
		if _attack_elapsed >= _attack_duration:
			_attacking = false
	if _hit_elapsed < HIT_SECONDS:
		_hit_elapsed = minf(_hit_elapsed + delta, HIT_SECONDS)

func _apply_attack_pose():
	if not _attacking:
		return
	var weight := animator.attack_pose_weight
	animator.left_arm_action.rotation.x -= deg_to_rad(34.0) * weight
	animator.left_arm_action.rotation.z += deg_to_rad(18.0 * _attack_direction) * weight
	animator.rig_root.position.z += 0.12 * weight

func _apply_hit_pose():
	if _hit_elapsed >= HIT_SECONDS:
		return
	var progress := clampf(_hit_elapsed / HIT_SECONDS, 0.0, 1.0)
	var weight := sin(progress * PI)
	animator.position = _visual_origin_position + _hit_direction * (0.13 * weight) + Vector3.UP * (0.04 * weight)
	animator.rotation = _visual_origin_rotation + Vector3(
		deg_to_rad(9.0) * _hit_direction.z * weight,
		0.0,
		-deg_to_rad(11.0) * _hit_direction.x * weight
	)
	animator.scale = _visual_origin_scale * Vector3(1.0 + 0.05 * weight, 1.0 - 0.08 * weight, 1.0 + 0.05 * weight)

func _select_state(planar_speed: float):
	if _hit_elapsed < HIT_SECONDS:
		_current_state = HIT
	elif _attacking:
		_current_state = ATTACK
	elif _chasing and planar_speed > 0.1:
		_current_state = CHASE
	elif planar_speed > 0.1:
		_current_state = WALK
	else:
		_current_state = IDLE

func _reset_visual_transform():
	animator.position = _visual_origin_position
	animator.rotation = _visual_origin_rotation
	animator.scale = _visual_origin_scale
