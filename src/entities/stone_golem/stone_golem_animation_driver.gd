extends EntityAnimationDriver
class_name StoneGolemAnimationDriver

const IDLE: StringName = &"Idle"
const WALK: StringName = &"Walk"
const HIT: StringName = &"Hit"
const DEATH: StringName = &"Death"
const HIT_SECONDS: float = 0.28
const DEATH_SECONDS: float = 1.0
const DORMANT_EYE_COLOR: Color = Color(0.035, 0.03, 0.025, 1.0)
const ALERT_EYE_COLOR: Color = Color(0.95, 0.035, 0.02, 1.0)
const ALERT_EYE_ENERGY: float = 3.5

@export_node_path("MeshInstance3D") var left_eye_path: NodePath
@export_node_path("MeshInstance3D") var right_eye_path: NodePath

var animator: BlockyHumanoidAnimator
var left_eye: MeshInstance3D
var right_eye: MeshInstance3D
var left_eye_material: StandardMaterial3D
var right_eye_material: StandardMaterial3D
var _animation_state: ActorAnimationState = ActorAnimationState.new()
var _current_state: StringName = IDLE
var _hit_elapsed: float = HIT_SECONDS
var _hit_direction: Vector3 = Vector3.BACK
var _dying: bool = false
var _alerted: bool = false
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
	left_eye = get_node(left_eye_path) as MeshInstance3D
	right_eye = get_node(right_eye_path) as MeshInstance3D
	assert(left_eye != null and right_eye != null)
	left_eye_material = _duplicate_eye_material(left_eye)
	right_eye_material = _duplicate_eye_material(right_eye)
	assert(left_eye_material != right_eye_material)
	_visual_origin_position = animator.position
	_visual_origin_rotation = animator.rotation
	_visual_origin_scale = animator.scale
	_animation_state.grounded = actor.get(&"on_ground") as bool
	animator.setup(_animation_state)
	_apply_eye_state()

func set_alerted(alerted: bool) -> void:
	_alerted = alerted and not _dying
	_apply_eye_state()

func play_hit(local_hit_direction: Vector3 = Vector3.BACK):
	if _dying:
		return
	_hit_direction = local_hit_direction.normalized() if not local_hit_direction.is_zero_approx() else Vector3.BACK
	_hit_elapsed = 0.0

func play_death():
	if _dying:
		return
	_dying = true
	set_alerted(false)
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
	_advance_hit(delta)
	_apply_hit_pose()
	if _hit_elapsed < HIT_SECONDS:
		_current_state = HIT
	elif planar_speed > 0.1:
		_current_state = WALK
	else:
		_current_state = IDLE

func get_current_state() -> StringName:
	return _current_state

func _advance_hit(delta: float):
	if _hit_elapsed < HIT_SECONDS:
		_hit_elapsed = minf(_hit_elapsed + delta, HIT_SECONDS)

func _apply_hit_pose():
	if _hit_elapsed >= HIT_SECONDS:
		return
	var progress := clampf(_hit_elapsed / HIT_SECONDS, 0.0, 1.0)
	var weight := sin(progress * PI)
	animator.position = _visual_origin_position + _hit_direction * (0.07 * weight)
	animator.rotation = _visual_origin_rotation + Vector3(
		deg_to_rad(3.0) * _hit_direction.z * weight,
		0.0,
		-deg_to_rad(4.0) * _hit_direction.x * weight
	)

func _apply_death_pose():
	var progress := smoothstep(0.0, 1.0, _death_elapsed / DEATH_SECONDS)
	var settle := smoothstep(0.0, 1.0, minf(progress / 0.42, 1.0))
	var fall := smoothstep(0.0, 1.0, maxf((progress - 0.24) / 0.76, 0.0))
	animator.position = _visual_origin_position + Vector3(0.0, -0.2 * settle + 0.38 * fall, 0.28 * fall)
	animator.rotation = _visual_origin_rotation + Vector3(deg_to_rad(86.0) * fall, 0.0, deg_to_rad(4.0) * settle * (1.0 - fall))
	animator.scale = _visual_origin_scale * Vector3(1.0 + 0.04 * settle, 1.0 - 0.08 * settle, 1.0 + 0.04 * settle)

func _reset_visual_transform():
	animator.position = _visual_origin_position
	animator.rotation = _visual_origin_rotation
	animator.scale = _visual_origin_scale

func _duplicate_eye_material(eye: MeshInstance3D) -> StandardMaterial3D:
	var source := eye.get_active_material(0) as StandardMaterial3D
	assert(source != null)
	var material := source.duplicate() as StandardMaterial3D
	eye.set_surface_override_material(0, material)
	return material

func _apply_eye_state() -> void:
	_apply_eye_material(left_eye_material)
	_apply_eye_material(right_eye_material)

func _apply_eye_material(material: StandardMaterial3D) -> void:
	assert(material != null)
	material.albedo_color = ALERT_EYE_COLOR if _alerted else DORMANT_EYE_COLOR
	material.emission_enabled = _alerted
	material.emission = ALERT_EYE_COLOR if _alerted else Color.BLACK
	material.emission_energy_multiplier = ALERT_EYE_ENERGY if _alerted else 0.0
