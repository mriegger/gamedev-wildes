extends Node3D
class_name TargetingView

@export var blob_shadow_shader: Shader

var voxel_space: VoxelSpace = null
var motor: PlayerMotor = null
var interactor: PlayerInteractor = null
var block_catalog: BlockCatalog = null
var _is_setup: bool = false

var selection_box: Node3D
var ghost_block: MeshInstance3D
var breaking_block: MeshInstance3D
var contact_shadow: MeshInstance3D

var _selection_edge_mat: StandardMaterial3D = null
var _contact_shadow_color: Color = Color(-1, -1, -1, -1)

func setup(p_motor: PlayerMotor, p_interactor: PlayerInteractor):
	assert(p_motor != null)
	assert(p_interactor != null)
	if _is_setup:
		assert(motor == p_motor)
		assert(interactor == p_interactor)
		return
	motor = p_motor
	interactor = p_interactor
	_ensure_visuals()
	if contact_shadow.get_parent() != motor:
		contact_shadow.reparent(motor, false)
	_is_setup = true

func bind_space(p_space: VoxelSpace, presentation_root: Node):
	assert(_is_setup)
	assert(p_space != null)
	assert(presentation_root != null)
	voxel_space = p_space
	block_catalog = p_space.block_catalog
	_hide_targeting_visuals()
	contact_shadow.visible = false
	for visual in [selection_box, ghost_block, breaking_block]:
		if visual.get_parent() != presentation_root:
			visual.reparent(presentation_root, false)

func unbind_space():
	_hide_targeting_visuals()
	contact_shadow.visible = false
	for visual in [selection_box, ghost_block, breaking_block]:
		if visual.get_parent() != self:
			visual.reparent(self, false)
	voxel_space = null
	block_catalog = null

func _hide_targeting_visuals():
	if selection_box != null:
		selection_box.visible = false
	if ghost_block != null:
		ghost_block.visible = false
	if breaking_block != null:
		breaking_block.visible = false

func _ensure_visuals():
	if selection_box == null:
		_create_selection()
	if ghost_block == null:
		_create_ghost()
	if contact_shadow == null:
		_create_contact_shadow()

func _ready():
	_ensure_visuals()

func _physics_process(_delta):
	_update_selection_visuals()
	_update_contact_shadow()

