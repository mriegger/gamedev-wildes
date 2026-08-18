extends Node3D
class_name ChestRenderer

const LID_HEIGHT: float = 0.28
const LID_OPEN_ANGLE: float = 18.0
const LID_ANIMATION_SPEED: float = 4.5
const HIGHLIGHT_ALPHA: float = 0.08
const HIGHLIGHT_MESH_PATHS: Array[NodePath] = [
	^"Body/Front",
	^"Body/Back",
	^"Body/Left",
	^"Body/Right",
	^"Body/Bottom",
	^"Interior",
	^"Lid/Shell",
	^"Lid/Front",
	^"Lid/Top",
]
const BODY_SIDE_TEXTURE: Texture2D = preload("res://assets/textures/blocks/chest_body_side.png")
const BODY_FRONT_TEXTURE: Texture2D = preload("res://assets/textures/blocks/chest_body_front.png")
const LID_SIDE_TEXTURE: Texture2D = preload("res://assets/textures/blocks/chest_lid_side.png")
const LID_FRONT_TEXTURE: Texture2D = preload("res://assets/textures/blocks/chest_lid_front.png")

var chest_instances: Dictionary[Vector3i, Node3D] = {}
var block_catalog: BlockCatalog
var _hovered_position: Variant = null
var _lid_progress: Dictionary[Vector3i, float] = {}
var _highlight_material: StandardMaterial3D
var _placement_preview: Node3D

func setup(p_block_catalog: BlockCatalog):
	assert(p_block_catalog != null)
	block_catalog = p_block_catalog
	_highlight_material = _make_highlight_material()
	set_process(true)

func spawn_chest(position: Vector3i) -> Node3D:
	remove_chest(position)
	var root := _create_chest_visual("Chest_%d_%d_%d" % [position.x, position.y, position.z])
	root.position = Vector3(position)
	add_child(root)
	chest_instances[position] = root
	_lid_progress[position] = 0.0
	return root

func set_placement_preview(position: Variant, can_place: bool) -> void:
	if position == null:
		if _placement_preview != null:
			_placement_preview.visible = false
		return
	if not position is Vector3i:
		return
	if _placement_preview == null:
		_placement_preview = _create_chest_visual("ChestPlacementPreview")
		_set_preview_materials(_placement_preview)
		add_child(_placement_preview)
	_placement_preview.global_position = Vector3(position)
	_placement_preview.visible = true
	_set_preview_opacity(0.48 if can_place else 0.18)

func _create_chest_visual(name_value: String) -> Node3D:
	var definition := block_catalog.get_definition(BlockId.Type.CHEST)
	var root := Node3D.new()
	root.name = name_value
	var body_height := 1.0 - LID_HEIGHT
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	body.add_child(_make_body_face("Front", Vector2(1.0, body_height), Vector3(0.5, body_height * 0.5, 0.0), Vector3(0.0, PI, 0.0), BODY_FRONT_TEXTURE))
	body.add_child(_make_body_face("Back", Vector2(1.0, body_height), Vector3(0.5, body_height * 0.5, 1.0), Vector3.ZERO, BODY_SIDE_TEXTURE))
	body.add_child(_make_body_face("Left", Vector2(1.0, body_height), Vector3(0.0, body_height * 0.5, 0.5), Vector3(0.0, -PI * 0.5, 0.0), BODY_SIDE_TEXTURE))
	body.add_child(_make_body_face("Right", Vector2(1.0, body_height), Vector3(1.0, body_height * 0.5, 0.5), Vector3(0.0, PI * 0.5, 0.0), BODY_SIDE_TEXTURE))
	body.add_child(_make_body_face("Bottom", Vector2(1.0, 1.0), Vector3(0.5, 0.0, 0.5), Vector3(PI * 0.5, 0.0, 0.0), BODY_SIDE_TEXTURE))
	var interior_mesh := PlaneMesh.new()
	interior_mesh.size = Vector2(1.0, 1.0)
	var interior := MeshInstance3D.new()
	interior.name = "Interior"
	interior.mesh = interior_mesh
	interior.position = Vector3(0.5, body_height + 0.002, 0.5)
	var interior_material := StandardMaterial3D.new()
	interior_material.albedo_color = Color(0.055, 0.038, 0.025, 1.0)
	interior_material.roughness = 1.0
	interior_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	interior.material_override = interior_material
	root.add_child(interior)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0.5, body_height, 1.0)
	root.add_child(lid)
	var lid_shell := MeshInstance3D.new()
	lid_shell.name = "Shell"
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.0, LID_HEIGHT, 1.0)
	lid_shell.mesh = lid_mesh
	lid_shell.position = Vector3(0.0, LID_HEIGHT * 0.5, -0.5)
	lid_shell.material_override = _make_texture_material(LID_SIDE_TEXTURE)
	lid.add_child(lid_shell)
	var lid_front := _make_front_face("Front", LID_HEIGHT, LID_HEIGHT * 0.5, -1.001, LID_FRONT_TEXTURE)
	lid.add_child(lid_front)
	var lid_top_mesh := PlaneMesh.new()
	lid_top_mesh.size = Vector2(1.0, 1.0)
	var lid_top := MeshInstance3D.new()
	lid_top.name = "Top"
	lid_top.mesh = lid_top_mesh
	lid_top.position = Vector3(0.0, LID_HEIGHT + 0.001, -0.5)
	lid_top.material_override = _make_texture_material(definition.top_texture)
	lid.add_child(lid_top)
	return root

