extends Node3D
class_name StructureMetadataOverlay

const SOCKET_COLOR := Color(0.12, 0.9, 1.0, 0.48)
const SPAWN_COLOR := Color(0.2, 1.0, 0.36, 0.78)
const RETURN_COLOR := Color(1.0, 0.52, 0.12, 0.78)
const ENEMY_SPAWN_ZONE_COLOR := Color(0.72, 0.24, 1.0, 0.42)

var _draft: StructureDraft

func setup(draft: StructureDraft) -> void:
	assert(draft != null)
	assert(_draft == null)
	_draft = draft
	rebuild()

func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if _draft.get_format() != StructureDraft.Format.LEVEL_MODULE:
		return
	for socket in _draft.get_sockets():
		_add_socket(socket)
	for zone in _draft.get_enemy_spawn_zones():
		_add_enemy_spawn_zone(zone)
	var spawn_marker := _draft.get_spawn_marker()
	var return_marker := _draft.get_return_door_marker()
	if spawn_marker != null:
		_add_marker("Spawn", spawn_marker.cell, spawn_marker.facing, SPAWN_COLOR)
	if return_marker != null:
		_add_marker("Return", return_marker.cell, return_marker.facing, RETURN_COLOR)

func rebuild_non_zone_metadata() -> void:
	for child in get_children():
		if not String(child.name).begins_with("EnemySpawnZone_"):
			remove_child(child)
			child.queue_free()
	if _draft.get_format() != StructureDraft.Format.LEVEL_MODULE:
		return
	for socket in _draft.get_sockets():
		_add_socket(socket)
	var spawn_marker := _draft.get_spawn_marker()
	var return_marker := _draft.get_return_door_marker()
	if spawn_marker != null:
		_add_marker("Spawn", spawn_marker.cell, spawn_marker.facing, SPAWN_COLOR)
	if return_marker != null:
		_add_marker("Return", return_marker.cell, return_marker.facing, RETURN_COLOR)

func rebuild_enemy_spawn_zone(zone_id: StringName) -> void:
	var node_name := "EnemySpawnZone_%s" % zone_id
	var existing := get_node_or_null(node_name)
	if existing != null:
		remove_child(existing)
		existing.queue_free()
	var zone := _draft.get_enemy_spawn_zone(zone_id)
	if zone != null:
		_add_enemy_spawn_zone(zone)

func _add_socket(socket: LevelSocketDefinition) -> void:
	var root := Node3D.new()
	root.name = "Socket_%s" % socket.socket_id
	add_child(root)
	var material := _make_material(SOCKET_COLOR)
	var aperture_cells := _draft.get_socket_aperture_cells(socket.socket_id)
	var aperture_mesh := BoxMesh.new()
	aperture_mesh.size = Vector3.ONE * 0.92
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = aperture_mesh
	multimesh.instance_count = aperture_cells.size()
	var center := Vector3.ZERO
	for index in aperture_cells.size():
		var position := Vector3(aperture_cells[index]) + Vector3.ONE * 0.5
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, position))
		center += position
	var aperture := MultiMeshInstance3D.new()
	aperture.name = "Aperture"
	aperture.multimesh = multimesh
	aperture.material_override = material
	aperture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(aperture)
	center /= float(aperture_cells.size())
	_add_arrow(root, center, LevelSocketDefinition.vector_for(socket.direction), material)

func _add_marker(label: String, cell: Vector3i, facing: LevelSocketDefinition.Direction, color: Color) -> void:
	var root := Node3D.new()
	root.name = "%sMarker" % label
	add_child(root)
	var material := _make_material(color)
	var marker := MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.18
	marker_mesh.bottom_radius = 0.34
	marker_mesh.height = 0.12
	marker.mesh = marker_mesh
	marker.position = Vector3(cell) + Vector3(0.5, 0.08, 0.5)
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(marker)
	_add_arrow(root, Vector3(cell) + Vector3(0.5, 0.18, 0.5), LevelSocketDefinition.vector_for(facing), material)

func _add_enemy_spawn_zone(zone: LevelEnemySpawnZone) -> void:
	var root := Node3D.new()
	root.name = "EnemySpawnZone_%s" % zone.zone_id
	add_child(root)
	var candidates := _draft.get_enemy_spawn_zone_candidate_cells(zone.zone_id)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.86, 0.055, 0.86)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = candidates.size()
	for index in candidates.size():
		multimesh.set_instance_transform(
			index,
			Transform3D(Basis.IDENTITY, Vector3(candidates[index]) + Vector3(0.5, 0.035, 0.5)),
		)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Candidates"
	instance.multimesh = multimesh
	instance.material_override = _make_material(ENEMY_SPAWN_ZONE_COLOR)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)

func _add_arrow(root: Node3D, origin: Vector3, direction: Vector3i, material: Material) -> void:
	var shaft := MeshInstance3D.new()
	var shaft_mesh := BoxMesh.new()
	shaft_mesh.size = Vector3(0.12, 0.08, 0.72)
	shaft.mesh = shaft_mesh
	shaft.position = origin + Vector3(direction) * 0.36
	shaft.rotation.y = PI * 0.5 if direction.x != 0 else 0.0
	shaft.material_override = material
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var head_mesh := CylinderMesh.new()
	head_mesh.top_radius = 0.0
	head_mesh.bottom_radius = 0.22
	head_mesh.height = 0.38
	head_mesh.radial_segments = 4
	head.mesh = head_mesh
	head.position = origin + Vector3(direction) * 0.78
	head.rotation.x = PI * 0.5
	head.rotation.y = atan2(float(direction.x), float(direction.z))
	head.material_override = material
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(head)

func _make_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b)
	material.emission_energy_multiplier = 0.8
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material
