extends Node3D
class_name CampfireRenderer

const SHADOW_UPDATE_INTERVAL: float = 0.6
const MAX_SHADOW_CAMPFIRES: int = 1

var campfire_instances: Dictionary[Vector3i, Node3D] = {}
var campfire_lights: Dictionary[Vector3i, OmniLight3D] = {}
var block_catalog: BlockCatalog
var audio_profile: CampfireAudioProfile
var player_ref: Node3D
var _stone_material: StandardMaterial3D
var _wood_material: StandardMaterial3D
var _ember_material: StandardMaterial3D
var _placement_preview: Node3D
var _shadow_update_timer: float = 0.0

func setup(p_block_catalog: BlockCatalog, p_audio_profile: CampfireAudioProfile) -> void:
	assert(p_block_catalog != null)
	assert(p_audio_profile != null and p_audio_profile.validate())
	block_catalog = p_block_catalog
	audio_profile = p_audio_profile
	_stone_material = _make_material(Color(0.34, 0.32, 0.29, 1.0), 0.96)
	_wood_material = _make_material(Color(0.30, 0.16, 0.065, 1.0), 0.94)
	_ember_material = _make_ember_material()

func spawn_campfire(anchor: Vector3i) -> Node3D:
	remove_campfire(anchor)
	var root := _create_campfire_visual("Campfire_%d_%d_%d" % [anchor.x, anchor.y, anchor.z], true)
	root.position = Vector3(anchor)
	add_child(root)
	campfire_instances[anchor] = root
	campfire_lights[anchor] = root.get_node(^"FireLight") as OmniLight3D
	_refresh_shadow_target()
	return root

func remove_campfire(anchor: Vector3i) -> bool:
	if not campfire_instances.has(anchor):
		return false
	var root := campfire_instances[anchor] as Node3D
	if root != null and is_instance_valid(root):
		root.queue_free()
	campfire_instances.erase(anchor)
	campfire_lights.erase(anchor)
	_refresh_shadow_target()
	return true

func clear() -> void:
	var anchors: Array[Vector3i] = []
	for anchor in campfire_instances:
		anchors.append(anchor as Vector3i)
	for anchor in anchors:
		remove_campfire(anchor)

func load_campfires_for_chunk(cx: int, cz: int, voxel_world: VoxelWorld) -> int:
	var loaded := 0
	for anchor in voxel_world.get_emplacements_for_chunk(cx, cz):
		if voxel_world.get_block_id_at(anchor) != BlockId.Type.CAMPFIRE or campfire_instances.has(anchor):
			continue
		spawn_campfire(anchor)
		loaded += 1
	return loaded

func unload_campfires_in_chunk(cx: int, cz: int, chunk_size: int) -> int:
	var anchors: Array[Vector3i] = []
	for anchor in campfire_instances:
		if floori(float(anchor.x) / chunk_size) == cx and floori(float(anchor.z) / chunk_size) == cz:
			anchors.append(anchor as Vector3i)
	for anchor in anchors:
		remove_campfire(anchor)
	return anchors.size()

func set_placement_preview(anchor: Variant, can_place: bool) -> void:
	if anchor == null:
		if _placement_preview != null:
			_placement_preview.visible = false
		return
	if not anchor is Vector3i:
		return
	if _placement_preview == null:
		_placement_preview = _create_campfire_visual("CampfirePlacementPreview", false)
		_set_preview_materials(_placement_preview)
		add_child(_placement_preview)
	_placement_preview.global_position = Vector3(anchor)
	_placement_preview.visible = true
	_set_preview_opacity(0.48 if can_place else 0.18)

func set_player_ref(player: Node3D) -> void:
	player_ref = player
	_refresh_shadow_target()

func update_shadow_culling(delta: float) -> void:
	_shadow_update_timer -= delta
	if _shadow_update_timer <= 0.0:
		_shadow_update_timer = SHADOW_UPDATE_INTERVAL
		_refresh_shadow_target()

func _refresh_shadow_target() -> void:
	var nearest_anchor: Variant = null
	var nearest_distance := INF
	for anchor in campfire_lights:
		var light := campfire_lights[anchor] as OmniLight3D
		if light == null or not is_instance_valid(light):
			continue
		var distance := 0.0 if player_ref == null else player_ref.global_position.distance_squared_to(light.global_position)
		if nearest_anchor == null or distance < nearest_distance or (is_equal_approx(distance, nearest_distance) and _cell_less(anchor, nearest_anchor)):
			nearest_anchor = anchor
			nearest_distance = distance
	for anchor in campfire_lights:
		var light := campfire_lights[anchor] as OmniLight3D
		if light != null and is_instance_valid(light):
			light.shadow_enabled = MAX_SHADOW_CAMPFIRES > 0 and anchor == nearest_anchor

