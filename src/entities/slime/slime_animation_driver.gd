extends EntityAnimationDriver
class_name SlimeAnimationDriver

const IDLE: StringName = &"Idle"
const HOP: StringName = &"Hop"
const LAND: StringName = &"Land"
const ATTACHED: StringName = &"Attached"
const HIT: StringName = &"Hit"
const DEATH: StringName = &"Death"
const HIT_SECONDS: float = 0.2
const DEATH_SECONDS: float = 0.45
const DEATH_SQUASH_END_RATIO: float = 0.22
const DEATH_REBOUND_END_RATIO: float = 0.68
const DEATH_SQUASH_SCALE: float = 0.58
const DEATH_REBOUND_SCALE: float = 1.4
const DEATH_REBOUND_LIFT: float = 0.08
const DEATH_POP_SCALE: float = 0.08
const LAND_SECONDS: float = 0.36
const MIN_LANDING_STRENGTH: float = 0.55
const AIRBORNE_SPEED_FLOOR: float = 1.0

var _rig_root: Node3D
var _size_root: Node3D
var _body_pivot: Node3D
var _rig_origin: Transform3D
var _body_origin: Transform3D
var _elapsed: float = 0.0
var _hit_elapsed: float = HIT_SECONDS
var _hit_direction: Vector3 = Vector3.BACK
var _dying: bool = false
var _death_elapsed: float = 0.0
var _current_state: StringName = IDLE
var _was_on_ground: bool = true
var _was_attached: bool = false
var _previous_vertical_velocity: float = 0.0
var _airborne_speed_reference: float = AIRBORNE_SPEED_FLOOR
var _landing_elapsed: float = LAND_SECONDS
var _landing_strength: float = MIN_LANDING_STRENGTH
var _attachment_elapsed: float = 0.0
var _wobble_phase: float = 0.0

func setup(p_actor: Node3D) -> void:
	super.setup(p_actor)
	var visual := get_parent() as Node3D
	assert(visual != null)
	_rig_root = visual.get_node(^"RigRoot") as Node3D
	_size_root = _rig_root.get_node(^"SizeRoot") as Node3D
	_body_pivot = _size_root.get_node(^"BodyPivot") as Node3D
	assert(_rig_root != null and _size_root != null and _body_pivot != null)
	_rig_origin = _rig_root.transform
	_body_origin = _body_pivot.transform
	var slime := actor as SlimeActor
	_was_on_ground = slime.on_ground
	_was_attached = slime.is_attached()
	_previous_vertical_velocity = slime.velocity.y
	_wobble_phase = float(posmod(slime.behavior_seed, 1024)) * TAU / 1024.0
	var behavior := slime.definition.behavior as SlimeBehaviorDefinition
	assert(behavior != null)
	_airborne_speed_reference = maxf(behavior.jump_velocity, AIRBORNE_SPEED_FLOOR)

func configure_dimensions(body_width: float, body_height: float) -> void:
	assert(is_finite(body_width) and body_width > 0.0)
	assert(is_finite(body_height) and body_height > 0.0)
	_size_root.scale = Vector3(body_width, body_height, body_width)

func advance(delta: float) -> void:
	assert(actor is SlimeActor)
	assert(is_finite(delta) and delta >= 0.0)
	_elapsed += delta
	_reset_pose()
	var slime := actor as SlimeActor
	_advance_motion_state(slime, delta)
	if _dying:
		_death_elapsed = minf(_death_elapsed + delta, DEATH_SECONDS)
		_apply_death_pose()
		_current_state = DEATH
		return
	_hit_elapsed = minf(_hit_elapsed + delta, HIT_SECONDS)
	if _hit_elapsed < HIT_SECONDS:
		_apply_hit_pose()
		_current_state = HIT
		return
	if slime.is_attached():
		_apply_attached_pose()
		_current_state = ATTACHED
	elif not slime.on_ground:
		_apply_hop_pose(slime.velocity.y)
		_current_state = HOP
	elif _landing_elapsed < LAND_SECONDS:
		_apply_landing_pose()
		_current_state = LAND
	else:
		_apply_idle_pose()
		_current_state = IDLE

func play_attack(_duration: float) -> void:
	pass

func play_hit(local_hit_direction: Vector3 = Vector3.BACK) -> void:
	if _dying:
		return
	_hit_direction = local_hit_direction.normalized() if not local_hit_direction.is_zero_approx() else Vector3.BACK
	_hit_elapsed = 0.0

func play_death() -> void:
	_dying = true
	_death_elapsed = 0.0
	_hit_elapsed = HIT_SECONDS
	_current_state = DEATH

func is_death_complete() -> bool:
	return _dying and _death_elapsed >= DEATH_SECONDS

func get_death_time_remaining() -> float:
	assert(_dying)
	return maxf(DEATH_SECONDS - _death_elapsed, 0.0)

func get_current_state() -> StringName:
	return _current_state

func _apply_idle_pose() -> void:
	var breath := sin(_elapsed * TAU / 1.45 + _wobble_phase)
	var ripple := sin(_elapsed * TAU / 0.68 + _wobble_phase * 1.7)
	var vertical_scale := 1.0 + breath * 0.07 + ripple * 0.018
	_apply_elastic_deformation(vertical_scale, maxf(breath, 0.0) * 0.018)
	_body_pivot.rotation.z = deg_to_rad(1.4) * ripple

