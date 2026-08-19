extends Node3D
class_name SwordSwingArcView

const HEIGHT_RATIO: float = 0.42
const SEGMENTS: int = 32
const PEAK_ALPHA: float = 0.56

var _interactor: PlayerInteractor
var _motor: PlayerMotor
var _mesh_instance: MeshInstance3D
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _active_action: MeleeAttackActionDefinition
var _elapsed: float = 0.0
var _duration: float = 0.0
var _reach: float = 0.0
var _sweep_radians: float = 0.0
var _attack_direction: int = 0
var _forward: Vector3 = Vector3.BACK
var _right: Vector3 = Vector3.RIGHT
var _leading_progress: float = 0.0
var _lagging_progress: float = 0.0
var _leading_angle: float = 0.0
var _lagging_angle: float = 0.0

func _ready() -> void:
	top_level = true
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Arc"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color.WHITE
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.vertex_color_use_as_albedo = true
	_material.render_priority = 1
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	add_child(_mesh_instance)
	visible = false
	set_process(false)

func setup(interactor: PlayerInteractor, motor: PlayerMotor) -> void:
	assert(interactor != null and motor != null and _interactor == null and _motor == null)
	_interactor = interactor
	_motor = motor
	_interactor.melee_attack_started.connect(_on_melee_attack_started)

func _process(delta: float) -> void:
	if _active_action == null or _motor == null:
		_stop()
		return
	if _interactor.melee_attack_action != _active_action and _elapsed < _duration:
		_stop()
		return
	_elapsed = minf(_elapsed + delta, _duration)
	global_position = _motor.global_position + Vector3.UP * (_motor.player_height * HEIGHT_RATIO)
	var action_progress := clampf(_elapsed / _duration, 0.0, 1.0)
	var contact_progress := _active_action.get_sweep_contact_progress()
	if action_progress <= contact_progress:
		_redraw_arc(_active_action.get_sweep_trace_progress(action_progress), 0.0, 1.0)
	else:
		var trailing_progress := (action_progress - contact_progress) / (1.0 - contact_progress)
		_redraw_arc(1.0, trailing_progress, 1.0 - trailing_progress)
	visible = _leading_progress > _lagging_progress
	if _elapsed >= _duration:
		_stop()

func play(action: MeleeAttackActionDefinition, direction: int) -> void:
	if action == null or action.animation_style != MeleeAttackActionDefinition.AnimationStyle.SWEEP or direction == 0:
		_stop()
		return
	var profile := action.attack_profile
	if profile == null or profile.sweep_degrees <= 0.0 or profile.sweep_degrees >= 360.0:
		_stop()
		return
	var forward := _motor.model_root.global_transform.basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		forward = Vector3.BACK
	_forward = forward.normalized()
	_right = Vector3.UP.cross(_forward).normalized()
	_active_action = action
	_duration = profile.duration
	_reach = profile.reach
	_sweep_radians = deg_to_rad(profile.sweep_degrees)
	_attack_direction = signi(direction)
	_elapsed = 0.0
	global_position = _motor.global_position + Vector3.UP * (_motor.player_height * HEIGHT_RATIO)
	_redraw_arc(0.0, 0.0, 1.0)
	visible = false
	set_process(true)

func _on_melee_attack_started(action: MeleeAttackActionDefinition, direction: int) -> void:
	play(action, direction)

func _redraw_arc(leading_progress: float, lagging_progress: float, opacity: float) -> void:
	_mesh.clear_surfaces()
	var half_sweep := _sweep_radians * 0.5
	var start_angle := half_sweep if _attack_direction < 0 else -half_sweep
	var end_angle := -half_sweep if _attack_direction < 0 else half_sweep
	_leading_progress = clampf(leading_progress, 0.0, 1.0)
	_lagging_progress = clampf(lagging_progress, 0.0, 1.0)
	_leading_angle = lerpf(start_angle, end_angle, _leading_progress)
	_lagging_angle = lerpf(start_angle, end_angle, _lagging_progress)
	var scan_width := absf(_leading_progress - _lagging_progress)
	var segment_count := maxi(1, ceili(float(SEGMENTS) * maxf(scan_width, 0.01)))
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for index in range(segment_count):
		var trail_start := float(index) / float(segment_count)
		var trail_end := float(index + 1) / float(segment_count)
		var start_direction := _forward * cos(lerpf(_lagging_angle, _leading_angle, trail_start)) + _right * sin(lerpf(_lagging_angle, _leading_angle, trail_start))
		var end_direction := _forward * cos(lerpf(_lagging_angle, _leading_angle, trail_end)) + _right * sin(lerpf(_lagging_angle, _leading_angle, trail_end))
		var alpha := PEAK_ALPHA * opacity * lerpf(0.08, 1.0, trail_end)
		_mesh.surface_set_color(Color(1.0, 1.0, 1.0, alpha))
		_mesh.surface_add_vertex(Vector3.ZERO)
		_mesh.surface_add_vertex(start_direction * _reach)
		_mesh.surface_add_vertex(end_direction * _reach)
	_mesh.surface_end()

func _stop() -> void:
	_active_action = null
	visible = false
	set_process(false)

func _exit_tree() -> void:
	if _interactor != null and _interactor.melee_attack_started.is_connected(_on_melee_attack_started):
		_interactor.melee_attack_started.disconnect(_on_melee_attack_started)
	_interactor = null
	_motor = null
