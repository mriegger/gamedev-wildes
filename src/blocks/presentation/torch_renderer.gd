extends Node3D
class_name TorchRenderer

const TORCH_SHADOW_UPDATE_INTERVAL: float = 0.6
const TORCH_LIGHT_Y: float = 0.32
const DEFAULT_SHADOW_OPACITY: float = 0.5

var torch_instances: Dictionary = {}
var torch_light_nodes: Dictionary = {}

var torch_base_material: StandardMaterial3D
var torch_flame_material: StandardMaterial3D
var torch_stem_mesh: BoxMesh
var torch_flame_mesh: BoxMesh

var _shadow_update_timer: float = 0.5
var _max_shadow_torches: int
var _shadow_transition_seconds: float
var _shadow_target_positions: Dictionary = {}
var _ordered_shadow_targets: Array[Vector3i] = []
var _shadow_strengths: Dictionary = {}
var _shadow_transition_active: bool = false
var player_ref: Node3D

var block_catalog: BlockCatalog

func setup(p_block_catalog: BlockCatalog, max_shadow_torches: int, shadow_transition_seconds: float):
	assert(p_block_catalog != null)
	assert(max_shadow_torches >= 0)
	assert(shadow_transition_seconds >= 0.0)
	block_catalog = p_block_catalog
	_max_shadow_torches = max_shadow_torches
	_shadow_transition_seconds = shadow_transition_seconds
	_shadow_target_positions.clear()
	_ordered_shadow_targets.clear()
	_shadow_strengths.clear()
	_shadow_transition_active = false
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
	var root := _create_torch(pos, attach_dir)
	_refresh_shadow_targets()
	_update_shadow_transitions(0.0)
	return root

func spawn_torches(torch_attachments: Dictionary) -> int:
	var spawned := 0
	for position in torch_attachments:
		_create_torch(position as Vector3i, torch_attachments[position] as Vector3i)
		spawned += 1
	if spawned > 0:
		_refresh_shadow_targets()
		_update_shadow_transitions(0.0)
	return spawned

func _create_torch(pos: Vector3i, attach_dir: Vector3i) -> Node3D:
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
	light.shadow_enabled = false
	light.shadow_reverse_cull_face = false
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 0.2
	light.shadow_opacity = 0.0
	light.shadow_blur = 1.0
	light.position = Vector3(0, TORCH_LIGHT_Y, 0)
	root.add_child(light)

	torch_instances[pos] = root
	torch_light_nodes[pos] = light
	_shadow_strengths[pos] = 0.0
	return root

func remove_torch(pos: Vector3i) -> bool:
	if torch_instances.has(pos):
		var n = torch_instances[pos] as Node3D
		if n and is_instance_valid(n):
			n.queue_free()
		torch_instances.erase(pos)
		torch_light_nodes.erase(pos)
		_shadow_target_positions.erase(pos)
		_ordered_shadow_targets.erase(pos)
		_shadow_strengths.erase(pos)
		return true
	torch_light_nodes.erase(pos)
	_shadow_target_positions.erase(pos)
	_ordered_shadow_targets.erase(pos)
	_shadow_strengths.erase(pos)
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
			_create_torch(torch_pos, dir)
			loaded += 1
	if loaded > 0:
		_refresh_shadow_targets()
		_update_shadow_transitions(0.0)
	return loaded

func update_shadow_culling(delta: float) -> void:
	if torch_instances.is_empty():
		return
	_shadow_update_timer -= delta
	if _shadow_update_timer <= 0.0:
		_shadow_update_timer = TORCH_SHADOW_UPDATE_INTERVAL
		_refresh_shadow_targets()
	_update_shadow_transitions(delta)