func _apply_hop_pose(vertical_velocity: float) -> void:
	var speed_ratio := clampf(absf(vertical_velocity) / _airborne_speed_reference, 0.0, 1.0)
	var stretch := smoothstep(0.0, 1.0, speed_ratio)
	var stretch_amount := 0.32 if vertical_velocity >= 0.0 else 0.27
	var apex_squash := (1.0 - stretch) * 0.035
	_apply_elastic_deformation(1.0 + stretch * stretch_amount - apex_squash, stretch * 0.025)
	_body_pivot.rotation.z = deg_to_rad(1.8) * sin(_elapsed * TAU / 0.72 + _wobble_phase) * speed_ratio

func _apply_landing_pose() -> void:
	var progress := clampf(_landing_elapsed / LAND_SECONDS, 0.0, 1.0)
	var oscillation := cos(progress * TAU * 1.25) * exp(-3.2 * progress)
	var vertical_scale := 1.0 - oscillation * 0.34 * _landing_strength
	var rebound_lift := maxf(-oscillation, 0.0) * 0.04 * _landing_strength
	_apply_elastic_deformation(vertical_scale, rebound_lift)

func _apply_attached_pose() -> void:
	var entry_splat := exp(-8.0 * _attachment_elapsed)
	var wobble := sin(_attachment_elapsed * TAU / 0.68 + _wobble_phase)
	var ripple := sin(_attachment_elapsed * TAU / 0.37 + _wobble_phase * 1.7)
	var vertical_scale := 0.9 - entry_splat * 0.18 + wobble * 0.07 + ripple * 0.025
	_apply_elastic_deformation(vertical_scale, maxf(wobble, 0.0) * 0.02)
	_rig_root.rotation.z = deg_to_rad(7.0) * wobble + deg_to_rad(2.0) * ripple

func _apply_hit_pose() -> void:
	var progress := clampf(_hit_elapsed / HIT_SECONDS, 0.0, 1.0)
	var recoil := sin(progress * PI)
	var elastic_pulse := sin(progress * TAU) * (1.0 - progress)
	_apply_elastic_deformation(1.0 - elastic_pulse * 0.28)
	_body_pivot.position += _hit_direction * 0.12 * recoil

func _apply_death_pose() -> void:
	var progress := clampf(_death_elapsed / DEATH_SECONDS, 0.0, 1.0)
	if progress <= DEATH_SQUASH_END_RATIO:
		var squash_progress := smoothstep(0.0, 1.0, progress / DEATH_SQUASH_END_RATIO)
		_apply_elastic_deformation(lerpf(1.0, DEATH_SQUASH_SCALE, squash_progress))
		return
	if progress <= DEATH_REBOUND_END_RATIO:
		var rebound_progress := smoothstep(
			0.0,
			1.0,
			(progress - DEATH_SQUASH_END_RATIO)
			/ (DEATH_REBOUND_END_RATIO - DEATH_SQUASH_END_RATIO),
		)
		_apply_elastic_deformation(
			lerpf(DEATH_SQUASH_SCALE, DEATH_REBOUND_SCALE, rebound_progress),
			DEATH_REBOUND_LIFT * rebound_progress,
		)
		return
	var pop_progress := smoothstep(
		0.0,
		1.0,
		(progress - DEATH_REBOUND_END_RATIO) / (1.0 - DEATH_REBOUND_END_RATIO),
	)
	var rebound_horizontal_scale := 1.0 / sqrt(DEATH_REBOUND_SCALE)
	var rebound_scale := Vector3(
		rebound_horizontal_scale,
		DEATH_REBOUND_SCALE,
		rebound_horizontal_scale,
	)
	_body_pivot.scale = rebound_scale.lerp(Vector3.ONE * DEATH_POP_SCALE, pop_progress)
	var centered_pop_lift := 0.5 * (1.0 - DEATH_POP_SCALE)
	_body_pivot.position.y = _body_origin.origin.y + lerpf(
		DEATH_REBOUND_LIFT,
		centered_pop_lift,
		pop_progress,
	)

func _advance_motion_state(slime: SlimeActor, delta: float) -> void:
	var attached := slime.is_attached()
	var launched := _was_on_ground and not slime.on_ground and not _was_attached and not attached and slime.velocity.y > 0.0
	var landed := not _was_on_ground and slime.on_ground and not _was_attached and not attached
	if launched:
		_airborne_speed_reference = maxf(slime.velocity.y, AIRBORNE_SPEED_FLOOR)
	if landed:
		var impact_speed := maxf(-_previous_vertical_velocity, 0.0)
		_landing_strength = clampf(impact_speed / _airborne_speed_reference, MIN_LANDING_STRENGTH, 1.0)
		_landing_elapsed = minf(delta, LAND_SECONDS)
	elif attached or not slime.on_ground:
		_landing_elapsed = LAND_SECONDS
	else:
		_landing_elapsed = minf(_landing_elapsed + delta, LAND_SECONDS)
	if attached:
		_attachment_elapsed = 0.0 if not _was_attached else _attachment_elapsed + delta
	else:
		_attachment_elapsed = 0.0
	_was_on_ground = slime.on_ground
	_was_attached = attached
	_previous_vertical_velocity = slime.velocity.y

func _apply_elastic_deformation(vertical_scale: float, lift: float = 0.0) -> void:
	var horizontal_scale := 1.0 / sqrt(vertical_scale)
	_body_pivot.scale = Vector3(horizontal_scale, vertical_scale, horizontal_scale)
	_body_pivot.position.y = _body_origin.origin.y + lift

func _reset_pose() -> void:
	_rig_root.transform = _rig_origin
	_body_pivot.transform = _body_origin
