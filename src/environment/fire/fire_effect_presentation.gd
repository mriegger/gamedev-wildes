extends Node3D
class_name FireEffectPresentation

func setup(effect_scale: float = 1.0) -> void:
	assert(effect_scale > 0.0)
	_add_fire(effect_scale)
	_add_smoke(effect_scale)

func _add_fire(effect_scale: float) -> void:
	var fire := GPUParticles3D.new()
	fire.name = "Fire"
	fire.amount = maxi(12, roundi(12.0 * effect_scale))
	fire.lifetime = 0.7
	fire.randomness = 0.72
	fire.visibility_aabb = AABB(Vector3(-0.3, -0.1, -0.3) * effect_scale, Vector3(0.6, 0.65, 0.6) * effect_scale)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.075 * effect_scale
	process_material.direction = Vector3.UP
	process_material.spread = 24.0
	process_material.gravity = Vector3(0.0, 0.08, 0.0)
	process_material.initial_velocity_min = 0.12 * effect_scale
	process_material.initial_velocity_max = 0.24 * effect_scale
	process_material.scale_min = 0.65 * effect_scale
	process_material.scale_max = 1.15 * effect_scale
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.45))
	scale_curve.add_point(Vector2(0.35, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.08))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process_material.scale_curve = scale_texture
	var fire_gradient := Gradient.new()
	fire_gradient.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	fire_gradient.colors = PackedColorArray([
		Color(1.0, 0.86, 0.25, 0.95),
		Color(1.0, 0.32, 0.06, 0.82),
		Color(0.52, 0.04, 0.01, 0.0),
	])
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = fire_gradient
	process_material.color_ramp = gradient_texture
	fire.process_material = process_material
	var flame := SphereMesh.new()
	flame.radius = 0.045
	flame.height = 0.10
	flame.radial_segments = 5
	flame.rings = 3
	var flame_material := StandardMaterial3D.new()
	flame_material.albedo_color = Color.WHITE
	flame_material.vertex_color_use_as_albedo = true
	flame_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.material = flame_material
	fire.draw_pass_1 = flame
	add_child(fire)

func _add_smoke(effect_scale: float) -> void:
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = Vector3.UP * 0.41 * effect_scale
	smoke.amount = maxi(8, roundi(8.0 * effect_scale))
	smoke.lifetime = 2.2
	smoke.randomness = 0.65
	smoke.visibility_aabb = AABB(Vector3(-0.45, -0.1, -0.45) * effect_scale, Vector3(0.9, 1.45, 0.9) * effect_scale)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.11 * effect_scale
	process_material.direction = Vector3.UP
	process_material.spread = 12.0
	process_material.gravity = Vector3(0.0, 0.035, 0.0)
	process_material.initial_velocity_min = 0.16 * effect_scale
	process_material.initial_velocity_max = 0.26 * effect_scale
	process_material.scale_min = 0.75 * effect_scale
	process_material.scale_max = 1.25 * effect_scale
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.45))
	scale_curve.add_point(Vector2(0.45, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.55))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	process_material.scale_curve = scale_texture
	var smoke_gradient := Gradient.new()
	smoke_gradient.colors = PackedColorArray([
		Color(0.66, 0.69, 0.72, 0.34),
		Color(0.62, 0.65, 0.68, 0.0),
	])
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = smoke_gradient
	process_material.color_ramp = gradient_texture
	smoke.process_material = process_material
	var puff := SphereMesh.new()
	puff.radius = 0.055
	puff.height = 0.11
	puff.radial_segments = 6
	puff.rings = 3
	var puff_material := StandardMaterial3D.new()
	puff_material.albedo_color = Color.WHITE
	puff_material.vertex_color_use_as_albedo = true
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = puff_material
	smoke.draw_pass_1 = puff
	add_child(smoke)
