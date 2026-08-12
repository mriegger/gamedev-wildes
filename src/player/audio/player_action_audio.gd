extends Node
class_name PlayerActionAudio

@onready var _clunk_player: AudioStreamPlayer = $ClunkPlayer
@onready var _creature_hit_player: AudioStreamPlayer = $CreatureHitPlayer
@onready var _player_hit_player: AudioStreamPlayer = $PlayerHitPlayer
@onready var _equip_player: AudioStreamPlayer = $EquipPlayer

var _interactor: PlayerInteractor
var _animation_driver: PlayerAnimationDriver
var _inventory: InventoryModel
var _combat: MeleeCombatCoordinator
var _selected_item_id: StringName
var _clunk_streams: Array[AudioStream] = [
	preload("res://assets/audio/sfx/tools/impactGeneric_light_001.ogg"),
	preload("res://assets/audio/sfx/tools/impactGeneric_light_002.ogg"),
	preload("res://assets/audio/sfx/tools/impactGeneric_light_003.ogg"),
	preload("res://assets/audio/sfx/tools/impactGeneric_light_004.ogg"),
]
var _creature_hit_streams: Array[AudioStream] = [
	preload("res://assets/audio/combat/impacts/creature/Stab_Knife_00.wav"),
	preload("res://assets/audio/combat/impacts/creature/Stab_Knife_01.wav"),
	preload("res://assets/audio/combat/impacts/creature/Stab_Knife_02.wav"),
]
var _player_hit_streams: Array[AudioStream] = [
	preload("res://assets/audio/combat/impacts/player/player_hit.wav"),
]
var _last_clunk_idx: int = -1
var _last_creature_hit_idx: int = -1
var _last_player_hit_idx: int = -1
var _last_equip_indices: Dictionary = {}


func setup(
	p_animation_driver: PlayerAnimationDriver,
	p_interactor: PlayerInteractor,
	p_inventory: InventoryModel,
	p_combat: MeleeCombatCoordinator,
):
	_animation_driver = p_animation_driver
	_interactor = p_interactor
	_inventory = p_inventory
	_combat = p_combat
	_selected_item_id = _get_selected_item_id()
	_animation_driver.mining_impact.connect(_on_mining_impact)
	_interactor.melee_terrain_hit.connect(_on_melee_terrain_hit)
	_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)
	_inventory.inventory_changed.connect(_on_inventory_changed)
	if _clunk_player.stream == null and not _clunk_streams.is_empty():
		_clunk_player.stream = _clunk_streams[0]


func _on_mining_impact():
	_play_clunk(-6.0)


func _on_melee_terrain_hit(_pos: Vector3i):
	_play_clunk(-4.0)


func _on_melee_outcome_committed(outcome: MeleeOutcome):
	var contact := outcome.contact
	if contact.source_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		_last_creature_hit_idx = _play_random(_creature_hit_player, _creature_hit_streams, _last_creature_hit_idx, 0.94, 1.06)
		return
	if contact.target_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		_last_player_hit_idx = _play_random(_player_hit_player, _player_hit_streams, _last_player_hit_idx, 0.96, 1.04)


func _on_inventory_changed():
	var selected_item_id := _get_selected_item_id()
	if selected_item_id == _selected_item_id:
		return
	_selected_item_id = selected_item_id
	_play_selected_item_equip()


func _get_selected_item_id() -> StringName:
	var selected_item_id = _inventory.get_selected_item_id()
	return StringName(selected_item_id) if selected_item_id != null else &""


func _play_selected_item_equip():
	if _selected_item_id.is_empty():
		return
	var profile := _inventory.item_catalog.get_definition(_selected_item_id).equip_audio
	if profile == null:
		return
	_equip_player.volume_db = profile.volume_db
	var last_index := int(_last_equip_indices.get(profile, -1))
	_last_equip_indices[profile] = _play_random(_equip_player, profile.streams, last_index, profile.pitch_min, profile.pitch_max)


func _play_clunk(volume_db: float = -6.0):
	_clunk_player.volume_db = volume_db
	_last_clunk_idx = _play_random(_clunk_player, _clunk_streams, _last_clunk_idx, 0.95, 1.07)


func _play_random(
	player: AudioStreamPlayer,
	streams: Array[AudioStream],
	last_idx: int,
	pitch_min: float,
	pitch_max: float,
) -> int:
	if streams.is_empty():
		return -1
	var idx := randi_range(0, streams.size() - 1)
	if streams.size() > 1:
		while idx == last_idx:
			idx = randi_range(0, streams.size() - 1)
	player.stop()
	player.stream = streams[idx]
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()
	return idx


func _exit_tree():
	if _animation_driver != null and _animation_driver.mining_impact.is_connected(_on_mining_impact):
		_animation_driver.mining_impact.disconnect(_on_mining_impact)
	if _interactor != null:
		if _interactor.melee_terrain_hit.is_connected(_on_melee_terrain_hit):
			_interactor.melee_terrain_hit.disconnect(_on_melee_terrain_hit)
	if _combat != null and _combat.melee_outcome_committed.is_connected(_on_melee_outcome_committed):
		_combat.melee_outcome_committed.disconnect(_on_melee_outcome_committed)
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
	_animation_driver = null
	_interactor = null
	_inventory = null
	_combat = null
	_release_player(_clunk_player)
	_release_player(_creature_hit_player)
	_release_player(_player_hit_player)
	_release_player(_equip_player)
	_clunk_streams.clear()
	_creature_hit_streams.clear()
	_player_hit_streams.clear()
	_last_equip_indices.clear()


func _release_player(player: AudioStreamPlayer):
	player.stop()
	player.stream = null
