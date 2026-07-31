extends Resource
class_name WaterProfile

## WaterProfile - single source of truth for water.gdshader uniforms
## Saved as res://environment/water_profile.tres
## WorldController loads this and applies to water ShaderMaterial.

@export_group("Color")
@export var tint_color: Vector4 = Vector4(0.08, 0.35, 0.65, 0.88)
@export var color_intensity: float = 1.0
@export var color_boost: float = 1.0
@export var depth_tint_strength: float = 0.6

@export_group("Tiling & Normals")
@export var normal_scale: float = 0.048
@export var normal_time_scale: float = 0.06
@export var normal_move_dir_a: Vector2 = Vector2(-1.0, 0.2)
@export var normal_move_dir_b: Vector2 = Vector2(0.2, 1.0)
@export var normal_bump_strength: float = 1.0
@export var large_wave_scale: float = 0.012
@export var large_wave_strength: float = 0.45

@export_group("Refraction")
@export var refraction_test: float = 0.35
@export var refraction_offset_scale: float = 0.08

@export_group("Lighting / PBR")
@export var sun_dir: Vector3 = Vector3(0.35, 0.72, 0.28)
@export var sun_color: Vector3 = Vector3(1.0, 0.95, 0.85)
@export var sun_energy: float = 1.2
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
	mat.set_shader_parameter("depth_tint_strength", depth_tint_strength)
	mat.set_shader_parameter("refraction_test", refraction_test)
	mat.set_shader_parameter("refraction_offset_scale", refraction_offset_scale)
	mat.set_shader_parameter("sun_dir", sun_dir)
	mat.set_shader_parameter("sun_color", sun_color)
	mat.set_shader_parameter("sun_energy", sun_energy)
	mat.set_shader_parameter("roughness", roughness)
	mat.set_shader_parameter("specular", specular)
	mat.set_shader_parameter("color_intensity", color_intensity)
	mat.set_shader_parameter("color_boost", color_boost)
	mat.set_shader_parameter("normal_bump_strength", normal_bump_strength)
	mat.set_shader_parameter("large_wave_scale", large_wave_scale)
	mat.set_shader_parameter("large_wave_strength", large_wave_strength)


func get_param_dict() -> Dictionary:
	return {
		"tint_color": tint_color,
		"normal_scale": normal_scale,
		"normal_time_scale": normal_time_scale,
		"normal_move_dir_a": normal_move_dir_a,
		"normal_move_dir_b": normal_move_dir_b,
		"depth_tint_strength": depth_tint_strength,
		"refraction_test": refraction_test,
		"refraction_offset_scale": refraction_offset_scale,
		"sun_dir": sun_dir,
		"sun_color": sun_color,
		"sun_energy": sun_energy,
		"roughness": roughness,
		"specular": specular,
		"color_intensity": color_intensity,
		"color_boost": color_boost,
		"normal_bump_strength": normal_bump_strength,
		"large_wave_scale": large_wave_scale,
		"large_wave_strength": large_wave_strength,
	}
