extends Node3D
class_name HammerShockwaveView

const DURATION_SECONDS: float = 0.5
const INNER_EDGE_DELAY: float = 0.16
const INNER_EDGE_CATCH_UP: float = 0.9
const FINAL_INNER_RADIUS_RATIO: float = 1.0
const SEGMENTS: int = 48

var _interactor: PlayerInteractor
var _camera_rig: CameraRig
var _mesh_instance: MeshInstance3D
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _elapsed: float = 0.0
var _target_radius: float = 0.0
var _inner_radius_ratio: float = 0.0

func _ready() -> void:
	top_level = true
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Ring"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = 1
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	_redraw_ring(0.0)
	add_child(_mesh_instance)
	visible = false
	set_process(false)

func setup(interactor: PlayerInteractor, camera_rig: CameraRig = null) -> void:
	assert(interactor != null and _interactor == null)
	_interactor = interactor
	_camera_rig = camera_rig
	_interactor.melee_attack_impacted.connect(_on_melee_attack_impacted)

func _process(delta: float) -> void:
	_elapsed = minf(_elapsed + delta, DURATION_SECONDS)
	var progress := _elapsed / DURATION_SECONDS
	var radius := lerpf(0.15, _target_radius, 1.0 - pow(1.0 - progress, 3.0))
	scale = Vector3(radius, 1.0, radius)
	var inner_progress := clampf((progress - INNER_EDGE_DELAY) / (INNER_EDGE_CATCH_UP - INNER_EDGE_DELAY), 0.0, 1.0)
	_inner_radius_ratio = FINAL_INNER_RADIUS_RATIO * smoothstep(0.0, 1.0, inner_progress)
	_redraw_ring(_inner_radius_ratio)
	_material.albedo_color = Color(1.0, 1.0, 1.0, 0.62 * (1.0 - progress))
	if _elapsed >= DURATION_SECONDS:
		visible = false
		set_process(false)

func play(position: Vector3, radius: float) -> void:
	if not position.is_finite() or not is_finite(radius) or radius <= 0.0:
		return
	global_position = position
	_target_radius = radius
	_elapsed = 0.0
	_inner_radius_ratio = 0.0
	scale = Vector3.ONE * 0.15
	_redraw_ring(0.0)
	_material.albedo_color = Color(1.0, 1.0, 1.0, 0.62)
	visible = true
	set_process(true)

func _on_melee_attack_impacted(action: MeleeAttackActionDefinition, position: Vector3) -> void:
	if action != null and action.impact_effect_radius > 0.0:
		play(position, action.impact_effect_radius)
		if _camera_rig != null:
			_camera_rig.play_impact_shake()

func _redraw_ring(inner_radius_ratio: float) -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for index in range(SEGMENTS + 1):
		var angle := TAU * float(index) / float(SEGMENTS)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		_mesh.surface_add_vertex(direction)
		_mesh.surface_add_vertex(direction * inner_radius_ratio)
	_mesh.surface_end()

func _exit_tree() -> void:
	if _interactor != null and _interactor.melee_attack_impacted.is_connected(_on_melee_attack_impacted):
		_interactor.melee_attack_impacted.disconnect(_on_melee_attack_impacted)
	_interactor = null
	_camera_rig = null
