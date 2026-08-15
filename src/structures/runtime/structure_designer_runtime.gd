extends Node3D
class_name StructureDesignerRuntime

class ConnectionTarget:
	var cell: Vector3i
	var direction: LevelSocketDefinition.Direction
	var side_available: bool
	var valid: bool

@onready var _controller: StructureDesignerController = $StructureDesignerController as StructureDesignerController
@onready var _chunk_renderer: StructureChunkRenderer = $StructureChunkRenderer as StructureChunkRenderer
@onready var _torch_renderer: TorchRenderer = $TorchRenderer as TorchRenderer
@onready var _guide_view: StructureDesignerGuideView = $StructureDesignerGuideView as StructureDesignerGuideView
@onready var _metadata_overlay: StructureMetadataOverlay = $StructureMetadataOverlay as StructureMetadataOverlay
@onready var _designer_ui: StructureDesignerUI = $StructureDesignerUI as StructureDesignerUI
@onready var _world_environment: WorldEnvironment = $WorldEnvironment as WorldEnvironment

var _draft: StructureDraft
var _space: StructureDesignerSpace
var _toolbelt: CreativeToolbelt
var _current_hit: VoxelRaycastHit
var _connection_targeting: bool
var _external_ui_blocked: bool
var _active: bool

func _ready() -> void:
	visible = false
	_designer_ui.visible = false
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)

func setup(
	draft: StructureDraft,
	block_catalog: BlockCatalog,
	item_catalog: ItemCatalog,
	texture_set: BlockTextureSet,
	terrain_shader: Shader,
) -> void:
	assert(is_node_ready())
	assert(_draft == null)
	assert(draft != null and block_catalog != null and item_catalog != null and texture_set != null and terrain_shader != null)
	_draft = draft
	_space = StructureDesignerSpace.new(_draft, block_catalog)
	_toolbelt = CreativeToolbelt.new()
	assert(_toolbelt.setup(item_catalog))
	_controller.setup(_space)
	_controller.pitch.rotation_degrees.x = -25.0
	_chunk_renderer.setup(_draft, texture_set, terrain_shader)
	_torch_renderer.setup(block_catalog, 0, 0.0)
	_guide_view.setup(_draft.get_size())
	_metadata_overlay.setup(_draft)
	_designer_ui.setup(item_catalog, _toolbelt, _draft.get_format())
	_designer_ui.ui_blocking_changed.connect(_on_ui_blocking_changed)
	_designer_ui.weight_requested.connect(_on_weight_requested)
	_designer_ui.void_requested.connect(_on_void_requested)
	_designer_ui.connection_targeting_requested.connect(_on_connection_targeting_requested)
	_designer_ui.socket_remove_requested.connect(_on_socket_remove_requested)
	_designer_ui.marker_target_requested.connect(_on_marker_target_requested)
	_designer_ui.markers_commit_requested.connect(_on_markers_commit_requested)
	_designer_ui.markers_clear_requested.connect(_on_markers_clear_requested)
	_spawn_initial_torches()
	_sync_module_presentation()
	_setup_environment()

func activate() -> void:
	assert(_draft != null)
	_active = true
	visible = true
	_designer_ui.visible = true
	_controller.set_camera_active(true)
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	_sync_input_state()

func set_external_ui_blocked(blocked: bool) -> void:
	_external_ui_blocked = blocked
	_sync_input_state()

func cancel_active_ui() -> bool:
	if _stop_connection_targeting():
		return true
	return _designer_ui.close_active_overlay()

func _process(_delta: float) -> void:
	if not _active or _external_ui_blocked or _designer_ui.is_ui_blocking():
		_guide_view.clear_preview()
		return
	_current_hit = _controller.get_centered_raycast()
	if _current_hit == null:
		_guide_view.clear_preview()
		if _connection_targeting:
			_designer_ui.present_connection_target(null, false, true)
		return
	if _connection_targeting:
		_present_connection_target(_current_hit)
		return
	var action := _toolbelt.get_selected_placement_action()
	var block_id := action.block.id
	var cell := _current_hit.placement_cell
	_guide_view.show_preview(cell, _can_preview_placement(cell, block_id, _current_hit.face_normal))

