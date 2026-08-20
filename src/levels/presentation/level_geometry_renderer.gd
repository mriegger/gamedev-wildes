extends Node3D
class_name LevelGeometryRenderer

const TRANSITION_SECONDS: float = 0.35

var _room_meshes: Dictionary = {}
var _room_torch_cells: Dictionary = {}
var _seal_meshes: Dictionary = {}
var _seal_ids_by_room: Dictionary = {}
var _sealed_door_ids: Dictionary = {}
var _discovered_room_ids: Dictionary = {}
var _torch_renderer: TorchRenderer

func setup(
	layout: LevelLayout,
	state: LevelState,
	topology: LevelEncounterTopology,
	sealed_door_ids: Array[int],
	discovered_room_ids: Array[int],
	texture_set: BlockTextureSet,
	terrain_shader: Shader,
	torch_renderer: TorchRenderer,
) -> bool:
	if layout == null or state == null or topology == null or texture_set == null or terrain_shader == null or torch_renderer == null:
		return false
	if not _has_terrain_texture_uniform(terrain_shader):
		return false
	if not _room_meshes.is_empty() or not _seal_meshes.is_empty():
		return false
	var placements: Dictionary = {}
	for placement in layout.placed_modules:
		if placement == null or placements.has(placement.placement_id):
			return false
		placements[placement.placement_id] = placement
	if not placements.has(0):
		return false
	var discovered: Dictionary = {}
	for room_id in discovered_room_ids:
		if topology.get_room(room_id) == null or discovered.has(room_id):
			return false
		discovered[room_id] = true
	var doorways: Dictionary = {}
	for doorway in topology.get_doorways():
		if doorway == null or doorways.has(doorway.door_id):
			return false
		doorways[doorway.door_id] = doorway
	var sealed: Dictionary = {}
	for door_id in sealed_door_ids:
		if not doorways.has(door_id) or sealed.has(door_id):
			return false
		sealed[door_id] = true
	var placement_owners: Dictionary = {}
	var torch_cell_owners: Dictionary = {}
	var solid_cells_by_room: Dictionary = {}
	var torch_cells_by_room: Dictionary = {}
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		var room_cells: Array[Vector3i] = []
		var torch_cells: Array[Vector3i] = []
		for placement_id in room.discovery_placement_ids:
			if placement_id == 0 or placement_owners.has(placement_id) or not placements.has(placement_id):
				return false
			placement_owners[placement_id] = room_id
			_append_placement_cells(layout, placements[placement_id] as LevelPlacedModule, room_cells)
			if not _append_placement_torches(placements[placement_id] as LevelPlacedModule, torch_cells, room_id, torch_cell_owners):
				return false
		if room_cells.is_empty():
			return false
		solid_cells_by_room[room_id] = room_cells
		torch_cells_by_room[room_id] = torch_cells
	if placement_owners.size() != placements.size() - 1:
		return false
	var mesher := LevelMesher.new(texture_set)
	var base_cells: Array[Vector3i] = []
	var base_torch_cells: Array[Vector3i] = []
	_append_placement_cells(layout, placements[0] as LevelPlacedModule, base_cells)
	if not _append_placement_torches(placements[0] as LevelPlacedModule, base_torch_cells, -1, torch_cell_owners):
		return false
	if torch_cell_owners.size() != layout.torches.size():
		return false
	for torch in layout.torches:
		if not torch_cell_owners.has(torch.cell) or not torch_renderer.has_torch(torch.cell):
			return false
	if base_cells.is_empty():
		return false
	var base_mesh := mesher.create_mesh_for_cells(state, base_cells)
	if base_mesh == null:
		return false
	var room_meshes: Dictionary = {}
	for room_id in topology.get_room_ids():
		var mesh := mesher.create_mesh_for_cells(state, solid_cells_by_room[room_id] as Array[Vector3i])
		if mesh == null:
			return false
		room_meshes[room_id] = mesh
	var seal_meshes: Dictionary = {}
	var seal_ids_by_room: Dictionary = {}
	for room_id in topology.get_room_ids():
		seal_ids_by_room[room_id] = [] as Array[int]
	for doorway in topology.get_doorways():
		if not seal_ids_by_room.has(doorway.room_id):
			return false
		var mesh := mesher.create_doorway_seal_mesh(doorway)
		if mesh == null:
			return false
		seal_meshes[doorway.door_id] = mesh
		(seal_ids_by_room[doorway.room_id] as Array[int]).append(doorway.door_id)
	var terrain_material := _make_material(terrain_shader, texture_set)
	_torch_renderer = torch_renderer
	_room_torch_cells = torch_cells_by_room
	_seal_ids_by_room = seal_ids_by_room
	_sealed_door_ids = sealed
	add_child(_make_mesh_instance("EntryGeometry", base_mesh, terrain_material, true))
	for room_id in topology.get_room_ids():
		var room_discovered := discovered.has(room_id)
		var instance := _make_mesh_instance(
			"RoomBranch%d" % room_id,
			room_meshes[room_id] as ArrayMesh,
			terrain_material,
			room_discovered,
		)
		add_child(instance)
		_room_meshes[room_id] = instance
	for doorway in topology.get_doorways():
		var seal_visible := sealed.has(doorway.door_id) and discovered.has(doorway.room_id)
		var instance := _make_mesh_instance(
			"Seal%d" % doorway.door_id,
			seal_meshes[doorway.door_id] as ArrayMesh,
			terrain_material,
			seal_visible,
		)
		add_child(instance)
		_seal_meshes[doorway.door_id] = instance
	for room_id in topology.get_room_ids():
		if discovered.has(room_id):
			_discovered_room_ids[room_id] = true
	for room_id in topology.get_room_ids():
		_set_room_torch_strength(room_id, 1.0 if discovered.has(room_id) else 0.0)
	return true

