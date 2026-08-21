extends RefCounted
class_name BlockOutlineBuilder

const EDGE_THICKNESS: float = 0.045
const HALF_SIZE: float = 0.5125
const EDGE_LENGTH: float = 1.025

static func create_outline(name: String, material: Material) -> Node3D:
	var outline := Node3D.new()
	outline.name = name
	var edges := [
		{"size": Vector3(EDGE_LENGTH, EDGE_THICKNESS, EDGE_THICKNESS), "position": Vector3(0.0, HALF_SIZE, HALF_SIZE)},
		{"size": Vector3(EDGE_LENGTH, EDGE_THICKNESS, EDGE_THICKNESS), "position": Vector3(0.0, HALF_SIZE, -HALF_SIZE)},
		{"size": Vector3(EDGE_LENGTH, EDGE_THICKNESS, EDGE_THICKNESS), "position": Vector3(0.0, -HALF_SIZE, HALF_SIZE)},
		{"size": Vector3(EDGE_LENGTH, EDGE_THICKNESS, EDGE_THICKNESS), "position": Vector3(0.0, -HALF_SIZE, -HALF_SIZE)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_LENGTH, EDGE_THICKNESS), "position": Vector3(HALF_SIZE, 0.0, HALF_SIZE)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_LENGTH, EDGE_THICKNESS), "position": Vector3(HALF_SIZE, 0.0, -HALF_SIZE)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_LENGTH, EDGE_THICKNESS), "position": Vector3(-HALF_SIZE, 0.0, HALF_SIZE)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_LENGTH, EDGE_THICKNESS), "position": Vector3(-HALF_SIZE, 0.0, -HALF_SIZE)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_THICKNESS, EDGE_LENGTH), "position": Vector3(HALF_SIZE, HALF_SIZE, 0.0)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_THICKNESS, EDGE_LENGTH), "position": Vector3(HALF_SIZE, -HALF_SIZE, 0.0)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_THICKNESS, EDGE_LENGTH), "position": Vector3(-HALF_SIZE, HALF_SIZE, 0.0)},
		{"size": Vector3(EDGE_THICKNESS, EDGE_THICKNESS, EDGE_LENGTH), "position": Vector3(-HALF_SIZE, -HALF_SIZE, 0.0)},
	]
	for edge in edges:
		var mesh_instance := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = edge["size"] as Vector3
		mesh_instance.mesh = mesh
		mesh_instance.position = edge["position"] as Vector3
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh_instance.material_override = material
		outline.add_child(mesh_instance)
	return outline