func _input(event: InputEvent) -> void:
	if not _active or _external_ui_blocked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_TAB or key_event.physical_keycode == KEY_TAB:
			if _stop_connection_targeting():
				_designer_ui.open_palette()
			else:
				_designer_ui.toggle_palette()
			get_viewport().set_input_as_handled()
			return
		if _draft.get_format() == StructureDraft.Format.LEVEL_MODULE and (key_event.keycode == KEY_M or key_event.physical_keycode == KEY_M):
			if _stop_connection_targeting():
				_current_hit = _controller.get_centered_raycast()
				_designer_ui.open_module_panel()
			else:
				if not _designer_ui.is_module_panel_open():
					_current_hit = _controller.get_centered_raycast()
				_designer_ui.toggle_module_panel()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _active or _external_ui_blocked:
		return
	if _designer_ui.is_ui_blocking() or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if _connection_targeting:
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_try_add_targeted_connection()
		if mouse_event.button_index == MOUSE_BUTTON_LEFT or mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()
		return
	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		_try_remove_target()
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_try_place_selected()
		get_viewport().set_input_as_handled()

func _try_remove_target() -> void:
	_current_hit = _controller.get_centered_raycast()
	if _current_hit == null or not _draft.is_in_bounds(_current_hit.target_cell):
		return
	var change: StructureDraftChange
	if _space.get_block_id_at(_current_hit.target_cell) == BlockId.Type.TORCH:
		change = _draft.try_remove_torch(_current_hit.target_cell)
	else:
		change = _draft.try_remove_block(_current_hit.target_cell)
	_apply_change(change)

func _try_place_selected() -> void:
	_current_hit = _controller.get_centered_raycast()
	if _current_hit == null or _controller.body_intersects_cell(_current_hit.placement_cell):
		return
	var block_id := _toolbelt.get_selected_placement_action().block.id
	var change: StructureDraftChange
	if block_id == BlockId.Type.TORCH:
		change = _draft.try_place_torch(_current_hit.placement_cell, -_current_hit.face_normal)
	else:
		change = _draft.try_place_block(_current_hit.placement_cell, block_id)
	_apply_change(change)

func _apply_change(change: StructureDraftChange) -> void:
	if change == null or not change.succeeded:
		return
	if not change.changed_cells.is_empty():
		_chunk_renderer.rebuild_for_cells(change.changed_cells)
	for cell in change.removed_torch_cells:
		_torch_renderer.remove_torch(cell)
	for torch in change.added_torches:
		_torch_renderer.spawn_torch(torch.cell, torch.support_direction)
	if change.metadata_changed:
		_metadata_overlay.rebuild()
		_sync_module_presentation()

func _spawn_initial_torches() -> void:
	var attachments: Dictionary = {}
	for torch in _draft.get_torches():
		attachments[torch.cell] = torch.support_direction
	_torch_renderer.spawn_torches(attachments)

func _sync_module_presentation() -> void:
	if _draft.get_format() != StructureDraft.Format.LEVEL_MODULE:
		return
	_designer_ui.present_module_state(
		_draft.get_weight(),
		_draft.get_sockets(),
		_draft.get_spawn_marker(),
		_draft.get_return_door_marker(),
	)

func _can_preview_placement(cell: Vector3i, block_id: int, face_normal: Vector3i) -> bool:
	if _controller.body_intersects_cell(cell):
		return false
	if block_id == BlockId.Type.TORCH:
		return _draft.can_place_torch(cell, -face_normal)
	return _draft.can_place_block(cell, block_id)

func _present_connection_target(hit: VoxelRaycastHit) -> void:
	var target := _connection_target_for_hit(hit)
	if target == null:
		var cell := hit.target_cell
		if _draft.is_in_bounds(cell) and _draft.is_in_bounds(cell + Vector3i.UP):
			_guide_view.show_connection_preview(cell, false)
		else:
			_guide_view.clear_preview()
		_designer_ui.present_connection_target(null, false, true)
		return
	_guide_view.show_connection_preview(target.cell, target.valid)
	_designer_ui.present_connection_target(target.direction, target.valid, target.side_available)

