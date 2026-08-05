extends Node
class_name GameSession

signal save_status_changed(text: String)

const AUTO_SAVE_INTERVAL: float = 30.0
const EDIT_SAVE_DEBOUNCE: float = 2.0

var slot_id: int = -1
var save_data: Dictionary = {}

var _world: WorldController
var _player: PlayerMotor
var _inventory: InventoryModel
var _environment: GameEnvironment
var _auto_save_elapsed: float = 0.0
var _edit_idle_elapsed: float = 0.0
var _playtime_accum: float = 0.0
var _pending_edit_save: bool = false

func _ready():
	set_process(false)

func setup(p_slot_id: int, p_save_data: Dictionary, p_world: WorldController, p_player: PlayerMotor, p_inventory: InventoryModel, p_environment: GameEnvironment):
	slot_id = p_slot_id
	save_data = p_save_data
	_world = p_world
	_player = p_player
	_inventory = p_inventory
	_environment = p_environment
	_auto_save_elapsed = 0.0
	_edit_idle_elapsed = 0.0
	_playtime_accum = 0.0
	_pending_edit_save = false
	set_process(slot_id != -1)
	if slot_id != -1:
		SaveManager.update_last_played(slot_id, save_data)
		_world.voxel_model.block_edit_committed.connect(_on_world_edit)

func _process(delta):
	_auto_save_elapsed += delta
	_playtime_accum += delta
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
	_pending_edit_save = true
	_edit_idle_elapsed = 0.0
	save_status_changed.emit("Pending save...")

func save(reason: String) -> bool:
	if slot_id == -1:
		return false
	var time_to_save = _environment.get_time_of_day()
	var success = SaveManager.save_world_state(slot_id, save_data, _world.voxel_model, _player, _inventory, _playtime_accum, time_to_save)
	if success:
		_auto_save_elapsed = 0.0
		_edit_idle_elapsed = 0.0
		_pending_edit_save = false
		_playtime_accum = 0.0
		save_status_changed.emit("Saved slot %d! (%s)" % [slot_id, reason])
	else:
		save_status_changed.emit("Save FAILED slot %d" % slot_id)
	return success

func get_summary() -> String:
	if slot_id == -1:
		return "No save slot | Seed %d | %s" % [_world.config.seed_value, _environment.get_formatted_time()]
	var world_name = save_data.get("world_name", "World")
	var edit_count = _world.voxel_model.placed_blocks.size() + _world.voxel_model.removed_blocks.size()
	return "Slot %d | Seed %d | %s | %s | %d edits" % [slot_id, _world.config.seed_value, world_name, _environment.get_formatted_time(), edit_count]

func shutdown(reason: String):
	set_process(false)
	if slot_id != -1:
		save(reason)
	if _world and _world.voxel_model and _world.voxel_model.block_edit_committed.is_connected(_on_world_edit):
		_world.voxel_model.block_edit_committed.disconnect(_on_world_edit)
