extends Node
class_name PlayerAnimationDriver

signal mining_impact

const PREVIEW_LIVE: StringName = &"Live"
const PREVIEW_IDLE: StringName = &"Idle"
const PREVIEW_WALK: StringName = &"Walk"
const PREVIEW_SPRINT: StringName = &"Sprint"
const PREVIEW_JUMP: StringName = &"Jump"
const PREVIEW_FALL: StringName = &"Fall"
const PREVIEW_ATTACK: StringName = &"Attack"

@onready var animator: BlockyHumanoidAnimator = $"../ModelRoot/PlayerVisual" as BlockyHumanoidAnimator

var _motor: PlayerMotor
var _interactor: PlayerInteractor
var _animation_state: ActorAnimationState = ActorAnimationState.new()
var _previous_yaw: float = 0.0
var _preview_state: StringName = PREVIEW_LIVE
var _attack_preview_item: ItemDefinition
var _attack_preview_action: MeleeAttackActionDefinition
var _active_attack_action: MeleeAttackActionDefinition
var _attack_preview_elapsed: float = 0.0
var _attack_preview_direction: int = -1
var _attack_preview_paused: bool = false
var _mining_impact_elapsed: float = 0.0
var _mining_impact_active: bool = false

func _ready():
	set_process(false)

func setup(p_motor: PlayerMotor, p_interactor: PlayerInteractor):
	_motor = p_motor
	_interactor = p_interactor
	_previous_yaw = _motor.model_root.rotation.y
	animator.setup(_animation_state)
	_interactor.block_placed.connect(_on_block_placed)
	_interactor.melee_attack_started.connect(_on_melee_attack_started)
	set_process(true)

func setup_attack_preview(item: ItemDefinition):
	assert(item != null and item.held_scene != null)
	var action := item.primary_action as MeleeAttackActionDefinition
	assert(action != null)
	_attack_preview_item = item
	_attack_preview_action = action

func get_attack_preview_action() -> MeleeAttackActionDefinition:
	assert(_attack_preview_action != null)
	return _attack_preview_action

func get_preview_states() -> Array[StringName]:
	return [PREVIEW_LIVE, PREVIEW_IDLE, PREVIEW_WALK, PREVIEW_SPRINT, PREVIEW_JUMP, PREVIEW_FALL, PREVIEW_ATTACK]

func set_preview_state(state: StringName):
	assert(state in get_preview_states())
	if _preview_state == PREVIEW_ATTACK and state != PREVIEW_ATTACK:
		_motor.held_item_view.clear_preview_item()
	_preview_state = state
	_attack_preview_paused = false
	animator.prepare_preview(_motor.on_ground if state == PREVIEW_LIVE else state not in [PREVIEW_JUMP, PREVIEW_FALL])
	_motor.held_item_view.set_attack_pose(0.0, 0.0, null)
	if state == PREVIEW_ATTACK:
		assert(_attack_preview_item != null and _attack_preview_action != null)
		_attack_preview_elapsed = 0.0
		_attack_preview_direction = -1
		_motor.held_item_view.show_preview_item(_attack_preview_item)
		animator.play_attack(_attack_preview_action.attack_profile.duration, _attack_preview_direction)

func set_attack_preview_paused(paused: bool):
	assert(_preview_state == PREVIEW_ATTACK)
	_attack_preview_paused = paused

func set_attack_preview_progress(progress: float):
	assert(_preview_state == PREVIEW_ATTACK)
	_attack_preview_elapsed = clampf(progress, 0.0, 1.0) * _attack_preview_action.attack_profile.duration
	animator.prepare_preview(true)
	animator.play_attack(_attack_preview_action.attack_profile.duration, _attack_preview_direction)
	animator.advance_animation(_attack_preview_elapsed)
	_motor.held_item_view.set_attack_pose(animator.attack_pose_weight, animator.right_arm_action.rotation.x, _attack_preview_action)

func get_attack_preview_progress() -> float:
	assert(_preview_state == PREVIEW_ATTACK)
	return _attack_preview_elapsed / _attack_preview_action.attack_profile.duration

