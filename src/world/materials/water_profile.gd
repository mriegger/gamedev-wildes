extends Resource
class_name WaterProfile

@export_group("Color")
@export var tint_color: Vector4 = Vector4(0.08, 0.35, 0.65, 0.88)
@export var color_intensity: float = 1.0

@export_group("Tiling & Normals")
@export var normal_scale: float = 0.048
@export var normal_time_scale: float = 0.06
@export var normal_move_dir_a: Vector2 = Vector2(-1.0, 0.2)
@export var normal_move_dir_b: Vector2 = Vector2(0.2, 1.0)
@export var normal_bump_strength: float = 1.0

@export_group("Step Ripples")
@export_range(0.1, 3.0, 0.01) var ripple_duration: float = 1.1
@export_range(0.1, 4.0, 0.01) var ripple_speed: float = 1.35
@export_range(0.05, 1.0, 0.01) var ripple_width: float = 0.28
@export_range(0.0, 1.0, 0.01) var ripple_strength: float = 0.405
@export_range(0.0, 1.0, 0.01) var ripple_directionality: float = 0.65

@export_group("Refraction")
@export var refraction_test: float = 0.35
@export var refraction_offset_scale: float = 0.08

@export_group("Lighting / PBR")
@export var roughness: float = 0.12
@export var specular: float = 1.0

func apply_to_material(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("tint_color", tint_color)
	mat.set_shader_parameter("normal_scale", normal_scale)
	mat.set_shader_parameter("normal_time_scale", normal_time_scale)
	mat.set_shader_parameter("normal_move_dir_a", normal_move_dir_a)
	mat.set_shader_parameter("normal_move_dir_b", normal_move_dir_b)
	mat.set_shader_parameter("refraction_test", refraction_test)
	mat.set_shader_parameter("refraction_offset_scale", refraction_offset_scale)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("specular", specular)
	mat.set_shader_parameter("color_intensity", color_intensity)
	mat.set_shader_parameter("normal_bump_strength", normal_bump_strength)
	mat.set_shader_parameter("ripple_duration", ripple_duration)
	mat.set_shader_parameter("ripple_speed", ripple_speed)
	mat.set_shader_parameter("ripple_width", ripple_width)
	mat.set_shader_parameter("ripple_strength", ripple_strength)
	mat.set_shader_parameter("ripple_directionality", ripple_directionality)