func remove_chest(position: Vector3i) -> bool:
	if not chest_instances.has(position):
		return false
	var root := chest_instances[position] as Node3D
	if root != null and is_instance_valid(root):
		root.queue_free()
	chest_instances.erase(position)
	_lid_progress.erase(position)
	if _hovered_position == position:
		_hovered_position = null
	return true

func load_chests_for_chunk(cx: int, cz: int, chunk_size: int, voxel_world: VoxelWorld) -> int:
	var loaded := 0
	var origin_x := cx * chunk_size
	var origin_z := cz * chunk_size
	var placed := voxel_world.snapshot_block_edits()["placed"] as Dictionary
	for position in placed:
		if placed[position] != BlockId.Type.CHEST:
			continue
		if position.x < origin_x or position.x >= origin_x + chunk_size or position.z < origin_z or position.z >= origin_z + chunk_size:
			continue
		if not chest_instances.has(position):
			spawn_chest(position)
			loaded += 1
	return loaded

func unload_chests_in_chunk(cx: int, cz: int, chunk_size: int) -> int:
	var positions: Array[Vector3i] = []
	for position in chest_instances:
		if floori(float(position.x) / chunk_size) == cx and floori(float(position.z) / chunk_size) == cz:
			positions.append(position)
	for position in positions:
		remove_chest(position)
	return positions.size()

func set_hovered_chest(position: Variant):
	_hovered_position = position if position is Vector3i and chest_instances.has(position) else null
	for chest_position in chest_instances:
		var root := chest_instances[chest_position] as Node3D
		_set_highlighted(root, chest_position == _hovered_position)

func get_lid(position: Vector3i) -> Node3D:
	if not chest_instances.has(position):
		return null
	return (chest_instances[position] as Node3D).get_node("Lid") as Node3D

func _process(delta: float):
	for position in chest_instances:
		var target := 1.0 if position == _hovered_position else 0.0
		var progress := move_toward(float(_lid_progress.get(position, 0.0)), target, delta * LID_ANIMATION_SPEED)
		_lid_progress[position] = progress
		get_lid(position).rotation.x = deg_to_rad(LID_OPEN_ANGLE) * progress

func _make_front_face(name_value: String, height: float, center_y: float, z: float, texture: Texture2D) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, height)
	var face := MeshInstance3D.new()
	face.name = name_value
	face.mesh = mesh
	face.position = Vector3(0.0, center_y, z)
	face.rotation.y = PI
	face.material_override = _make_texture_material(texture)
	return face

func _make_body_face(name_value: String, size: Vector2, position_value: Vector3, rotation_value: Vector3, texture: Texture2D) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var face := MeshInstance3D.new()
	face.name = name_value
	face.mesh = mesh
	face.position = position_value
	face.rotation = rotation_value
	face.material_override = _make_texture_material(texture)
	return face

func _make_texture_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _make_highlight_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(1.0, 0.96, 0.82, HIGHLIGHT_ALPHA)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

func _set_highlighted(root: Node3D, highlighted: bool) -> void:
	for path in HIGHLIGHT_MESH_PATHS:
		var mesh := root.get_node(path) as MeshInstance3D
		mesh.material_overlay = _highlight_material if highlighted else null

func _set_preview_materials(root: Node3D) -> void:
	for path in HIGHLIGHT_MESH_PATHS:
		var mesh := root.get_node(path) as MeshInstance3D
		var material := mesh.material_override.duplicate() as StandardMaterial3D
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material

func _set_preview_opacity(opacity: float) -> void:
	for path in HIGHLIGHT_MESH_PATHS:
		var mesh := _placement_preview.get_node(path) as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color.a = opacity