func _process(delta: float):
	if _preview_state != PREVIEW_LIVE:
		_update_mining_impact(0.0, false)
		_update_preview(delta)
		return
	if _active_attack_action != null and (_interactor.melee_attack_action != _active_attack_action or _interactor.get_selected_primary_action() != _active_attack_action):
		_active_attack_action = null
		animator.cancel_attack()
	var model_basis = _motor.model_root.global_transform.basis.orthonormalized()
	var local_velocity = model_basis.inverse() * _motor.velocity
	var planar_speed = Vector2(_motor.velocity.x, _motor.velocity.z).length()
	var target_speed = _motor.sprint_speed if _motor.is_sprinting else _motor.move_speed
	var speed_ratio = clamp(planar_speed / max(target_speed, 0.001), 0.0, 1.0)
	var sprinting = _motor.is_sprinting and planar_speed > 0.1
	var current_yaw = _motor.model_root.rotation.y
	var turn_rate = wrapf(current_yaw - _previous_yaw, -PI, PI) / max(delta, 0.0001)
	_previous_yaw = current_yaw
	var has_look_target = _interactor.target_has
	var local_look_direction = Vector3.ZERO
	if has_look_target:
		var target_center = Vector3(_interactor.target_block) + Vector3(0.5, 0.5, 0.5)
		var head_position = animator.head_secondary.global_position
		local_look_direction = model_basis.inverse() * (target_center - head_position)
	_animation_state.set_motion(local_velocity, speed_ratio, sprinting, _motor.on_ground, _motor.jump_anticipation, turn_rate, has_look_target, local_look_direction)
	var mining_active = _interactor.is_mining and _interactor.can_primary_target
	animator.set_mining_active(mining_active)
	_update_mining_impact(delta, mining_active)
	animator.advance_animation(delta)
	_motor.held_item_view.set_attack_pose(animator.attack_pose_weight, animator.right_arm_action.rotation.x, _active_attack_action)

func _update_preview(delta: float):
	var local_velocity = Vector3.ZERO
	var speed_ratio = 0.0
	var sprinting = false
	var grounded = true
	match _preview_state:
		PREVIEW_WALK:
			local_velocity.z = _motor.move_speed
			speed_ratio = 1.0
		PREVIEW_SPRINT:
			local_velocity.z = _motor.sprint_speed
			speed_ratio = 1.0
			sprinting = true
		PREVIEW_JUMP:
			local_velocity.y = _motor.jump_velocity
			grounded = false
		PREVIEW_FALL:
			local_velocity.y = -_motor.jump_velocity
			grounded = false
	_animation_state.set_motion(local_velocity, speed_ratio, sprinting, grounded, 0.0, 0.0, false, Vector3.ZERO)
	animator.set_mining_active(false)
	if _preview_state == PREVIEW_ATTACK:
		if not _attack_preview_paused:
			_advance_attack_preview(delta)
		_motor.held_item_view.set_attack_pose(animator.attack_pose_weight, animator.right_arm_action.rotation.x, _attack_preview_action)
	else:
		animator.advance_animation(delta)
		_motor.held_item_view.set_attack_pose(0.0, 0.0, null)

func _update_mining_impact(delta: float, active: bool):
	if not active:
		_mining_impact_elapsed = 0.0
		_mining_impact_active = false
		return
	if not _mining_impact_active:
		_mining_impact_active = true
		mining_impact.emit()
	_mining_impact_elapsed += delta
	while _mining_impact_elapsed >= animator.profile.mine_cycle_seconds:
		_mining_impact_elapsed -= animator.profile.mine_cycle_seconds
		mining_impact.emit()

func _advance_attack_preview(delta: float):
	var remaining := delta
	while remaining > 0.0:
		var step := minf(remaining, _attack_preview_action.attack_profile.duration - _attack_preview_elapsed)
		animator.advance_animation(step)
		_attack_preview_elapsed += step
		remaining -= step
		if is_equal_approx(_attack_preview_elapsed, _attack_preview_action.attack_profile.duration):
			_attack_preview_elapsed = 0.0
			_attack_preview_direction *= -1
			animator.play_attack(_attack_preview_action.attack_profile.duration, _attack_preview_direction)

func _on_block_placed():
	animator.play_place()

func _on_melee_attack_started(action: MeleeAttackActionDefinition, direction: int):
	_active_attack_action = action
	animator.play_attack(action.attack_profile.duration, direction)
