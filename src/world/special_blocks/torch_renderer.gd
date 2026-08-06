extends Node3D
class_name TorchRenderer

const MAX_SHADOW_TORCHES: int = 4
const TORCH_SHADOW_UPDATE_INTERVAL: float = 0.6
# Light Y is flame base, independent of wall offset.
# Stem: size 0.45 centered at 0.05 => spans -0.175 to 0.275
# Flame: size 0.14 centered at 0.38 => spans 0.31 to 0.45
const TORCH_LIGHT_Y: float = 0.32

var torch_instances: Dictionary = {}
var torch_light_nodes: Dictionary = {}

var torch_base_material: StandardMaterial3D
var torch_flame_material: StandardMaterial3D
var torch_stem_mesh: BoxMesh
var torch_flame_mesh: BoxMesh

var _shadow_update_timer: float = 0.5
var _shadow_pool_limited: bool = false
var player_ref: Node3D

var block_catalog: BlockCatalog

func setup(p_block_catalog: BlockCatalog):
	block_catalog = p_block_catalog
	_setup_materials_and_meshes()

func _setup_materials_and_meshes():
	var def = block_catalog.get_definition(BlockId.Type.TORCH)
	var flame_col = def.emissive_color

	torch_base_material = StandardMaterial3D.new()
	torch_base_material.albedo_texture = def.side_texture
	torch_base_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	torch_base_material.roughness = 0.9

	torch_flame_material = StandardMaterial3D.new()
	torch_flame_material.albedo_color = flame_col
	torch_flame_material.emission_enabled = true
	torch_flame_material.emission = flame_col
	torch_flame_material.emission_energy_multiplier = def.emissive_energy
	torch_flame_material.roughness = 0.6

	torch_stem_mesh = BoxMesh.new()
	torch_stem_mesh.size = Vector3(0.08, 0.45, 0.08)
	torch_flame_mesh = BoxMesh.new()
	torch_flame_mesh.size = Vector3(0.14, 0.14, 0.14)

func spawn_torch(pos: Vector3i, attach_dir: Vector3i) -> Node3D:
	remove_torch(pos)

	var root = Node3D.new()
	root.name = "Torch_%d_%d_%d" % [pos.x, pos.y, pos.z]
	root.position = TorchPlacement.world_position(pos, attach_dir)
	add_child(root)

	var stem = MeshInstance3D.new()
	stem.mesh = torch_stem_mesh
	stem.position = Vector3(0, 0.05, 0)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stem.material_override = torch_base_material
	root.add_child(stem)

	var flame = MeshInstance3D.new()
	flame.mesh = torch_flame_mesh
	flame.position = Vector3(0, 0.38, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.material_override = torch_flame_material
	root.add_child(flame)

	var def = block_catalog.get_definition(BlockId.Type.TORCH)
	var light = OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = def.light_color
	light.light_energy = def.emissive_energy
	light.omni_range = def.light_range
	light.omni_attenuation = 0.75
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.shadow_enabled = true
	light.shadow_reverse_cull_face = false
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 0.2
	light.shadow_opacity = 0.5
	light.shadow_blur = 1.0
	light.position = Vector3(0, TORCH_LIGHT_Y, 0)
	root.add_child(light)

	torch_instances[pos] = root
	torch_light_nodes[pos] = light
	return root

func remove_torch(pos: Vector3i) -> bool:
	if torch_instances.has(pos):
		var n = torch_instances[pos] as Node3D
		if n and is_instance_valid(n):
			n.queue_free()
		torch_instances.erase(pos)
		torch_light_nodes.erase(pos)
		return true
	torch_light_nodes.erase(pos)
	return false

func has_torch(pos: Vector3i) -> bool:
	return torch_instances.has(pos)

func unload_torches_in_chunk(cx: int, cz: int, p_chunk_size: int) -> int:
	var removed = 0
	var to_remove: Array[Vector3i] = []
	for pos in torch_instances.keys():
		var torch_cx = int(floor(float(pos.x) / float(p_chunk_size)))
		var torch_cz = int(floor(float(pos.z) / float(p_chunk_size)))
		if torch_cx == cx and torch_cz == cz:
			to_remove.append(pos)
	for pos in to_remove:
		remove_torch(pos)
		removed += 1
	return removed

func load_torches_for_chunk(cx: int, cz: int, p_chunk_size: int, torch_attachments: Dictionary) -> int:
	var loaded = 0
	var origin_x = cx * p_chunk_size
	var origin_z = cz * p_chunk_size
	for torch_pos in torch_attachments.keys():
		if torch_pos.x >= origin_x and torch_pos.x < origin_x + p_chunk_size and torch_pos.z >= origin_z and torch_pos.z < origin_z + p_chunk_size:
			if has_torch(torch_pos):
				continue
			var dir = torch_attachments[torch_pos] as Vector3i
			spawn_torch(torch_pos, dir)
			loaded += 1
	return loaded

func update_shadow_culling(delta: float) -> void:
	_shadow_update_timer -= delta
	if _shadow_update_timer > 0:
		return
	_shadow_update_timer = TORCH_SHADOW_UPDATE_INTERVAL

	if torch_instances.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		return

	if player_ref != null and torch_light_nodes.size() > MAX_SHADOW_TORCHES:
		_shadow_pool_limited = true
		_apply_shadow_pool_limit()
	elif _shadow_pool_limited:
		_shadow_pool_limited = false
		for light in torch_light_nodes.values():
			if light and is_instance_valid(light):
				light.shadow_enabled = true

func _apply_shadow_pool_limit():
	if player_ref == null:
		return
	var positions = torch_light_nodes.keys()
	var player_position = player_ref.global_position
	positions.sort_custom(func(a, b):
		return player_position.distance_squared_to(Vector3(a)) < player_position.distance_squared_to(Vector3(b))
	)
	for i in range(positions.size()):
		var pos = positions[i] as Vector3i
		var light = torch_light_nodes.get(pos) as OmniLight3D
		if not light or not is_instance_valid(light):
			continue
		light.shadow_enabled = i < MAX_SHADOW_TORCHES

func set_player_ref(p: Node3D):
	player_ref = p
