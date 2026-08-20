extends Node3D
class_name ArrowTrailView

const TRAIL_DURATION_SECONDS: float = 0.12
const FADE_SECONDS: float = 0.12
const PEAK_ALPHA: float = 0.46

var _mesh_instance: MeshInstance3D
var _mesh: ImmediateMesh
var _material: StandardMaterial3D
var _positions: Array[Vector3] = []
var _elapsed_samples: Array[float] = []
var _fade_elapsed: float = 0.0
var _finishing: bool = false

func _ready() -> void:
	top_level = true
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Trail"
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

func start(position: Vector3) -> void:
	assert(position.is_finite())
	_positions.clear()
	_elapsed_samples.clear()
	_positions.append(position)
	_elapsed_samples.append(0.0)
	_fade_elapsed = 0.0
	_finishing = false
	_mesh_instance.transparency = 0.0
	visible = false
	set_process(false)

func record_position(position: Vector3, flight_elapsed: float) -> void:
	assert(position.is_finite() and is_finite(flight_elapsed) and flight_elapsed >= 0.0)
	assert(not _positions.is_empty() and flight_elapsed >= _elapsed_samples[_elapsed_samples.size() - 1])
	_positions.append(position)
	_elapsed_samples.append(flight_elapsed)
	_prune_samples(flight_elapsed)
	_redraw()

func finish() -> void:
	if _positions.size() < 2:
		visible = false
		return
	_finishing = true
	_fade_elapsed = 0.0
	set_process(true)

func _process(delta: float) -> void:
	assert(is_finite(delta) and delta >= 0.0)
	if not _finishing:
		return
	_fade_elapsed = minf(_fade_elapsed + delta, FADE_SECONDS)
	_mesh_instance.transparency = _fade_elapsed / FADE_SECONDS
	if _fade_elapsed >= FADE_SECONDS:
		visible = false
		set_process(false)

func _prune_samples(flight_elapsed: float) -> void:
	var cutoff := flight_elapsed - TRAIL_DURATION_SECONDS
	while _elapsed_samples.size() > 2 and _elapsed_samples[1] <= cutoff:
		_elapsed_samples.remove_at(0)
		_positions.remove_at(0)
	if _elapsed_samples.size() < 2 or _elapsed_samples[0] >= cutoff:
		return
	var interval := _elapsed_samples[1] - _elapsed_samples[0]
	var weight := 1.0 if interval <= 0.000001 else clampf((cutoff - _elapsed_samples[0]) / interval, 0.0, 1.0)
	_positions[0] = _positions[0].lerp(_positions[1], weight)
	_elapsed_samples[0] = cutoff

func _redraw() -> void:
	_mesh.clear_surfaces()
	if _positions.size() < 2:
		visible = false
		return
	global_position = _positions[_positions.size() - 1]
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _material)
	for index in range(_positions.size()):
		var progress := float(index) / float(_positions.size() - 1)
		_mesh.surface_set_color(Color(1.0, 1.0, 1.0, PEAK_ALPHA * progress))
		_mesh.surface_add_vertex(_positions[index] - global_position)
	_mesh.surface_end()
	visible = true
