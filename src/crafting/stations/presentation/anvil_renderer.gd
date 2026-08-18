extends Node3D
class_name AnvilRenderer

const HIGHLIGHT_ALPHA: float = 0.06

var anvil_instances: Dictionary[Vector3i, Node3D] = {}
var _hovered_position: Variant = null
var _base_material: StandardMaterial3D
var _highlight_material: StandardMaterial3D
var _placement_preview: Node3D

func setup() -> void:
	_base_material = _make_base_material()
	_highlight_material = _make_highlight_material()

func spawn_anvil(position: Vector3i) -> Node3D:
	remove_anvil(position)
	var root := _create_anvil_visual("Anvil_%d_%d_%d" % [position.x, position.y, position.z])
	root.position = Vector3(position)
	add_child(root)
	anvil_instances[position] = root
	return root

func remove_anvil(position: Vector3i) -> bool:
	if not anvil_instances.has(position):
		return false
	var root := anvil_instances[position] as Node3D
	if root != null and is_instance_valid(root):
		root.queue_free()
	anvil_instances.erase(position)
	if _hovered_position == position:
		_hovered_position = null
	return true

func load_anvils_for_chunk(cx: int, cz: int, chunk_size: int, voxel_world: VoxelWorld) -> int:
	var loaded := 0
	var origin_x := cx * chunk_size
	var origin_z := cz * chunk_size
	var placed := voxel_world.snapshot_edits_for_chunk(origin_x, origin_z)["placed"] as Dictionary
	for position in placed:
		if placed[position] != BlockId.Type.ANVIL:
			continue
		if position.x < origin_x or position.x >= origin_x + chunk_size or position.z < origin_z or position.z >= origin_z + chunk_size:
			continue
		if not anvil_instances.has(position):
			spawn_anvil(position)
			loaded += 1
	return loaded

func unload_anvils_in_chunk(cx: int, cz: int, chunk_size: int) -> int:
	var positions: Array[Vector3i] = []
	for position in anvil_instances:
		if floori(float(position.x) / chunk_size) == cx and floori(float(position.z) / chunk_size) == cz:
			positions.append(position)
	for position in positions:
		remove_anvil(position)
	return positions.size()

func set_hovered_anvil(position: Variant) -> void:
	_hovered_position = position if position is Vector3i and anvil_instances.has(position) else null
	for anvil_position in anvil_instances:
		_set_highlighted(anvil_instances[anvil_position] as Node3D, anvil_position == _hovered_position)

func set_placement_preview(position: Variant, can_place: bool) -> void:
	if position == null:
		if _placement_preview != null:
			_placement_preview.visible = false
		return
	if not position is Vector3i:
		return
	if _placement_preview == null:
		_placement_preview = _create_anvil_visual("AnvilPlacementPreview")
		_set_preview_materials(_placement_preview)
		add_child(_placement_preview)
	_placement_preview.global_position = Vector3(position)
	_placement_preview.visible = true
	_set_preview_opacity(0.48 if can_place else 0.18)

func _create_anvil_visual(name_value: String) -> Node3D:
	var root := Node3D.new()
	root.name = name_value
	_add_box(root, "Base", Vector3(0.72, 0.18, 0.62), Vector3(0.42, 0.09, 0.50))
	_add_box(root, "Stem", Vector3(0.32, 0.42, 0.34), Vector3(0.43, 0.36, 0.50))
	_add_box(root, "Top", Vector3(0.68, 0.18, 0.40), Vector3(0.38, 0.66, 0.50))
	var horn := MeshInstance3D.new()
	horn.name = "Horn"
	horn.mesh = _create_horn_mesh()
	horn.material_override = _base_material
	root.add_child(horn)
	return root

func _create_horn_mesh() -> ArrayMesh:
	var base_top_back := Vector3(0.66, 0.75, 0.32)
	var base_top_front := Vector3(0.66, 0.75, 0.68)
	var base_bottom_back := Vector3(0.66, 0.55, 0.34)
	var base_bottom_front := Vector3(0.66, 0.55, 0.66)
	var tip := Vector3(0.99, 0.75, 0.50)
	var triangles := [
		[base_top_back, base_top_front, tip],
		[base_top_front, base_bottom_front, tip],
		[base_bottom_back, tip, base_bottom_front],
		[base_top_back, tip, base_bottom_back],
		[base_top_back, base_bottom_back, base_bottom_front],
		[base_top_back, base_bottom_front, base_top_front],
	]
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in triangles:
		var normal := Plane(triangle[0], triangle[1], triangle[2]).normal
		for vertex in triangle:
			surface_tool.set_normal(normal)
			surface_tool.add_vertex(vertex)
	return surface_tool.commit()

func _add_box(root: Node3D, name_value: String, size: Vector3, position_value: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = _base_material
	root.add_child(instance)

func _make_base_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.35, 0.37, 0.39, 1.0)
	material.metallic = 0.08
	material.roughness = 0.86
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
