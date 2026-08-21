extends Node
class_name MiningTutorialCoordinator

const SHOW_DELAY_SECONDS: float = 5.0
const TARGET_RADIUS: int = 10
const DISMISS_DISTANCE: float = 14.0
const RETRY_DELAY_SECONDS: float = 1.0

var _voxel_world: VoxelWorld
var _player: Node3D
var _is_overworld_active: Callable
var _camera: Camera3D
var _interactor: PlayerInteractor
var _view: MiningTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _target: Variant = null

func _ready() -> void:
	set_process(false)

func setup(
	voxel_world: VoxelWorld,
	player: Node3D,
	is_overworld_active: Callable,
	camera: Camera3D,
	interactor: PlayerInteractor,
	view: MiningTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
	world_seed: int,
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
	_camera = camera
	_interactor = interactor
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_rng.seed = hash([world_seed, floori(player.global_position.x), floori(player.global_position.z)])
	_view.setup(camera)
	_interactor.block_mined.connect(_on_block_mined)
	_view.callout_hidden.connect(_on_view_hidden)
	set_process(not _progress.is_mining_tip_completed())

func _exit_tree() -> void:
	if _interactor != null and _interactor.block_mined.is_connected(_on_block_mined):
		_interactor.block_mined.disconnect(_on_block_mined)
	if _view != null and _view.callout_hidden.is_connected(_on_view_hidden):
		_view.callout_hidden.disconnect(_on_view_hidden)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)

func _process(delta: float) -> void:
	if _progress == null or _progress.is_mining_tip_completed():
		return
	if not bool(_is_overworld_active.call()):
		if _view.is_showing():
			_view.hide_tip()
		return
	if _target is Vector3i:
		if not _is_valid_target(_target as Vector3i):
			_view.hide_tip()
			_target = null
			_elapsed = SHOW_DELAY_SECONDS - RETRY_DELAY_SECONDS
			return
		if not _view.is_showing() and _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
			_view.show_tip(_target as Vector3i)
		_view.set_outline_suppressed(_is_normal_mining_outline_active(_target as Vector3i))
		var target_center := Vector3(_target as Vector3i) + Vector3(0.5, 0.5, 0.5)
		var distance := Vector2(_player.global_position.x - target_center.x, _player.global_position.z - target_center.z).length()
		if distance > DISMISS_DISTANCE:
			_complete()
		return
	_elapsed += delta
	if _elapsed < SHOW_DELAY_SECONDS:
		return
	if not _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
		return
	_target = _choose_target()
	if _target is Vector3i:
		_view.show_tip(_target as Vector3i)
	else:
		_callout_arbiter.release(self)
		_elapsed = SHOW_DELAY_SECONDS - RETRY_DELAY_SECONDS

func _choose_target() -> Variant:
	var reachable_candidates: Array[Vector3i] = []
	var reachable_visible_side_count: int = 0
	var radius_candidates: Array[Vector3i] = []
	var radius_visible_side_count: int = -1
	var origin := Vector2i(floori(_player.global_position.x), floori(_player.global_position.z))
	var camera_direction := Vector3(_camera.global_position.x - _player.global_position.x, 0.0, _camera.global_position.z - _player.global_position.z)
	if camera_direction.is_zero_approx():
		camera_direction = Vector3(_camera.global_basis.z.x, 0.0, _camera.global_basis.z.z)
	if not camera_direction.is_zero_approx():
		camera_direction = camera_direction.normalized()
	for x_offset in range(-TARGET_RADIUS, TARGET_RADIUS + 1):
		for z_offset in range(-TARGET_RADIUS, TARGET_RADIUS + 1):
			if x_offset * x_offset + z_offset * z_offset > TARGET_RADIUS * TARGET_RADIUS:
				continue
			var x := origin.x + x_offset
			var z := origin.y + z_offset
			var surface_y := _voxel_world.get_terrain_surface_y(x, z)
			if surface_y == VoxelSpace.NO_SURFACE_Y:
				continue
			var position := Vector3i(x, floori(surface_y), z)
			if not _is_valid_target(position):
				continue
			var screen_position := _camera.unproject_position(Vector3(position) + Vector3(0.5, 0.5, 0.5))
			if _camera.is_position_behind(Vector3(position) + Vector3(0.5, 0.5, 0.5)) or not get_viewport().get_visible_rect().grow(-8.0).has_point(screen_position):
				continue
			var visible_side_count := _get_camera_visible_side_count(position, camera_direction)
			if visible_side_count > radius_visible_side_count:
				radius_visible_side_count = visible_side_count
				radius_candidates.clear()
			if visible_side_count == radius_visible_side_count:
				radius_candidates.append(position)
			var target_center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
			if visible_side_count <= 0 or _player.global_position.distance_squared_to(target_center) > _interactor.reach * _interactor.reach:
				continue
			if visible_side_count > reachable_visible_side_count:
				reachable_visible_side_count = visible_side_count
				reachable_candidates.clear()
			if visible_side_count == reachable_visible_side_count:
				reachable_candidates.append(position)
	var pool := reachable_candidates if not reachable_candidates.is_empty() else radius_candidates
	if pool.is_empty():
		return null
	return pool[_rng.randi_range(0, pool.size() - 1)]

func _is_valid_target(position: Vector3i) -> bool:
	if _voxel_world.is_edit_protected(position) or not _voxel_world.is_raycast_solid(position):
		return false
	var block_id := _voxel_world.get_block_id_at(position)
	return block_id != BlockId.Type.AIR and _interactor.unarmed_primary_action.can_mine(_voxel_world.block_catalog.get_definition(block_id))

func _get_camera_visible_side_count(position: Vector3i, camera_direction: Vector3) -> int:
	var visible_side_count: int = 0
	for normal in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		if Vector3(normal).dot(camera_direction) > 0.15 and not _voxel_world.is_opaque(position + normal):
			visible_side_count += 1
	return visible_side_count

func _is_normal_mining_outline_active(position: Vector3i) -> bool:
	return (
		_interactor.target_has
		and _interactor.target_block == position
		and _interactor.can_primary_target
		and _interactor.get_selected_primary_action() is MiningActionDefinition
	)

func _on_block_mined(_position: Vector3i, _block_id: int) -> void:
	_complete()

func _on_view_hidden() -> void:
	_callout_arbiter.release(self)

func dismiss_for_priority_callout() -> void:
	_complete()

func _complete() -> void:
	if not _progress.complete_mining_tip():
		return
	_view.hide_tip()
	set_process(false)
