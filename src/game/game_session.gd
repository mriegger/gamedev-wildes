extends Node
class_name GameSession

signal save_status_changed(text: String)

const AUTO_SAVE_INTERVAL: float = 30.0
const EDIT_SAVE_DEBOUNCE: float = 2.0

var slot_id: int = -1
var save_data: Dictionary = {}

var _world: WorldController
var _player_stats: ActorStats
var _inventory: InventoryModel
var _equipment_instance_factory: EquipmentInstanceFactory
var _player_perks: PlayerPerks
var _item_proficiency: ItemProficiency
var _tutorial_progress: TutorialProgress
var _chest_storage: ChestStorage
var _world_loot_state: WorldLootState
var _dungeon_progress: DungeonProgressState
var _chest_coordinator: ChestCoordinator
var _overworld_loot: OverworldLootCoordinator
var _environment: GameEnvironment
var _persisted_position_query: Callable
var _pumpkin_patch: PumpkinPatchCoordinator
var _apple_trees: AppleTreeCoordinator
var _auto_save_elapsed: float = 0.0
var _edit_idle_elapsed: float = 0.0
var _playtime_accum: float = 0.0
var _pending_edit_save: bool = false
var _saving_suspended: bool = false

func _ready():
	set_process(false)

func setup(
	p_slot_id: int,
	p_save_data: Dictionary,
	p_world: WorldController,
	p_player_stats: ActorStats,
	p_inventory: InventoryModel,
	p_equipment_instance_factory: EquipmentInstanceFactory,
	p_player_perks: PlayerPerks,
	p_item_proficiency: ItemProficiency,
	p_tutorial_progress: TutorialProgress,
	p_chest_storage: ChestStorage,
	p_world_loot_state: WorldLootState,
	p_dungeon_progress: DungeonProgressState,
	p_chest_coordinator: ChestCoordinator,
	p_overworld_loot: OverworldLootCoordinator,
	p_environment: GameEnvironment,
	p_pumpkin_patch: PumpkinPatchCoordinator,
	p_apple_trees: AppleTreeCoordinator,
	p_persisted_position_query: Callable,
):
	assert(p_world != null)
	assert(p_player_stats != null)
	assert(p_inventory != null)
	assert(p_equipment_instance_factory != null)
	assert(p_inventory.equipment_instance_factory == p_equipment_instance_factory)
	assert(p_player_perks != null)
	assert(p_item_proficiency != null)
	assert(p_tutorial_progress != null)
	assert(
		p_chest_storage != null
		and p_chest_storage._uses_dependencies(
			p_inventory.item_catalog,
			p_equipment_instance_factory,
		)
	)
	assert(p_world_loot_state != null and p_world_loot_state.item_catalog == p_inventory.item_catalog)
	assert(p_world_loot_state.equipment_instance_factory == p_equipment_instance_factory)
	assert(p_dungeon_progress != null)
	assert(p_chest_coordinator != null)
	assert(p_overworld_loot != null and p_overworld_loot._uses_world_loot_state(p_world_loot_state))
	assert(p_environment != null)
	assert(p_pumpkin_patch != null)
	assert(p_apple_trees != null)
	assert(p_persisted_position_query.is_valid())
	slot_id = p_slot_id
	save_data = p_save_data
	_world = p_world
	_player_stats = p_player_stats
	_inventory = p_inventory
	_equipment_instance_factory = p_equipment_instance_factory
	_player_perks = p_player_perks
	_item_proficiency = p_item_proficiency
	_tutorial_progress = p_tutorial_progress
	_chest_storage = p_chest_storage
	_world_loot_state = p_world_loot_state
	_dungeon_progress = p_dungeon_progress
	_chest_coordinator = p_chest_coordinator
	_overworld_loot = p_overworld_loot
	_environment = p_environment
	_persisted_position_query = p_persisted_position_query
	_pumpkin_patch = p_pumpkin_patch
	_apple_trees = p_apple_trees
	_auto_save_elapsed = 0.0
	_edit_idle_elapsed = 0.0
	_playtime_accum = 0.0
	_pending_edit_save = false
	_saving_suspended = false
	set_process(slot_id != -1)
	if slot_id != -1:
		save_data["inventory"] = _inventory.to_dict()
		save_data["next_equipment_instance_id"] = _equipment_instance_factory.get_next_instance_id()
		save_data["player_perks"] = _player_perks.snapshot()
		save_data["tutorial_progress"] = _tutorial_progress.snapshot()
		save_data["world_loot"] = _world_loot_state.snapshot()
		save_data["dungeon_progress"] = _dungeon_progress.snapshot()
		save_data["pumpkin_patch"] = _pumpkin_patch.snapshot()
		save_data["apple_trees"] = _apple_trees.snapshot()
		SaveManager.update_last_played(slot_id, save_data)
		_world.voxel_model.block_edit_committed.connect(_on_world_edit)
		_pumpkin_patch.state_changed.connect(_queue_state_save)
		_apple_trees.state_changed.connect(_queue_state_save)
		_chest_coordinator.contents_changed.connect(_on_chest_contents_changed)
		_overworld_loot.state_changed.connect(_queue_state_save)
		_dungeon_progress.state_changed.connect(_queue_state_save)
		_tutorial_progress.changed.connect(_on_tutorial_progress_changed)

