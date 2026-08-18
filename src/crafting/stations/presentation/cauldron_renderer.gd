extends Node3D
class_name CauldronRenderer

const HIGHLIGHT_ALPHA: float = 0.06

var cauldron_instances: Dictionary[Vector3i, Node3D] = {}
var _hovered_position: Variant = null
var _iron_material: StandardMaterial3D
var _liquid_material: StandardMaterial3D
var _wood_material: StandardMaterial3D
var _rope_material: StandardMaterial3D
var _ember_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D
var _placement_preview: Node3D

func setup() -> void:
	_iron_material = _make_iron_material()
	_liquid_material = _make_liquid_material()
	_wood_material = _make_wood_material()
	_rope_material = _make_rope_material()
	_ember_material = _make_ember_material()
	_highlight_material = _make_highlight_material()

func spawn_cauldron(position: Vector3i) -> Node3D:
	remove_cauldron(position)
	var root := _create_cauldron_visual("Cauldron_%d_%d_%d" % [position.x, position.y, position.z])
	root.position = Vector3(position)
	add_child(root)
	cauldron_instances[position] = root
	return root

func remove_cauldron(position: Vector3i) -> bool:
	if not cauldron_instances.has(position):
		return false
	var root := cauldron_instances[position] as Node3D
	if root != null and is_instance_valid(root):
		root.queue_free()
	cauldron_instances.erase(position)
	if _hovered_position == position:
		_hovered_position = null
	return true

func load_cauldrons_for_chunk(cx: int, cz: int, chunk_size: int, voxel_world: VoxelWorld) -> int:
	var loaded := 0
	var origin_x := cx * chunk_size
	var origin_z := cz * chunk_size
	var placed := voxel_world.snapshot_edits_for_chunk(origin_x, origin_z)["placed"] as Dictionary
	for position in placed:
		if placed[position] != BlockId.Type.CAULDRON:
			continue
		if position.x < origin_x or position.x >= origin_x + chunk_size or position.z < origin_z or position.z >= origin_z + chunk_size:
			continue
		if not cauldron_instances.has(position):
			spawn_cauldron(position)
			loaded += 1
	return loaded

func unload_cauldrons_in_chunk(cx: int, cz: int, chunk_size: int) -> int:
	var positions: Array[Vector3i] = []
	for position in cauldron_instances:
		if floori(float(position.x) / chunk_size) == cx and floori(float(position.z) / chunk_size) == cz:
			positions.append(position)
	for position in positions:
		remove_cauldron(position)
	return positions.size()

func set_hovered_cauldron(position: Variant) -> void:
	_hovered_position = position if position is Vector3i and cauldron_instances.has(position) else null
	for cauldron_position in cauldron_instances:
		_set_highlighted(cauldron_instances[cauldron_position] as Node3D, cauldron_position == _hovered_position)

func set_placement_preview(position: Variant, can_place: bool) -> void:
	if position == null:
		if _placement_preview != null:
			_placement_preview.visible = false
		return
	if not position is Vector3i:
		return
	if _placement_preview == null:
		_placement_preview = _create_cauldron_visual("CauldronPlacementPreview", false)
		_set_preview_materials(_placement_preview)
		add_child(_placement_preview)
	_placement_preview.global_position = Vector3(position)
	_placement_preview.visible = true
	_set_preview_opacity(0.48 if can_place else 0.18)

