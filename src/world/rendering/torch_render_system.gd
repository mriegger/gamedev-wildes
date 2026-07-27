extends RefCounted
class_name TorchRenderSystem

## TorchRenderSystem - displays torches, uses BlockCatalog cache, no duplicate opacity rules

const TORCH_OMNI_RANGE: float = 9.0
const MAX_SHADOW_TORCHES: int = 4
const TORCH_SHADOW_UPDATE_INTERVAL: float = 0.6

var torch_container: Node3D

var torch_instances: Dictionary = {} # Vector3i -> Node3D visual
var torch_light_nodes: Dictionary = {} # Vector3i -> OmniLight3D

var torch_base_material: StandardMaterial3D
var torch_flame_material: StandardMaterial3D
var torch_stem_mesh: BoxMesh
var torch_flame_mesh: BoxMesh

var _shadow_update_timer: float = 0.5
var player_ref: Node3D

var catalog: BlockCatalog

func _init(p_container: Node3D = null):
	torch_container = p_container
	catalog = BlockCatalog.shared()
	_setup_materials_and_meshes()

func setup(p_container: Node3D, p_player: Node3D = null):
	torch_container = p_container
	player_ref = p_player
	if torch_base_material == null:
		_setup_materials_and_meshes()

func _setup_materials_and_meshes():
	var def = catalog.get_definition(BlockId.Type.TORCH)
	var base_col = def.side_color if def else Color(0.78, 0.62, 0.42)
	var flame_col = def.emissive_color if def and def.emissive_enabled else Color(1.0, 0.92, 0.68)

	torch_base_material = StandardMaterial3D.new()
	torch_base_material.albedo_color = base_col
	torch_base_material.roughness = 0.9

	torch_flame_material = StandardMaterial3D.new()
	torch_flame_material.albedo_color = flame_col
	torch_flame_material.emission_enabled = true
	torch_flame_material.emission = flame_col
	torch_flame_material.emission_energy_multiplier = def.emissive_energy if def else 1.2
	torch_flame_material.roughness = 0.6

	torch_stem_mesh = BoxMesh.new()
	torch_stem_mesh.size = Vector3(0.08, 0.45, 0.08)
	torch_flame_mesh = BoxMesh.new()
	torch_flame_mesh.size = Vector3(0.14, 0.14, 0.14)

func clear():
	for pos in torch_instances.keys():
		var n = torch_instances[pos] as Node3D
		if n and is_instance_valid(n):
			n.queue_free()
	torch_instances.clear()
	torch_light_nodes.clear()

func spawn_torch(pos: Vector3i, attach_dir: Vector3i = Vector3i.ZERO) -> Node3D:
	if torch_container == null:
		return null
	remove_torch(pos)

	var root = Node3D.new()
	root.name = "Torch_%d_%d_%d" % [pos.x, pos.y, pos.z]
	var base_pos = Vector3(pos.x + 0.5, pos.y + 0.5, pos.z + 0.5)
	if attach_dir != Vector3i.ZERO:
		var off = Vector3(attach_dir.x, attach_dir.y, attach_dir.z) * 0.32
		base_pos += off
		if attach_dir == Vector3i.DOWN:
			base_pos.y = pos.y + 0.15
	root.position = base_pos
	torch_container.add_child(root)

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

	var def = catalog.get_definition(BlockId.Type.TORCH)
	var light = OmniLight3D.new()
	light.name = "TorchLight"
	light.light_color = def.light_color if def and def.light_color.a > 0 else Color(1.0, 0.96, 0.88)
	light.light_energy = def.emissive_energy if def else 0.72
	light.omni_range = def.light_range if def and def.light_range > 0 else TORCH_OMNI_RANGE
	light.omni_attenuation = 0.75
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.shadow_enabled = true
	light.shadow_reverse_cull_face = false
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 0.2
	light.shadow_opacity = 0.5
	light.shadow_blur = 1.0
	light.position = Vector3(0, 0.32, 0)
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

func get_torch_count() -> int:
	return torch_instances.size()

func update_shadow_culling(_delta: float) -> void:
	_shadow_update_timer -= _delta
	if _shadow_update_timer > 0:
		return
	_shadow_update_timer = TORCH_SHADOW_UPDATE_INTERVAL

	if torch_instances.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		return

	for tpos in torch_light_nodes.keys():
		var light = torch_light_nodes[tpos] as OmniLight3D
		if not light or not is_instance_valid(light):
			continue
		light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
		light.shadow_enabled = true
		light.shadow_reverse_cull_face = false
		light.shadow_bias = 0.03
		light.shadow_normal_bias = 0.2
		light.shadow_opacity = 0.5
		light.shadow_blur = 1.0

	if player_ref != null and torch_light_nodes.size() > MAX_SHADOW_TORCHES:
		_apply_shadow_pool_limit()

func _apply_shadow_pool_limit():
	if player_ref == null:
		return
	var list: Array = []
	for pos in torch_light_nodes.keys():
		var dist = player_ref.global_position.distance_to(Vector3(pos.x, pos.y, pos.z))
		list.append({"pos": pos, "dist": dist})
	list.sort_custom(func(a, b): return a["dist"] < b["dist"])
	for i in range(list.size()):
		var entry = list[i]
		var pos = entry["pos"] as Vector3i
		var light = torch_light_nodes.get(pos) as OmniLight3D
		if not light or not is_instance_valid(light):
			continue
		light.shadow_enabled = i < MAX_SHADOW_TORCHES

func set_player_ref(p: Node3D):
	player_ref = p

func get_stats() -> Dictionary:
	return {
		"torches": torch_instances.size(),
		"lights": torch_light_nodes.size(),
		"max_shadow": MAX_SHADOW_TORCHES,
		"range": TORCH_OMNI_RANGE,
	}