func _create_selection():
	var edge_thickness = 0.045
	var hs = 0.5125
	selection_box = Node3D.new()
	selection_box.name = "SelectionBox"
	_selection_edge_mat = StandardMaterial3D.new()
	_selection_edge_mat.albedo_color = Color(1.0, 0.92, 0.08, 1.0)
	_selection_edge_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_selection_edge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_selection_edge_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var edges_def = [
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, hs, hs)},
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, hs, -hs)},
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, -hs, hs)},
		{"size": Vector3(1.025, edge_thickness, edge_thickness), "pos": Vector3(0, -hs, -hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(hs, 0, hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(hs, 0, -hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(-hs, 0, hs)},
		{"size": Vector3(edge_thickness, 1.025, edge_thickness), "pos": Vector3(-hs, 0, -hs)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(hs, hs, 0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(hs, -hs, 0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(-hs, hs, 0)},
		{"size": Vector3(edge_thickness, edge_thickness, 1.025), "pos": Vector3(-hs, -hs, 0)},
	]
	for ed in edges_def:
		var mi = MeshInstance3D.new()
		var bm = BoxMesh.new()
		bm.size = ed["size"]
		mi.mesh = bm
		mi.position = ed["pos"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.material_override = _selection_edge_mat
		selection_box.add_child(mi)
	selection_box.visible = false
	add_child(selection_box)

	breaking_block = MeshInstance3D.new()
	breaking_block.name = "BreakingBlock"
	var bb_mesh = BoxMesh.new()
	bb_mesh.size = Vector3(1.01, 1.01, 1.01)
	breaking_block.mesh = bb_mesh
	breaking_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bb_mat = StandardMaterial3D.new()
	bb_mat.albedo_color = Color.WHITE
	bb_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	breaking_block.material_override = bb_mat
	breaking_block.visible = false
	add_child(breaking_block)

func _create_ghost():
	ghost_block = MeshInstance3D.new()
	ghost_block.name = "GhostBlock"
	var b = BoxMesh.new()
	b.size = Vector3(1.0, 1.0, 1.0)
	ghost_block.mesh = b
	ghost_block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 1.0, 0.48)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ghost_block.material_override = mat
	ghost_block.visible = false
	add_child(ghost_block)

func _create_contact_shadow():
	contact_shadow = MeshInstance3D.new()
	contact_shadow.name = "ContactShadow"
	var plane = PlaneMesh.new()
	plane.size = Vector2(1.4, 1.4)
	contact_shadow.mesh = plane
	contact_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow_material = ShaderMaterial.new()
	shadow_material.shader = blob_shadow_shader
	shadow_material.set_shader_parameter("shadow_color", Color(0.06, 0.06, 0.06, 0.55))
	contact_shadow.material_override = shadow_material
	contact_shadow.visible = false
	add_child(contact_shadow)

func _texture_for_block(block_id: int) -> Texture2D:
	return block_catalog.get_definition(block_id).side_texture

func _update_selection_visuals():
	if interactor == null or voxel_space == null:
		return
	if interactor.pointer_over_ui:
		if selection_box:
			selection_box.visible = false
		if ghost_block:
			ghost_block.visible = false
		if breaking_block:
			breaking_block.visible = false
		return
	var selected_block_id = interactor.get_selected_block_id()
	var has_block = selected_block_id != null
	var primary_holding = Input.is_action_pressed("primary_use")
	var has_mining_action = interactor.is_editing_enabled() and interactor.get_selected_primary_action() is MiningActionDefinition

	var show_mining_outline = false
	var show_ghost = false

	if has_block:
		if primary_holding or interactor.is_mining:
			show_mining_outline = has_mining_action and interactor.target_has
		else:
			show_ghost = interactor.placement_has
	else:
		show_mining_outline = has_mining_action and interactor.target_has

	if show_mining_outline and interactor.target_has:
		if selection_box == null or not selection_box.is_inside_tree():
			return
		selection_box.visible = true
		var center = Vector3(float(interactor.target_block.x) + 0.5, float(interactor.target_block.y) + 0.5, float(interactor.target_block.z) + 0.5)
		selection_box.global_position = center
		if breaking_block and breaking_block.is_inside_tree():
			breaking_block.global_position = center

		var pulse = 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 1.8 * TAU)
		var col: Color
		if interactor.can_mine_target:
			col = Color(1.0, 0.92, 0.08, 0.95 * pulse)
		else:
			col = Color(1.0, 0.32, 0.22, 0.55 * pulse)
		_selection_edge_mat.albedo_color = col

		if interactor.is_mining and interactor.can_mine_target:
			if breaking_block:
				breaking_block.visible = true
				var bt = voxel_space.get_block_at(interactor.target_block)
				if bt != null:
					var texture := _texture_for_block(bt)
					var bmat = breaking_block.material_override
					if bmat is StandardMaterial3D and bmat.albedo_texture != texture:
						bmat.albedo_texture = texture
				var progress = clamp(interactor.mine_timer / interactor.get_mine_duration(), 0.0, 1.0)
				var s = 1.0 + 0.12 * sin(progress * PI)
				var mining_scale = Vector3(s, s, s)
				if breaking_block.scale != mining_scale:
					breaking_block.scale = mining_scale
				if selection_box.scale != mining_scale:
					selection_box.scale = mining_scale
		else:
			if breaking_block:
				breaking_block.visible = false
				if breaking_block.scale != Vector3.ONE:
					breaking_block.scale = Vector3.ONE
			if selection_box.scale != Vector3.ONE:
				selection_box.scale = Vector3.ONE
	else:
		if selection_box and selection_box.is_inside_tree():
			selection_box.visible = false
			if selection_box.scale != Vector3.ONE:
				selection_box.scale = Vector3.ONE
		if breaking_block and breaking_block.is_inside_tree():
			breaking_block.visible = false
			if breaking_block.scale != Vector3.ONE:
				breaking_block.scale = Vector3.ONE

	if show_ghost and ghost_block and interactor.placement_has:
		if not ghost_block.is_inside_tree():
			return
		var block_id = selected_block_id
		if block_id == null or block_id == BlockId.Type.AIR:
			ghost_block.visible = false
		else:
			ghost_block.visible = true
			var base_center: Vector3
			var ghost_size: Vector3
			if block_id == BlockId.Type.TORCH:
				var support_dir = -interactor.last_ray_normal
				base_center = TorchPlacement.world_position(interactor.placement_block, support_dir)
				ghost_size = Vector3(0.12, 0.55, 0.12)
			else:
				base_center = Vector3(float(interactor.placement_block.x) + 0.5, float(interactor.placement_block.y) + 0.5, float(interactor.placement_block.z) + 0.5)
				ghost_size = Vector3.ONE
			var ghost_mesh = ghost_block.mesh as BoxMesh
			if ghost_mesh.size != ghost_size:
				ghost_mesh.size = ghost_size
			ghost_block.global_position = base_center
			var gmat = ghost_block.material_override
			if gmat is StandardMaterial3D:
				var texture := _texture_for_block(block_id)
				if gmat.albedo_texture != texture:
					gmat.albedo_texture = texture
				var ghost_color: Color
				if interactor.can_place_target:
					ghost_color = Color(1.0, 1.0, 1.0, 0.48)
				else:
					ghost_color = Color(1.0, 1.0, 1.0, 0.18)
				if gmat.albedo_color != ghost_color:
					gmat.albedo_color = ghost_color
	else:
		if ghost_block and ghost_block.is_inside_tree():
			ghost_block.visible = false

func _update_contact_shadow():
	if contact_shadow == null or motor == null:
		return
	if not motor.is_inside_tree() or not contact_shadow.is_inside_tree():
		return
	var g = motor.ground_y
	if g == VoxelSpace.NO_SURFACE_Y:
		if contact_shadow.visible:
			contact_shadow.visible = false
		return
	if not contact_shadow.visible:
		contact_shadow.visible = true
	var shadow_position = Vector3(motor.global_position.x, g + 0.02, motor.global_position.z)
	if contact_shadow.global_position != shadow_position:
		contact_shadow.global_position = shadow_position
	var dist = motor.global_position.y - g
	var alpha = clamp(1.0 - dist * 0.8, 0.0, 0.55)
	var plane_mesh = contact_shadow.mesh as PlaneMesh
	if plane_mesh:
		var size_factor = clamp(1.4 - dist * 0.18, 0.5, 1.4)
		var shadow_size = Vector2(size_factor, size_factor)
		if plane_mesh.size != shadow_size:
			plane_mesh.size = shadow_size
	var mat = contact_shadow.material_override as ShaderMaterial
	var shadow_color = Color(0.06, 0.06, 0.06, alpha)
	if shadow_color != _contact_shadow_color:
		_contact_shadow_color = shadow_color
		mat.set_shader_parameter("shadow_color", shadow_color)
