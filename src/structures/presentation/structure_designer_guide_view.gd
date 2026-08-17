extends Node3D
class_name StructureDesignerGuideView

const LINE_THICKNESS: float = 0.035

var _preview: MeshInstance3D
var _valid_preview_material: StandardMaterial3D
var _invalid_preview_material: StandardMaterial3D

func setup(size: Vector3i) -> void:
	assert(size.x > 0 and size.y > 0 and size.z > 0)
	_create_floor(size)
	_create_bounds(size)
	_create_preview()

func show_preview(cell: Vector3i, valid: bool) -> void:
	_preview.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	_preview.material_override = _valid_preview_material if valid else _invalid_preview_material
	_preview.visible = true

func clear_preview() -> void:
	_preview.visible = false

func _create_floor(size: Vector3i) -> void:
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(size.x, 0.05, size.z)
	var floor_material := StandardMaterial3D.new()
	floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_material.albedo_color = Color(0.28, 0.58, 0.72, 0.24)
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_instance := MeshInstance3D.new()
	floor_instance.name = "GuideFloor"
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = floor_material
	floor_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	floor_instance.position = Vector3(float(size.x) * 0.5, -0.025, float(size.z) * 0.5)
	add_child(floor_instance)

func _create_bounds(size: Vector3i) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.42, 0.82, 1.0, 0.72)
	material.emission_enabled = true
	material.emission = Color(0.18, 0.55, 0.8)
	material.emission_energy_multiplier = 0.7
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var x_length := float(size.x)
	var y_length := float(size.y)
	var z_length := float(size.z)
	for y in [0.0, y_length]:
		for z in [0.0, z_length]:
			_add_line(Vector3(x_length * 0.5, y, z), Vector3(x_length, LINE_THICKNESS, LINE_THICKNESS), material)
	for x in [0.0, x_length]:
		for z in [0.0, z_length]:
			_add_line(Vector3(x, y_length * 0.5, z), Vector3(LINE_THICKNESS, y_length, LINE_THICKNESS), material)
	for x in [0.0, x_length]:
		for y in [0.0, y_length]:
			_add_line(Vector3(x, y, z_length * 0.5), Vector3(LINE_THICKNESS, LINE_THICKNESS, z_length), material)

func _add_line(position: Vector3, line_size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = line_size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = position
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _create_preview() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE * 1.012
	_valid_preview_material = _make_preview_material(Color(0.22, 1.0, 0.48, 0.36))
	_invalid_preview_material = _make_preview_material(Color(1.0, 0.2, 0.18, 0.4))
	_preview = MeshInstance3D.new()
	_preview.name = "PlacementPreview"
	_preview.mesh = mesh
	_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_preview.visible = false
	add_child(_preview)

func _make_preview_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material
