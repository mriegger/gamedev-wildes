extends Node3D
class_name ArrowTrajectoryView

const LINE_ALPHA: float = 0.38
const FADE_START_RATIO: float = 0.3
const FADE_END_RATIO: float = 0.95

var _interactor: PlayerInteractor
var _projectile_runtime: ArrowProjectileRuntime
var _mesh_instance: MeshInstance3D
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
func _ready() -> void:
	top_level = true
	process_priority = 1
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Trajectory"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color.WHITE
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.render_priority = 1
	_mesh = ImmediateMesh.new()
	_mesh_instance.mesh = _mesh
	add_child(_mesh_instance)
	visible = false
	set_process(false)

func setup(
	interactor: PlayerInteractor,
	projectile_runtime: ArrowProjectileRuntime,
) -> void:
	assert(interactor != null and projectile_runtime != null)
	assert(_interactor == null and _projectile_runtime == null)
	_interactor = interactor
	_projectile_runtime = projectile_runtime
	set_process(true)

func _process(_delta: float) -> void:
	if not _interactor.is_drawing_bow() or _interactor.get_bow_raise_progress() < 1.0:
		_hide_trajectory()
		return
	var action := _interactor.bow_draw_action
	var ammunition := _interactor.bow_draw_ammunition
	if action == null or ammunition == null:
		_hide_trajectory()
		return
	var release_transform := _interactor.get_bow_release_transform()
	var points := _projectile_runtime.predict_trajectory(
		action,
		ammunition,
		_interactor.get_bow_draw_progress(),
		release_transform,
	)
	if points.size() < 2:
		_hide_trajectory()
		return
	_redraw(points)

func _redraw(points: PackedVector3Array) -> void:
	global_position = points[0]
	var total_length := 0.0
	for index in range(1, points.size()):
		total_length += points[index - 1].distance_to(points[index])
	if total_length <= 0.000001:
		_hide_trajectory()
		return
	var traversed_length := 0.0
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material)
	for index in range(points.size()):
		if index > 0:
			traversed_length += points[index - 1].distance_to(points[index])
		var path_ratio := traversed_length / total_length
		var point := points[index]
		var color := Color(1.0, 1.0, 1.0, _calculate_line_alpha(path_ratio))
		_mesh.surface_set_color(color)
		_mesh.surface_add_vertex(point - global_position)
	_mesh.surface_end()
	visible = true

func _hide_trajectory() -> void:
	visible = false

func _calculate_line_alpha(path_ratio: float) -> float:
	return LINE_ALPHA * (1.0 - smoothstep(FADE_START_RATIO, FADE_END_RATIO, clampf(path_ratio, 0.0, 1.0)))

func _exit_tree() -> void:
	_interactor = null
	_projectile_runtime = null