func _create_campfire_visual(name_value: String, include_effects: bool) -> Node3D:
	var root := Node3D.new()
	root.name = name_value
	var center := Vector3(0.5, 0.0, 0.5)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		var stone_position := center + Vector3(cos(angle) * 1.05, 0.14, sin(angle) * 1.05)
		_add_stone(root, "Stone%02d" % index, stone_position, angle)
	_add_log(root, "LogA", center + Vector3.UP * 0.22, PI * 0.25)
	_add_log(root, "LogB", center + Vector3.UP * 0.24, -PI * 0.25)
	_add_log(root, "LogC", center + Vector3.UP * 0.30, PI * 0.5)
	_add_ember(root, center + Vector3.UP * 0.23)
	if include_effects:
		var effect := FireEffectPresentation.new()
		effect.name = "FireEffect"
		effect.position = center + Vector3.UP * 0.30
		effect.setup(1.65)
		root.add_child(effect)
		_add_light(root, center)
		_add_audio(root, center)
	return root

func _add_stone(root: Node3D, name_value: String, position_value: Vector3, angle: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.23
	mesh.height = 0.27
	mesh.radial_segments = 6
	mesh.rings = 3
	var stone := MeshInstance3D.new()
	stone.name = name_value
	stone.mesh = mesh
	stone.position = position_value
	stone.rotation.y = angle
	stone.scale = Vector3(1.25, 0.82, 0.9)
	stone.material_override = _stone_material
	root.add_child(stone)

func _add_log(root: Node3D, name_value: String, position_value: Vector3, angle: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 0.12
	mesh.top_radius = 0.12
	mesh.height = 1.45
	mesh.radial_segments = 8
	mesh.rings = 1
	var log := MeshInstance3D.new()
	log.name = name_value
	log.mesh = mesh
	log.position = position_value
	log.rotation = Vector3(0.0, angle, PI * 0.5)
	log.material_override = _wood_material
	root.add_child(log)

func _add_ember(root: Node3D, position_value: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = 0.48
	mesh.top_radius = 0.38
	mesh.height = 0.08
	mesh.radial_segments = 10
	var ember := MeshInstance3D.new()
	ember.name = "Embers"
	ember.mesh = mesh
	ember.position = position_value
	ember.material_override = _ember_material
	root.add_child(ember)

func _add_light(root: Node3D, center: Vector3) -> void:
	var definition := block_catalog.get_definition(BlockId.Type.CAMPFIRE)
	var light := OmniLight3D.new()
	light.name = "FireLight"
	light.position = center + Vector3.UP * 0.62
	light.light_color = definition.light_color
	light.light_energy = definition.emissive_energy
	light.omni_range = definition.light_range
	light.omni_attenuation = 0.82
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	light.shadow_enabled = false
	light.shadow_bias = 0.035
	light.shadow_normal_bias = 0.22
	light.shadow_opacity = 0.52
	light.shadow_blur = 1.2
	root.add_child(light)

func _add_audio(root: Node3D, center: Vector3) -> void:
	var player := AudioStreamPlayer3D.new()
	player.name = "FireAudio"
	player.position = center + Vector3.UP * 0.3
	player.stream = audio_profile.loop_stream.duplicate()
	if player.stream is AudioStreamOggVorbis:
		(player.stream as AudioStreamOggVorbis).loop = true
	player.volume_db = audio_profile.volume_db
	player.unit_size = audio_profile.unit_size
	player.max_distance = audio_profile.max_distance
	player.bus = &"Ambient"
	player.autoplay = true
	root.add_child(player)

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material

func _make_ember_material() -> StandardMaterial3D:
	var material := _make_material(Color(0.44, 0.055, 0.012, 1.0), 0.72)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.12, 0.01, 1.0)
	material.emission_energy_multiplier = 1.5
	return material

func _get_meshes(root: Node) -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D:
			meshes.append(child as MeshInstance3D)
		meshes.append_array(_get_meshes(child))
	return meshes

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

func _cell_less(left: Vector3i, right: Vector3i) -> bool:
	if left.x != right.x:
		return left.x < right.x
	if left.y != right.y:
		return left.y < right.y
	return left.z < right.z