func _process(delta):
	_playtime_accum += delta
	if _is_save_blocked():
		return
	_auto_save_elapsed += delta
	if _pending_edit_save:
		_edit_idle_elapsed += delta
	if _pending_edit_save and _edit_idle_elapsed >= EDIT_SAVE_DEBOUNCE:
		_pending_edit_save = false
		_edit_idle_elapsed = 0.0
		save("edit")
	elif _auto_save_elapsed >= AUTO_SAVE_INTERVAL:
		_auto_save_elapsed = 0.0
		save("auto")

func _on_world_edit(_edit: BlockEdit):
	_queue_state_save()

func _on_chest_contents_changed(_position: Vector3i) -> void:
	_queue_state_save()

func _on_tutorial_progress_changed() -> void:
	save_data["tutorial_progress"] = _tutorial_progress.snapshot()
	_queue_state_save()

func _queue_state_save() -> void:
	_pending_edit_save = true
	_edit_idle_elapsed = 0.0
	save_status_changed.emit("Pending save...")

func save(reason: String) -> bool:
	if slot_id == -1 or _is_save_blocked():
		return false
	var time_to_save = _environment.get_time_of_day()
	var persisted_position := _persisted_position_query.call() as Vector3
	var success = SaveManager.save_world_state(
		slot_id,
		save_data,
		_world.voxel_model,
		persisted_position,
		_player_stats,
		_inventory,
		_equipment_instance_factory,
		_player_perks,
		_item_proficiency,
		_chest_storage,
		_world_loot_state,
		_dungeon_progress,
		_pumpkin_patch.snapshot(),
		_apple_trees.snapshot(),
		_playtime_accum,
		time_to_save,
	)
	if success:
		_auto_save_elapsed = 0.0
		_edit_idle_elapsed = 0.0
		_pending_edit_save = false
		_playtime_accum = 0.0
		save_status_changed.emit("Saved slot %d! (%s)" % [slot_id, reason])
	else:
		save_status_changed.emit("Save FAILED slot %d" % slot_id)
	return success

func suspend_saving():
	_saving_suspended = true

func resume_saving():
	_saving_suspended = false

func is_saving_suspended() -> bool:
	return _saving_suspended

func _is_save_blocked() -> bool:
	return _saving_suspended or _player_stats.is_dead()

func get_summary() -> String:
	if slot_id == -1:
		return "No save slot | Seed %d | %s" % [_world.config.seed_value, _environment.get_formatted_time()]
	var world_name = save_data.get("world_name", "World")
	var edit_count = _world.voxel_model.get_block_edit_count()
	return "Slot %d | Seed %d | %s | %s | %d edits" % [slot_id, _world.config.seed_value, world_name, _environment.get_formatted_time(), edit_count]

func shutdown(reason: String):
	set_process(false)
	if slot_id != -1:
		save(reason)
	if _world and _world.voxel_model and _world.voxel_model.block_edit_committed.is_connected(_on_world_edit):
		_world.voxel_model.block_edit_committed.disconnect(_on_world_edit)
	if _pumpkin_patch and _pumpkin_patch.state_changed.is_connected(_queue_state_save):
		_pumpkin_patch.state_changed.disconnect(_queue_state_save)
	if _apple_trees and _apple_trees.state_changed.is_connected(_queue_state_save):
		_apple_trees.state_changed.disconnect(_queue_state_save)
	if _chest_coordinator != null and _chest_coordinator.contents_changed.is_connected(_on_chest_contents_changed):
		_chest_coordinator.contents_changed.disconnect(_on_chest_contents_changed)
	if _overworld_loot != null and _overworld_loot.state_changed.is_connected(_queue_state_save):
		_overworld_loot.state_changed.disconnect(_queue_state_save)
	if _dungeon_progress != null and _dungeon_progress.state_changed.is_connected(_queue_state_save):
		_dungeon_progress.state_changed.disconnect(_queue_state_save)
	if _tutorial_progress != null and _tutorial_progress.changed.is_connected(_on_tutorial_progress_changed):
		_tutorial_progress.changed.disconnect(_on_tutorial_progress_changed)
