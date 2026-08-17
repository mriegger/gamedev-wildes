extends Node3D
class_name StructureDesignerRuntime

@onready var _controller: StructureDesignerController = $StructureDesignerController as StructureDesignerController
@onready var _chunk_renderer: StructureChunkRenderer = $StructureChunkRenderer as StructureChunkRenderer
@onready var _torch_renderer: TorchRenderer = $TorchRenderer as TorchRenderer
@onready var _guide_view: StructureDesignerGuideView = $StructureDesignerGuideView as StructureDesignerGuideView
@onready var _designer_ui: StructureDesignerUI = $StructureDesignerUI as StructureDesignerUI
@onready var _world_environment: WorldEnvironment = $WorldEnvironment as WorldEnvironment

var _draft: StructureDraft
var _space: StructureDesignerSpace
var _toolbelt: CreativeToolbelt
var _current_hit: VoxelRaycastHit
var _external_ui_blocked: bool
var _active: bool

func _ready() -> void:
	visible = false
	_designer_ui.visible = false
	set_process(false)
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
	_designer_ui.setup(item_catalog, _toolbelt)
	_designer_ui.ui_blocking_changed.connect(_on_ui_blocking_changed)
	_spawn_initial_torches()
	_setup_environment()

func activate() -> void:
	assert(_draft != null)
	_active = true
	visible = true
	_designer_ui.visible = true
	_controller.set_camera_active(true)
	set_process(true)
	set_process_unhandled_input(true)
	_sync_input_state()

func set_external_ui_blocked(blocked: bool) -> void:
	_external_ui_blocked = blocked
	_sync_input_state()

func cancel_active_ui() -> bool:
	if not _designer_ui.is_palette_open():
		return false
	_designer_ui.close_palette()
	return true

func _process(_delta: float) -> void:
	if not _active or _external_ui_blocked or _designer_ui.is_ui_blocking():
		_guide_view.clear_preview()
		return
	_current_hit = _controller.get_centered_raycast()
	if _current_hit == null:
		_guide_view.clear_preview()
		return
	var action := _toolbelt.get_selected_placement_action()
	var block_id := action.block.id
	var cell := _current_hit.placement_cell
	_guide_view.show_preview(cell, _can_preview_placement(cell, block_id, _current_hit.face_normal))

func _unhandled_input(event: InputEvent) -> void:
	if not _active or _external_ui_blocked:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_TAB or key_event.physical_keycode == KEY_TAB:
			_designer_ui.toggle_palette()
			get_viewport().set_input_as_handled()
			return
	if _designer_ui.is_ui_blocking() or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
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

func _spawn_initial_torches() -> void:
	var attachments: Dictionary = {}
	for torch in _draft.get_torches():
		attachments[torch.cell] = torch.support_direction
	_torch_renderer.spawn_torches(attachments)

func _can_preview_placement(cell: Vector3i, block_id: int, face_normal: Vector3i) -> bool:
	if _controller.body_intersects_cell(cell):
		return false
	if block_id == BlockId.Type.TORCH:
		return _draft.can_place_torch(cell, -face_normal)
	return _draft.can_place_block(cell, block_id)

func _on_ui_blocking_changed(_blocking: bool) -> void:
	if _designer_ui.is_ui_blocking():
		_guide_view.clear_preview()
	_sync_input_state()

func _sync_input_state() -> void:
	if not is_node_ready():
		return
	var enabled := _active and not _external_ui_blocked and not _designer_ui.is_ui_blocking()
	_controller.set_mouse_capture_enabled(enabled)
	_controller.set_input_enabled(enabled)

func _setup_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.8, 0.9)
	environment.ambient_light_energy = 0.72
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_world_environment.environment = environment
