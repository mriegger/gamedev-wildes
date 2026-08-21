extends Node
class_name CopperMiningTutorialCoordinator

const DISMISS_DISTANCE: float = 14.0

var _voxel_world: VoxelWorld
var _player: Node3D
var _is_overworld_active: Callable
var _interactor: PlayerInteractor
var _view: CopperMiningTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _pending_target: Variant = null
var _active_target: Variant = null

func _ready() -> void:
	set_process(false)

func setup(
	voxel_world: VoxelWorld,
	player: Node3D,
	is_overworld_active: Callable,
	camera: Camera3D,
	interactor: PlayerInteractor,
	view: CopperMiningTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
) -> void:
	assert(voxel_world != null)
	assert(player != null)
	assert(is_overworld_active.is_valid())
	assert(camera != null)
	assert(interactor != null)
	assert(view != null)
	assert(progress != null)
	assert(callout_arbiter != null)
	assert(_voxel_world == null)
	_voxel_world = voxel_world
	_player = player
	_is_overworld_active = is_overworld_active
	_interactor = interactor
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_view.setup(camera)
	_interactor.mining_tool_requirement_failed.connect(_on_mining_tool_requirement_failed)
	_interactor.block_mined.connect(_on_block_mined)
	_view.callout_hidden.connect(_on_view_hidden)

func _exit_tree() -> void:
	if _interactor != null:
		if _interactor.mining_tool_requirement_failed.is_connected(_on_mining_tool_requirement_failed):
			_interactor.mining_tool_requirement_failed.disconnect(_on_mining_tool_requirement_failed)
		if _interactor.block_mined.is_connected(_on_block_mined):
			_interactor.block_mined.disconnect(_on_block_mined)
	if _view != null and _view.callout_hidden.is_connected(_on_view_hidden):
		_view.callout_hidden.disconnect(_on_view_hidden)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)
		_callout_arbiter.cancel_priority(self)

func _process(_delta: float) -> void:
	if _active_target is Vector3i:
		var position := _active_target as Vector3i
		if not bool(_is_overworld_active.call()) or not _is_valid_target(position) or _is_too_far(position):
			_active_target = null
			_view.hide_tip()
			return
		_view.set_outline_suppressed(_is_normal_outline_active(position))
		return
	if not _pending_target is Vector3i:
		set_process(false)
		return
	var pending_position := _pending_target as Vector3i
	if not bool(_is_overworld_active.call()) or not _is_valid_target(pending_position) or _is_too_far(pending_position):
		_pending_target = null
		_callout_arbiter.cancel_priority(self)
		set_process(false)
		return
	if not _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
		return
	_pending_target = null
	_active_target = pending_position
	_progress.complete_copper_mining_tip()
	_view.show_tip(pending_position)
	_view.set_outline_suppressed(_is_normal_outline_active(pending_position))

func _on_mining_tool_requirement_failed(
	position: Vector3i,
	block_id: int,
	action: MiningActionDefinition,
) -> void:
	if (
		_progress.is_copper_mining_tip_completed()
		or block_id != BlockId.Type.COPPER
		or action != _interactor.unarmed_primary_action
		or not bool(_is_overworld_active.call())
	):
		return
	_pending_target = position
	set_process(true)
	_callout_arbiter.request_priority(self, dismiss_for_priority_callout)
	_process(0.0)

func _on_block_mined(_position: Vector3i, block_id: int) -> void:
	if block_id != BlockId.Type.COPPER:
		return
	_progress.complete_copper_mining_tip()
	_pending_target = null
	_callout_arbiter.cancel_priority(self)
	if _active_target is Vector3i:
		_active_target = null
		_view.hide_tip()
	else:
		set_process(false)

func _on_view_hidden() -> void:
	_callout_arbiter.release(self)
	if not _pending_target is Vector3i and not _active_target is Vector3i:
		set_process(false)

func dismiss_for_priority_callout() -> void:
	_pending_target = null
	_callout_arbiter.cancel_priority(self)
	if _active_target is Vector3i:
		_active_target = null
		_view.hide_tip()
	else:
		set_process(false)

func _is_valid_target(position: Vector3i) -> bool:
	return _voxel_world.is_raycast_solid(position) and _voxel_world.get_block_id_at(position) == BlockId.Type.COPPER

func _is_too_far(position: Vector3i) -> bool:
	var center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
	return Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length() > DISMISS_DISTANCE

func _is_normal_outline_active(position: Vector3i) -> bool:
	return (
		_interactor.target_has
		and _interactor.target_block == position
		and _interactor.get_selected_primary_action() is MiningActionDefinition
	)