func _create_cauldron_visual(name_value: String, include_effects: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = name_value
	var apex := Vector3(0.5, 0.96, 0.5)
	_add_cylinder_between(root, "SupportLeft", Vector3(0.12, 0.04, 0.28), apex, 0.035, 6, _wood_material)
	_add_cylinder_between(root, "SupportRight", Vector3(0.88, 0.04, 0.28), apex, 0.035, 6, _wood_material)
	_add_cylinder_between(root, "SupportBack", Vector3(0.5, 0.04, 0.93), apex, 0.035, 6, _wood_material)
	_add_cylinder_between(root, "SuspensionLeft", Vector3(0.5, 0.87, 0.5), Vector3(0.34, 0.51, 0.5), 0.010, 4, _rope_material)
	_add_cylinder_between(root, "SuspensionRight", Vector3(0.5, 0.87, 0.5), Vector3(0.66, 0.51, 0.5), 0.010, 4, _rope_material)
	_add_cylinder_between(root, "SuspensionBack", Vector3(0.5, 0.87, 0.5), Vector3(0.5, 0.51, 0.66), 0.010, 4, _rope_material)
	_add_cylinder(root, "Body", 0.12, 0.16, 0.25, 8, Vector3(0.5, 0.36, 0.5), _iron_material)
	_add_cylinder(root, "Rim", 0.19, 0.19, 0.045, 8, Vector3(0.5, 0.505, 0.5), _iron_material)
	_add_cylinder(root, "Liquid", 0.145, 0.145, 0.010, 8, Vector3(0.5, 0.531, 0.5), _liquid_material)
	_add_cylinder_between(root, "FirewoodLeft", Vector3(0.36, 0.08, 0.39), Vector3(0.64, 0.08, 0.61), 0.030, 6, _wood_material)
	_add_cylinder_between(root, "FirewoodRight", Vector3(0.36, 0.09, 0.61), Vector3(0.64, 0.09, 0.39), 0.030, 6, _wood_material)
	_add_sphere(root, "FireCore", 0.07, 0.14, 6, 3, Vector3(0.5, 0.16, 0.5), _ember_material)
	if include_effects:
		_add_fire(root)
		_add_smoke(root)
		_add_fire_light(root)
	return root

func _add_fire(root: Node3D) -> void:
	var fire := GPUParticles3D.new()
	fire.name = "Fire"
	fire.position = Vector3(0.5, 0.17, 0.5)
	fire.amount = 12
	fire.lifetime = 0.7
	fire.randomness = 0.72
	fire.visibility_aabb = AABB(Vector3(-0.3, -0.1, -0.3), Vector3(0.6, 0.65, 0.6))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.075
	process_material.direction = Vector3.UP
	process_material.spread = 24.0
	process_material.gravity = Vector3(0.0, 0.08, 0.0)
	process_material.initial_velocity_min = 0.12
	process_material.initial_velocity_max = 0.24
	process_material.scale_min = 0.65
	process_material.scale_max = 1.15
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
	root.add_child(fire)

func _add_smoke(root: Node3D) -> void:
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = Vector3(0.5, 0.58, 0.5)
	smoke.amount = 8
	smoke.lifetime = 2.2
	smoke.randomness = 0.65
	smoke.visibility_aabb = AABB(Vector3(-0.45, -0.1, -0.45), Vector3(0.9, 1.45, 0.9))
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.11
	process_material.direction = Vector3.UP
	process_material.spread = 12.0
	process_material.gravity = Vector3(0.0, 0.035, 0.0)
	process_material.initial_velocity_min = 0.16
	process_material.initial_velocity_max = 0.26
	process_material.scale_min = 0.75
	process_material.scale_max = 1.25
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
	puff_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	puff_material.vertex_color_use_as_albedo = true
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = puff_material
	smoke.draw_pass_1 = puff
	root.add_child(smoke)

func _add_fire_light(root: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.position = Vector3(0.5, 0.28, 0.5)
	light.light_color = Color(1.0, 0.54, 0.24, 1.0)
	light.light_energy = 0.5
	light.omni_range = 4.0
	light.omni_attenuation = 1.15
	light.shadow_enabled = false
	root.add_child(light)

func _add_cylinder_between(root: Node3D, name_value: String, start: Vector3, end: Vector3, radius: float, radial_segments: int, material: Material) -> void:
	var direction := end - start
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius
	mesh.height = direction.length()
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = (start + end) * 0.5
	instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	instance.material_override = material
	root.add_child(instance)

func _add_cylinder(root: Node3D, name_value: String, bottom_radius: float, top_radius: float, height: float, radial_segments: int, position_value: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	root.add_child(instance)

func _add_sphere(root: Node3D, name_value: String, radius: float, height: float, radial_segments: int, rings: int, position_value: Vector3, material: Material) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	root.add_child(instance)

func _make_iron_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.18, 0.20, 0.22, 1.0)
	material.metallic = 0.12
	material.roughness = 0.88
	return material

func _make_liquid_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.24, 0.05, 0.08, 1.0)
	material.metallic = 0.0
	material.roughness = 0.72
	return material

func _make_wood_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.32, 0.19, 0.09, 1.0)
	material.roughness = 0.95
	return material

func _make_rope_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.09, 0.07, 0.05, 1.0)
	material.roughness = 1.0
	return material

func _make_ember_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.20, 0.03, 1.0)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.13, 0.01, 1.0)
	material.emission_energy_multiplier = 1.1
	material.roughness = 0.65
	return material

func _make_highlight_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.92, 0.96, 1.0, HIGHLIGHT_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material

func _get_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			meshes.append(child as MeshInstance3D)
		meshes.append_array(_get_meshes(child))
	return meshes

func _set_highlighted(root: Node3D, highlighted: bool) -> void:
	for mesh in _get_meshes(root):
		mesh.material_overlay = _highlight_material if highlighted else null

func _set_preview_materials(root: Node3D) -> void:
	for mesh in _get_meshes(root):
		var material := mesh.material_override.duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material

func _set_preview_opacity(opacity: float) -> void:
	for mesh in _get_meshes(_placement_preview):
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color.a = opacity