func open_seals(seal_ids: Array[int]) -> void:
	var requested: Dictionary = {}
	for door_id in seal_ids:
		assert(_seal_meshes.has(door_id) and _sealed_door_ids.has(door_id) and not requested.has(door_id))
		requested[door_id] = true
	for door_id in seal_ids:
		_sealed_door_ids.erase(door_id)
		var instance := _seal_meshes[door_id] as MeshInstance3D
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not instance.visible:
			instance.transparency = 1.0
			continue
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(instance, "transparency", 1.0, TRANSITION_SECONDS)
		tween.tween_callback(_finish_open_seal.bind(instance))

func discover_rooms(room_ids: Array[int]) -> void:
	var requested: Dictionary = {}
	for room_id in room_ids:
		assert(_room_meshes.has(room_id) and not _discovered_room_ids.has(room_id) and not requested.has(room_id))
		requested[room_id] = true
	for room_id in room_ids:
		_discovered_room_ids[room_id] = true
		_prepare_room_discovery(room_id)
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_method(
			_set_room_discovery_strength.bind(room_id),
			0.0,
			1.0,
			TRANSITION_SECONDS,
		)
		tween.tween_callback(_finish_room_discovery.bind(room_id))

func _append_placement_cells(layout: LevelLayout, placement: LevelPlacedModule, target: Array[Vector3i]) -> void:
	for y in placement.definition.size.y:
		for z in placement.definition.size.z:
			for x in placement.definition.size.x:
				var cell := placement.world_cell(Vector3i(x, y, z))
				if StructureCell.is_structure_solid(layout.get_cell(cell)):
					target.append(cell)

func _append_placement_torches(
	placement: LevelPlacedModule,
	target: Array[Vector3i],
	owner_id: int,
	owners: Dictionary,
) -> bool:
	for torch in placement.definition.torches:
		var cell := placement.world_cell(torch.cell)
		if owners.has(cell):
			return false
		owners[cell] = owner_id
		target.append(cell)
	return true

func _make_mesh_instance(
	instance_name: String,
	mesh: ArrayMesh,
	material: ShaderMaterial,
	shown: bool,
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = mesh
	instance.material_override = material
	instance.visible = shown
	instance.transparency = 0.0 if shown else 1.0
	instance.cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if shown
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	return instance

func _make_material(shader: Shader, texture_set: BlockTextureSet) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("terrain_textures", texture_set.texture_array)
	return material

func _has_terrain_texture_uniform(shader: Shader) -> bool:
	for uniform in shader.get_shader_uniform_list():
		if StringName(uniform.get("name", &"")) == &"terrain_textures":
			return int(uniform.get("type", TYPE_NIL)) == TYPE_OBJECT \
				and String(uniform.get("hint_string", "")) == "TextureLayered"
	return false

func _prepare_room_discovery(room_id: int) -> void:
	var room_instance := _room_meshes[room_id] as MeshInstance3D
	room_instance.visible = true
	room_instance.transparency = 1.0
	room_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for door_id in _seal_ids_by_room[room_id] as Array[int]:
		var seal_instance := _seal_meshes[door_id] as MeshInstance3D
		var seal_visible := _sealed_door_ids.has(door_id)
		seal_instance.visible = seal_visible
		seal_instance.transparency = 1.0
		seal_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_room_torch_strength(room_id, 0.0)

func _set_room_discovery_strength(strength: float, room_id: int) -> void:
	var clamped_strength := clampf(strength, 0.0, 1.0)
	var room_instance := _room_meshes[room_id] as MeshInstance3D
	room_instance.transparency = 1.0 - clamped_strength
	for door_id in _seal_ids_by_room[room_id] as Array[int]:
		var seal_instance := _seal_meshes[door_id] as MeshInstance3D
		if _sealed_door_ids.has(door_id):
			seal_instance.transparency = 1.0 - clamped_strength
		else:
			seal_instance.visible = false
			seal_instance.transparency = 1.0
	_set_room_torch_strength(room_id, clamped_strength)

func _finish_room_discovery(room_id: int) -> void:
	var room_instance := _room_meshes[room_id] as MeshInstance3D
	room_instance.visible = true
	room_instance.transparency = 0.0
	room_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for door_id in _seal_ids_by_room[room_id] as Array[int]:
		var seal_instance := _seal_meshes[door_id] as MeshInstance3D
		if _sealed_door_ids.has(door_id):
			seal_instance.visible = true
			seal_instance.transparency = 0.0
			seal_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		else:
			seal_instance.visible = false
			seal_instance.transparency = 1.0
			seal_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_set_room_torch_strength(room_id, 1.0)

func _finish_open_seal(instance: MeshInstance3D) -> void:
	instance.visible = false
	instance.transparency = 1.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _set_room_torch_strength(room_id: int, strength: float) -> void:
	for cell in _room_torch_cells[room_id] as Array[Vector3i]:
		var strength_set := _torch_renderer.set_torch_reveal_strength(cell, strength)
		assert(strength_set)
