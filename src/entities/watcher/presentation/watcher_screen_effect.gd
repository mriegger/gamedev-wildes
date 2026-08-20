extends CanvasLayer
class_name WatcherScreenEffect

const ONSET_SECONDS: float = 0.2
const FADE_SECONDS: float = 1.0
const APERTURE_RADIUS_WORLD_UNITS: float = 2.5
const APERTURE_FEATHER_WORLD_UNITS: float = 0.5
const GLITCH_SHIFT_POWER: float = 0.01
const GLITCH_RATE: float = 1.0
const GLITCH_SPEED: float = 5.0
const GLITCH_BAND_COUNT: float = 30.5
const NOISE_AMOUNT: float = 0.2
const NOISE_SPEED: float = 1.0

@onready var _overlay: ColorRect = $Overlay as ColorRect

var _player: PlayerMotor = null
var _camera: Camera3D = null
var _shader_material: ShaderMaterial = null
var _active_requested: bool = false
var _presentation_enabled: bool = true
var _intensity: float = 0.0
var _transition_start_intensity: float = 0.0
var _transition_elapsed: float = 0.0
var _transition_duration: float = ONSET_SECONDS

func _ready() -> void:
	_shader_material = _overlay.material as ShaderMaterial
	assert(_shader_material != null)
	_apply_static_shader_parameters()
	_apply_intensity()
	visible = _presentation_enabled and (_active_requested or _intensity > 0.0)
	set_process(visible)
	if visible and _player != null:
		_update_shader_geometry()

func setup(p_player: PlayerMotor, p_camera: Camera3D) -> void:
	assert(p_player != null)
	assert(p_camera != null)
	assert(p_camera.projection == Camera3D.PROJECTION_ORTHOGONAL)
	if _player != null:
		assert(_player == p_player)
		assert(_camera == p_camera)
		return
	_player = p_player
	_camera = p_camera
	if is_node_ready() and visible:
		_update_shader_geometry()

func set_active(active: bool) -> void:
	assert(_player != null and _camera != null)
	if _active_requested == active:
		return
	_active_requested = active
	_transition_start_intensity = _intensity
	_transition_elapsed = 0.0
	_transition_duration = ONSET_SECONDS if active else FADE_SECONDS
	if active and _presentation_enabled:
		visible = true
		set_process(true)
		if is_node_ready():
			_update_shader_geometry()
	elif _intensity > 0.0 and _presentation_enabled:
		set_process(true)
	else:
		visible = false
		set_process(false)

func set_presentation_enabled(enabled: bool) -> void:
	if _presentation_enabled == enabled:
		return
	_presentation_enabled = enabled
	_intensity = 0.0
	_transition_start_intensity = 0.0
	_transition_elapsed = 0.0
	_transition_duration = ONSET_SECONDS if _active_requested else FADE_SECONDS
	_apply_intensity()
	if not enabled or not _active_requested:
		visible = false
		set_process(false)
		return
	visible = true
	set_process(true)
	if is_node_ready():
		_update_shader_geometry()

func get_intensity() -> float:
	return _intensity

func get_aperture_center() -> Vector2:
	assert(_shader_material != null)
	return _shader_material.get_shader_parameter(&"aperture_center") as Vector2

func get_aperture_pixel_to_ground_x() -> Vector2:
	assert(_shader_material != null)
	return _shader_material.get_shader_parameter(&"pixel_to_ground_x") as Vector2

func get_aperture_pixel_to_ground_z() -> Vector2:
	assert(_shader_material != null)
	return _shader_material.get_shader_parameter(&"pixel_to_ground_z") as Vector2

func _process(delta: float) -> void:
	assert(delta >= 0.0)
	var target_intensity := 1.0 if _active_requested else 0.0
	if not is_equal_approx(_intensity, target_intensity):
		_transition_elapsed = minf(_transition_elapsed + delta, _transition_duration)
		var progress := _transition_elapsed / _transition_duration
		var eased_progress := smoothstep(0.0, 1.0, progress)
		_intensity = lerpf(_transition_start_intensity, target_intensity, eased_progress)
		if _transition_elapsed >= _transition_duration:
			_intensity = target_intensity
		_apply_intensity()
	_update_shader_geometry()
	if not _active_requested and is_zero_approx(_intensity):
		visible = false
		set_process(false)

func _apply_intensity() -> void:
	if _shader_material != null:
		_shader_material.set_shader_parameter(&"intensity", clampf(_intensity, 0.0, 1.0))

func _apply_static_shader_parameters() -> void:
	_shader_material.set_shader_parameter(&"aperture_radius_world_units", APERTURE_RADIUS_WORLD_UNITS)
	_shader_material.set_shader_parameter(&"aperture_feather_world_units", APERTURE_FEATHER_WORLD_UNITS)
	_shader_material.set_shader_parameter(&"shake_power", GLITCH_SHIFT_POWER)
	_shader_material.set_shader_parameter(&"shake_rate", GLITCH_RATE)
	_shader_material.set_shader_parameter(&"shake_speed", GLITCH_SPEED)
	_shader_material.set_shader_parameter(&"shake_block_size", GLITCH_BAND_COUNT)
	_shader_material.set_shader_parameter(&"noise_amount", NOISE_AMOUNT)
	_shader_material.set_shader_parameter(&"noise_speed", NOISE_SPEED)

func _update_shader_geometry() -> void:
	if _shader_material == null or _player == null or _camera == null:
		return
	var viewport_rect := get_viewport().get_visible_rect()
	var viewport_size := viewport_rect.size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	var player_position := _player.get_world_bounds().get_center()
	var projected_player := _camera.unproject_position(player_position)
	var projected_x_axis := _camera.unproject_position(player_position + Vector3.RIGHT) - projected_player
	var projected_z_axis := _camera.unproject_position(player_position + Vector3.BACK) - projected_player
	var determinant := projected_x_axis.x * projected_z_axis.y - projected_x_axis.y * projected_z_axis.x
	assert(not is_zero_approx(determinant))
	if is_zero_approx(determinant):
		return
	var aperture_center := (projected_player - viewport_rect.position) / viewport_size
	var pixel_to_ground_x := Vector2(projected_z_axis.y, -projected_z_axis.x) / determinant
	var pixel_to_ground_z := Vector2(-projected_x_axis.y, projected_x_axis.x) / determinant
	_shader_material.set_shader_parameter(&"viewport_size", viewport_size)
	_shader_material.set_shader_parameter(&"aperture_center", aperture_center)
	_shader_material.set_shader_parameter(&"pixel_to_ground_x", pixel_to_ground_x)
	_shader_material.set_shader_parameter(&"pixel_to_ground_z", pixel_to_ground_z)
