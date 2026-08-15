extends Node3D
class_name LevelGeometryRenderer

const TRANSITION_SECONDS: float = 0.35

var _room_meshes: Dictionary = {}
var _room_materials: Dictionary = {}
var _room_torch_cells: Dictionary = {}
var _barrier_meshes: Dictionary = {}
var _barrier_materials: Dictionary = {}
var _barrier_room_ids: Dictionary = {}
var _revealed_room_ids: Dictionary = {}
var _barrier_tweens: Dictionary = {}
var _reveal_tweens: Dictionary = {}
var _torch_renderer: TorchRenderer

func setup(
	layout: LevelLayout,
	state: LevelState,
	topology: LevelEncounterTopology,
	door_locks: Dictionary,
	revealed_room_ids: Array[int],
	texture_set: BlockTextureSet,
	terrain_shader: Shader,
	torch_renderer: TorchRenderer,
) -> bool:
	if layout == null or state == null or topology == null or texture_set == null or terrain_shader == null or torch_renderer == null:
		return false
	if not _has_reveal_uniform(terrain_shader):
		return false
	if not _room_meshes.is_empty() or not _barrier_meshes.is_empty():
		return false
	var placements: Dictionary = {}
	for placement in layout.placed_modules:
		if placement == null or placements.has(placement.placement_id):
			return false
		placements[placement.placement_id] = placement
	if not placements.has(0):
		return false
	var revealed: Dictionary = {}
	for room_id in revealed_room_ids:
		if topology.get_room(room_id) == null or revealed.has(room_id):
			return false
		revealed[room_id] = true
	var placement_owners: Dictionary = {}
	var torch_cell_owners: Dictionary = {}
	var solid_cells_by_room: Dictionary = {}
	var torch_cells_by_room: Dictionary = {}
	for room_id in topology.get_room_ids():
		var room := topology.get_room(room_id)
		var room_cells: Array[Vector3i] = []
		var torch_cells: Array[Vector3i] = []
		for placement_id in room.reveal_placement_ids:
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
	var room_materials: Dictionary = {}
	for room_id in topology.get_room_ids():
		var reveal_amount := 1.0 if revealed.has(room_id) else 0.0
		var material := _make_material(terrain_shader, texture_set, reveal_amount)
		var mesh := mesher.create_mesh_for_cells(state, solid_cells_by_room[room_id] as Array[Vector3i])
		if mesh == null:
			return false
		room_meshes[room_id] = mesh
		room_materials[room_id] = material
	var barrier_meshes: Dictionary = {}
	var barrier_materials: Dictionary = {}
	var barrier_room_ids: Dictionary = {}
	for doorway in topology.get_doorways():
		if doorway == null or not door_locks.has(doorway.door_id) or not door_locks[doorway.door_id] is bool or barrier_meshes.has(doorway.door_id):
			return false
		var mesh := mesher.create_uniform_block_mesh(state, doorway.aperture_cells, doorway.fill_block_id)
		if mesh == null:
			return false
		var material := _make_material(
			terrain_shader,
			texture_set,
			1.0 if revealed.has(doorway.room_id) else 0.0,
		)
		barrier_meshes[doorway.door_id] = mesh
		barrier_materials[doorway.door_id] = material
		barrier_room_ids[doorway.door_id] = doorway.room_id
	if barrier_meshes.size() != door_locks.size():
		return false
	_torch_renderer = torch_renderer
	_room_materials = room_materials
	_room_torch_cells = torch_cells_by_room
	_barrier_materials = barrier_materials
	_barrier_room_ids = barrier_room_ids
	add_child(_make_mesh_instance("EntryGeometry", base_mesh, _make_material(terrain_shader, texture_set, 1.0)))
	for room_id in topology.get_room_ids():
		var instance := _make_mesh_instance("RoomBranch%d" % room_id, room_meshes[room_id] as ArrayMesh, room_materials[room_id] as ShaderMaterial)
		add_child(instance)
		_room_meshes[room_id] = instance
	for doorway in topology.get_doorways():
		var instance := _make_mesh_instance("Barrier%d" % doorway.door_id, barrier_meshes[doorway.door_id] as ArrayMesh, barrier_materials[doorway.door_id] as ShaderMaterial)
		instance.transparency = 0.0 if bool(door_locks[doorway.door_id]) else 1.0
		instance.visible = bool(door_locks[doorway.door_id])
		add_child(instance)
		_barrier_meshes[doorway.door_id] = instance
	for room_id in topology.get_room_ids():
		var reveal_amount := 1.0 if revealed.has(room_id) else 0.0
		_set_room_reveal(room_id, reveal_amount)
		if revealed.has(room_id):
			_revealed_room_ids[room_id] = true
	return true

func apply_door_locks(changes: Dictionary) -> void:
	for door_id in changes:
		assert(_barrier_meshes.has(door_id) and changes[door_id] is bool)
		var instance := _barrier_meshes[door_id] as MeshInstance3D
		var previous := _barrier_tweens.get(door_id) as Tween
		if previous != null and previous.is_valid():
			previous.kill()
		if bool(changes[door_id]):
			instance.visible = true
			instance.transparency = 0.0
			continue
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(instance, "transparency", 1.0, TRANSITION_SECONDS)
		tween.tween_callback(func() -> void: instance.visible = false)
		_barrier_tweens[door_id] = tween

func reveal_rooms(room_ids: Array[int]) -> void:
	for room_id in room_ids:
		if _revealed_room_ids.has(room_id):
			continue
		assert(_room_materials.has(room_id))
		_revealed_room_ids[room_id] = true
		var previous := _reveal_tweens.get(room_id) as Tween
		if previous != null and previous.is_valid():
			previous.kill()
		var material := _room_materials[room_id] as ShaderMaterial
		var start_amount := float(material.get_shader_parameter("reveal_amount"))
		var target_room_id := room_id
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_method(
			func(amount: float) -> void: _set_room_reveal(target_room_id, amount),
			start_amount,
			1.0,
			TRANSITION_SECONDS,
		)
		_reveal_tweens[room_id] = tween

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

func _make_mesh_instance(instance_name: String, mesh: ArrayMesh, material: ShaderMaterial) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = instance_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return instance

func _make_material(shader: Shader, texture_set: BlockTextureSet, reveal_amount: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("terrain_textures", texture_set.texture_array)
	material.set_shader_parameter("reveal_amount", reveal_amount)
	return material

func _has_reveal_uniform(shader: Shader) -> bool:
	for uniform in shader.get_shader_uniform_list():
		if StringName(uniform.get("name", &"")) == &"reveal_amount":
			return int(uniform.get("type", TYPE_NIL)) == TYPE_FLOAT
	return false

func _set_room_reveal(room_id: int, amount: float) -> void:
	var strength := clampf(amount, 0.0, 1.0)
	(_room_materials[room_id] as ShaderMaterial).set_shader_parameter("reveal_amount", strength)
	for door_id in _barrier_room_ids:
		if int(_barrier_room_ids[door_id]) == room_id:
			(_barrier_materials[door_id] as ShaderMaterial).set_shader_parameter("reveal_amount", strength)
	for cell in _room_torch_cells[room_id] as Array[Vector3i]:
		assert(_torch_renderer.set_torch_reveal_strength(cell, strength))