func _refresh_shadow_targets() -> void:
	var previous_targets := _shadow_target_positions
	_shadow_target_positions = {}
	_ordered_shadow_targets.clear()
	if _max_shadow_torches <= 0 or torch_light_nodes.is_empty():
		_finish_shadow_target_refresh(previous_targets)
		return
	if player_ref == null and not is_zero_approx(_shadow_transition_seconds):
		_finish_shadow_target_refresh(previous_targets)
		return
	var positions: Array[Vector3i] = []
	for position in torch_light_nodes:
		positions.append(position as Vector3i)
	if player_ref != null:
		var player_position := player_ref.global_position
		positions.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			if is_zero_approx(_shadow_transition_seconds):
				var immediate_a_distance := player_position.distance_squared_to(Vector3(a))
				var immediate_b_distance := player_position.distance_squared_to(Vector3(b))
				return immediate_a_distance < immediate_b_distance
			var a_light := torch_light_nodes.get(a) as OmniLight3D
			var b_light := torch_light_nodes.get(b) as OmniLight3D
			var a_distance := player_position.distance_squared_to(a_light.global_position)
			var b_distance := player_position.distance_squared_to(b_light.global_position)
			if not is_equal_approx(a_distance, b_distance):
				return a_distance < b_distance
			return _cell_less(a, b)
		)
	elif is_zero_approx(_shadow_transition_seconds) and positions.size() <= _max_shadow_torches:
		positions.sort_custom(_cell_less)
	else:
		_shadow_target_positions = previous_targets
		return
	var target_count := mini(_max_shadow_torches, positions.size())
	for index in target_count:
		var position := positions[index]
		_ordered_shadow_targets.append(position)
		_shadow_target_positions[position] = true
	_finish_shadow_target_refresh(previous_targets)

func _finish_shadow_target_refresh(previous_targets: Dictionary) -> void:
	if is_zero_approx(_shadow_transition_seconds):
		_apply_immediate_shadow_targets()
		_shadow_transition_active = false
		return
	if not _target_sets_match(previous_targets):
		_shadow_transition_active = true

func _target_sets_match(other_targets: Dictionary) -> bool:
	if _shadow_target_positions.size() != other_targets.size():
		return false
	for position in _shadow_target_positions:
		if not other_targets.has(position):
			return false
	return true

func _apply_immediate_shadow_targets() -> void:
	for position in torch_light_nodes:
		var light := torch_light_nodes.get(position) as OmniLight3D
		if light == null or not is_instance_valid(light):
			continue
		var enabled := _shadow_target_positions.has(position)
		light.shadow_enabled = enabled
		_shadow_strengths[position] = 1.0 if enabled else 0.0
		light.shadow_opacity = DEFAULT_SHADOW_OPACITY if enabled else 0.0

func _update_shadow_transitions(delta: float) -> void:
	if is_zero_approx(_shadow_transition_seconds) or not _shadow_transition_active:
		return
	var fade_step := clampf(delta / _shadow_transition_seconds, 0.0, 1.0)
	var transition_remains := false
	for position in torch_light_nodes:
		var light := torch_light_nodes.get(position) as OmniLight3D
		if light == null or not is_instance_valid(light) or not light.shadow_enabled:
			continue
		if _shadow_target_positions.has(position):
			continue
		var strength := maxf(float(_shadow_strengths.get(position, 0.0)) - fade_step, 0.0)
		_set_shadow_strength(position as Vector3i, light, strength)
		if is_zero_approx(strength):
			light.shadow_enabled = false
		else:
			transition_remains = true
	var active_count := 0
	for light_value in torch_light_nodes.values():
		var active_light := light_value as OmniLight3D
		if active_light != null and is_instance_valid(active_light) and active_light.shadow_enabled:
			active_count += 1
	for position in _ordered_shadow_targets:
		if active_count >= _max_shadow_torches:
			break
		var light := torch_light_nodes.get(position) as OmniLight3D
		if light == null or not is_instance_valid(light) or light.shadow_enabled:
			continue
		light.shadow_enabled = true
		_set_shadow_strength(position, light, 0.0)
		active_count += 1
	for position in _ordered_shadow_targets:
		var light := torch_light_nodes.get(position) as OmniLight3D
		if light == null or not is_instance_valid(light) or not light.shadow_enabled:
			continue
		var strength := minf(float(_shadow_strengths.get(position, 0.0)) + fade_step, 1.0)
		_set_shadow_strength(position, light, strength)
		if strength < 1.0:
			transition_remains = true
	_shadow_transition_active = transition_remains

func _set_shadow_strength(position: Vector3i, light: OmniLight3D, strength: float) -> void:
	_shadow_strengths[position] = strength
	light.shadow_opacity = DEFAULT_SHADOW_OPACITY * strength

func _cell_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z

func set_max_shadow_torches(count: int):
	assert(count >= 0)
	_max_shadow_torches = count
	_refresh_shadow_targets()
	_update_shadow_transitions(0.0)

func set_player_ref(p: Node3D):
	player_ref = p
	_refresh_shadow_targets()
	_update_shadow_transitions(0.0)
