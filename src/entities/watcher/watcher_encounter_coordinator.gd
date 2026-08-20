extends Node
class_name WatcherEncounterCoordinator

const WatcherActorType := preload("res://entities/watcher/watcher_actor.gd")
const WatcherTeleportSearchType := preload("res://entities/watcher/watcher_teleport_search.gd")

const WATCHER_DEFINITION_ID: StringName = &"watcher"

var _player: PlayerMotor
var _screen_effect: WatcherScreenEffect
var _voxel_space: VoxelSpace
var _runtime: EntityRuntime
var _position_ready: Callable
var _tracked_runtime_ids: Dictionary = {}

func setup(player: PlayerMotor, screen_effect: WatcherScreenEffect) -> void:
	assert(player != null)
	assert(screen_effect != null)
	assert(_player == null and _screen_effect == null)
	_player = player
	_screen_effect = screen_effect

func bind_context(
	voxel_space: VoxelSpace,
	runtime: EntityRuntime,
	position_ready: Callable,
) -> void:
	assert(_player != null and _screen_effect != null)
	assert(voxel_space != null)
	assert(runtime != null)
	assert(not runtime.is_suspended())
	assert(position_ready.is_valid())
	unbind_context()
	_voxel_space = voxel_space
	_runtime = runtime
	_position_ready = position_ready
	_runtime.entity_removed.connect(_on_entity_removed)
	_track_aggressive_watchers()
	_screen_effect.set_presentation_enabled(true)

func unbind_context() -> void:
	if _runtime != null:
		if _runtime.entity_removed.is_connected(_on_entity_removed):
			_runtime.entity_removed.disconnect(_on_entity_removed)
	_tracked_runtime_ids.clear()
	_voxel_space = null
	_runtime = null
	_position_ready = Callable()
	if _screen_effect != null:
		_screen_effect.set_active(false)
		_screen_effect.set_presentation_enabled(false)

func record_melee_outcome(outcome: MeleeOutcome) -> void:
	if (
		outcome == null
		or _runtime == null
		or _voxel_space == null
		or _runtime.is_suspended()
		or outcome.target_defeated
		or outcome.contact.source_runtime_id != MeleeCombatCoordinator.PLAYER_RUNTIME_ID
		or outcome.contact.source_definition_id != MeleeCombatCoordinator.PLAYER_DEFINITION_ID
	):
		return
	_record_player_hit(outcome.contact.target_runtime_id, outcome.contact.target_definition_id)

func record_projectile_outcome(outcome: ProjectileOutcome) -> void:
	if outcome == null or _runtime == null or _voxel_space == null or _runtime.is_suspended() or outcome.target_defeated:
		return
	_record_player_hit(outcome.contact.target_runtime_id, outcome.contact.target_definition_id)

func _record_player_hit(target_runtime_id: int, target_definition_id: StringName) -> void:
	if target_definition_id != WATCHER_DEFINITION_ID:
		return
	var actor := _runtime.get_actor(target_runtime_id) as WatcherActorType
	if actor == null or actor.definition == null or actor.definition.id != WATCHER_DEFINITION_ID:
		return
	actor.record_player_attack()
	_tracked_runtime_ids[actor.runtime_id] = true
	_sync_tracking_state()
	_try_teleport(actor)

func reset_for_player_defeat(runtimes: Array[EntityRuntime]) -> void:
	for runtime in runtimes:
		assert(runtime != null)
		_reset_runtime_watchers(runtime)
	_tracked_runtime_ids.clear()
	_sync_tracking_state()

func get_tracked_count() -> int:
	return _tracked_runtime_ids.size()

func set_presentation_enabled(enabled: bool) -> void:
	assert(_screen_effect != null and _runtime != null)
	_screen_effect.set_presentation_enabled(enabled)

func _try_teleport(actor: WatcherActorType) -> bool:
	var previous_position := actor.global_position
	var candidates := WatcherTeleportSearchType.find_candidates(
		_voxel_space,
		actor.definition,
		actor.behavior_seed,
		actor.get_teleport_sequence(),
		_player.global_position,
		_player.get_world_bounds(),
		previous_position,
		_position_ready,
	)
	for candidate in candidates:
		if not _runtime.try_teleport_actor(actor.runtime_id, candidate):
			continue
		actor.record_teleport_committed(previous_position)
		return true
	return false

func _reset_runtime_watchers(runtime: EntityRuntime) -> void:
	for runtime_id in runtime.get_active_runtime_ids_for_definition(WATCHER_DEFINITION_ID):
		var actor := runtime.get_presented_actor(runtime_id) as WatcherActorType
		if actor != null and actor.is_aggressive():
			actor.reset_after_player_defeat()

func _track_aggressive_watchers() -> void:
	if _runtime == null or _runtime.is_suspended():
		return
	for actor in _runtime.get_active_actors():
		var watcher := actor as WatcherActorType
		if watcher != null and watcher.is_aggressive():
			_tracked_runtime_ids[watcher.runtime_id] = true
	_sync_tracking_state()

func _on_entity_removed(runtime_id: int) -> void:
	_remove_tracked_watcher(runtime_id)

func _remove_tracked_watcher(runtime_id: int) -> void:
	if not _tracked_runtime_ids.erase(runtime_id):
		return
	_sync_tracking_state()

func _sync_tracking_state() -> void:
	var has_tracked_watchers := not _tracked_runtime_ids.is_empty()
	_screen_effect.set_active(has_tracked_watchers)