func _connection_target_for_hit(hit: VoxelRaycastHit) -> ConnectionTarget:
	var candidate_cells: Array[Vector3i] = [hit.target_cell]
	if hit.face_normal == Vector3i.UP:
		candidate_cells.append(hit.target_cell + Vector3i.UP)
	var fallback: ConnectionTarget
	for cell in candidate_cells:
		var direction: Variant = _boundary_direction_for_hit(cell, hit.face_normal)
		if direction == null:
			continue
		var target := ConnectionTarget.new()
		target.cell = cell
		target.direction = direction as LevelSocketDefinition.Direction
		target.side_available = not _draft.has_socket_direction(target.direction)
		target.valid = target.side_available and _draft.can_add_socket(target.cell, target.direction)
		if target.valid:
			return target
		if fallback == null:
			fallback = target
	return fallback

func _boundary_direction_for_hit(cell: Vector3i, face_normal: Vector3i) -> Variant:
	var directions := _draft.get_boundary_directions(cell)
	if directions.is_empty():
		return null
	if directions.size() == 1:
		return directions[0]
	for direction_vector in [-face_normal, face_normal]:
		var direction: Variant = LevelSocketDefinition.direction_for_vector(direction_vector)
		if direction != null and directions.has(direction as LevelSocketDefinition.Direction):
			return direction
	return null

func _try_add_targeted_connection() -> void:
	_current_hit = _controller.get_centered_raycast()
	if _current_hit == null:
		return
	var target := _connection_target_for_hit(_current_hit)
	if target == null or not target.valid:
		return
	var change := _draft.try_add_socket(target.cell, target.direction)
	_apply_change(change)
	if not change.succeeded:
		return
	_guide_view.clear_preview()
	_designer_ui.present_connection_target(null, false, true)
	if _all_connection_sides_used():
		_stop_connection_targeting()
		_designer_ui.open_module_panel()

func _all_connection_sides_used() -> bool:
	for value in LevelSocketDefinition.Direction.values():
		if not _draft.has_socket_direction(value as LevelSocketDefinition.Direction):
			return false
	return true

func _on_ui_blocking_changed(blocking: bool) -> void:
	if blocking:
		_guide_view.clear_preview()
	_sync_input_state()

func _sync_input_state() -> void:
	if not is_node_ready():
		return
	var enabled := _active and not _external_ui_blocked and not _designer_ui.is_ui_blocking()
	_controller.set_mouse_capture_enabled(enabled)
	_controller.set_input_enabled(enabled)

func _on_weight_requested(weight: float) -> void:
	var change := _draft.try_set_weight(weight)
	_apply_change(change)
	if not change.succeeded:
		_sync_module_presentation()

func _on_void_requested() -> void:
	if _current_hit == null or not _draft.is_in_bounds(_current_hit.target_cell):
		return
	_apply_change(_draft.try_set_void(_current_hit.target_cell))

func _on_connection_targeting_requested() -> void:
	_connection_targeting = true
	_designer_ui.set_connection_targeting(true)
	_guide_view.clear_preview()

func _stop_connection_targeting() -> bool:
	if not _connection_targeting:
		return false
	_connection_targeting = false
	_designer_ui.set_connection_targeting(false)
	_guide_view.clear_preview()
	return true

func _on_socket_remove_requested(socket_id: StringName) -> void:
	_apply_change(_draft.try_remove_socket(socket_id))

func _on_marker_target_requested(role: StructureDesignerUI.MarkerRole, facing: LevelSocketDefinition.Direction) -> void:
	if _current_hit == null or not _draft.is_in_bounds(_current_hit.placement_cell):
		return
	_designer_ui.set_pending_marker(role, _current_hit.placement_cell, facing)

func _on_markers_commit_requested(
	spawn_cell: Vector3i,
	spawn_facing: LevelSocketDefinition.Direction,
	return_cell: Vector3i,
	return_facing: LevelSocketDefinition.Direction,
) -> void:
	var change := _draft.try_set_markers(spawn_cell, spawn_facing, return_cell, return_facing)
	_apply_change(change)
	if change.succeeded:
		_designer_ui.clear_pending_markers()

func _on_markers_clear_requested() -> void:
	_apply_change(_draft.try_clear_markers())

func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.8, 0.9)
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world_environment.environment = environment
