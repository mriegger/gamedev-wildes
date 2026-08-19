extends Node3D
class_name HeldItemView

var inventory_model: InventoryModel
var held_node: Node3D
var _displayed_item_id: StringName
var _has_refreshed: bool = false
var _rest_position: Vector3
var _rest_rotation: Vector3
var _rest_scale: Vector3
var _previewing_item: bool = false
var _attack_idle_relative_transform: Transform3D
var _recovery_start_relative_transform: Transform3D
var _has_attack_idle_transform: bool = false
var _recovery_started: bool = false

func _ready():
	_rest_position = position
	_rest_rotation = rotation
	_rest_scale = scale

func setup(p_inventory_model: InventoryModel):
	inventory_model = p_inventory_model
	inventory_model.inventory_changed.connect(_refresh)
	_refresh()

func set_attack_pose(weight: float, attack_arm_pitch: float, action: MeleeAttackActionDefinition, windup_weight: float = 0.0):
	var pose_weight: float = clampf(weight, 0.0, 1.0)
	var windup_pose_weight: float = clampf(windup_weight, 0.0, 1.0)
	var rest_position_offset := action.held_rest_position_offset if action != null else Vector3.ZERO
	var rest_rotation_degrees := action.held_rest_rotation_degrees if action != null else Vector3.ZERO
	var windup_rotation_degrees := action.held_windup_rotation_degrees if action != null else Vector3.ZERO
	var position_offset := action.held_position_offset if action != null else Vector3.ZERO
	var rotation_degrees := action.held_rotation_degrees if action != null else Vector3.ZERO
	position = _rest_position + rest_position_offset + position_offset * pose_weight
	rotation = _rest_rotation + Vector3(
		deg_to_rad(rest_rotation_degrees.x),
		deg_to_rad(rest_rotation_degrees.y),
		deg_to_rad(rest_rotation_degrees.z)
	) + Vector3(
		deg_to_rad(windup_rotation_degrees.x),
		deg_to_rad(windup_rotation_degrees.y),
		deg_to_rad(windup_rotation_degrees.z)
	) * windup_pose_weight + Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	) * pose_weight
	if pose_weight > 0.0 and action != null and action.compensate_attack_arm_pitch:
		rotation.x -= attack_arm_pitch

func align_overhead_striking_face(alignment_weight: float, face_turn_weight: float, action: MeleeAttackActionDefinition, p_actor_forward: Vector3) -> void:
	if action == null or not action.align_overhead_striking_face:
		return
	var weight := clampf(alignment_weight, 0.0, 1.0)
	if is_zero_approx(weight):
		return
	if not p_actor_forward.is_finite():
		return
	var actor_forward := p_actor_forward
	actor_forward.y = 0.0
	if actor_forward.length_squared() <= 0.0001:
		actor_forward = Vector3.BACK
	else:
		actor_forward = actor_forward.normalized()
	var actor_right := Vector3.UP.cross(actor_forward).normalized()
	var swing_angle := PI * clampf(face_turn_weight, 0.0, 1.0)
	var striking_face := Vector3.UP.rotated(actor_right, swing_angle).normalized()
	var handle_direction := (-actor_forward).rotated(actor_right, swing_angle).normalized()
	var target_basis := Basis(striking_face, handle_direction, striking_face.cross(handle_direction)).orthonormalized()
	var current_global_rotation := global_transform.basis.orthonormalized()
	var blended_global_rotation := current_global_rotation.slerp(target_basis, weight)
	var parent_node := get_parent() as Node3D
	var parent_global_rotation := parent_node.global_transform.basis.orthonormalized()
	var authored_local_scale := scale
	basis = (parent_global_rotation.inverse() * blended_global_rotation).orthonormalized().scaled(authored_local_scale)

func anchor_two_handed_grip(weight: float, left_hand_position: Vector3, right_hand_position: Vector3) -> void:
	assert(left_hand_position.is_finite() and right_hand_position.is_finite())
	var grip_weight := clampf(weight, 0.0, 1.0)
	if is_zero_approx(grip_weight):
		return
	global_position = global_position.lerp((left_hand_position + right_hand_position) * 0.5, grip_weight)

func capture_attack_idle_transform(idle_anchor_transform: Transform3D) -> void:
	_attack_idle_relative_transform = idle_anchor_transform.affine_inverse() * global_transform
	_attack_idle_relative_transform.basis = _attack_idle_relative_transform.basis.orthonormalized()
	_has_attack_idle_transform = true
	_recovery_started = false

func begin_linear_attack_recovery(actor_transform: Transform3D) -> void:
	if not _has_attack_idle_transform or _recovery_started:
		return
	_recovery_start_relative_transform = actor_transform.affine_inverse() * global_transform
	_recovery_start_relative_transform.basis = _recovery_start_relative_transform.basis.orthonormalized()
	_recovery_started = true

func apply_linear_attack_recovery(progress: float, actor_transform: Transform3D, idle_anchor_transform: Transform3D) -> void:
	var recovery_progress := clampf(progress, 0.0, 1.0)
	if not _has_attack_idle_transform or is_zero_approx(recovery_progress):
		return
	if not _recovery_started:
		begin_linear_attack_recovery(actor_transform)
	var idle_global_transform := idle_anchor_transform * _attack_idle_relative_transform
	var idle_relative_transform := actor_transform.affine_inverse() * idle_global_transform
	idle_relative_transform.basis = idle_relative_transform.basis.orthonormalized()
	var relative_transform := _recovery_start_relative_transform.interpolate_with(idle_relative_transform, recovery_progress)
	var desired_global_transform := actor_transform * relative_transform
	global_position = desired_global_transform.origin
	var parent_node := get_parent() as Node3D
	var parent_global_rotation := parent_node.global_transform.basis.orthonormalized()
	basis = (parent_global_rotation.inverse() * desired_global_transform.basis.orthonormalized()).orthonormalized().scaled(_rest_scale)

func show_preview_item(definition: ItemDefinition):
	assert(definition.held_scene != null)
	_previewing_item = true
	_replace_held_scene(definition.held_scene)

func clear_preview_item():
	_previewing_item = false
	_has_refreshed = false
	_refresh()

func _refresh():
	if _previewing_item:
		return
	var selected_item_id = inventory_model.get_selected_item_id()
	if _has_refreshed and selected_item_id == _displayed_item_id:
		return
	_has_refreshed = true
	_displayed_item_id = selected_item_id if selected_item_id != null else &""
	var held_scene: PackedScene = null
	if selected_item_id != null:
		held_scene = inventory_model.item_catalog.get_definition(selected_item_id).held_scene
	_replace_held_scene(held_scene)

func _replace_held_scene(scene: PackedScene):
	if held_node != null:
		held_node.free()
		held_node = null
	if scene == null:
		return
	held_node = scene.instantiate() as Node3D
	add_child(held_node)
