extends Node
class_name PlayerActionAudio

@onready var _clunk_player: AudioStreamPlayer = $ClunkPlayer
@onready var _creature_hit_player: AudioStreamPlayer = $CreatureHitPlayer
@onready var _draw_player: AudioStreamPlayer = $DrawPlayer

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
var _draw_streams: Array[AudioStream] = [
	preload("res://assets/audio/combat/weapons/sword/draw/drawKnife1.ogg"),
	preload("res://assets/audio/combat/weapons/sword/draw/drawKnife2.ogg"),
	preload("res://assets/audio/combat/weapons/sword/draw/drawKnife3.ogg"),
]

var _last_clunk_idx: int = -1
var _last_creature_hit_idx: int = -1
var _last_draw_idx: int = -1


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
	if outcome.contact.source_runtime_id != MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		return
	_last_creature_hit_idx = _play_random(_creature_hit_player, _creature_hit_streams, _last_creature_hit_idx, 0.94, 1.06)


func _on_inventory_changed():
	var selected_item_id := _get_selected_item_id()
	if selected_item_id == _selected_item_id:
		return
	_selected_item_id = selected_item_id
	if _selected_item_is_melee():
		_last_draw_idx = _play_random(_draw_player, _draw_streams, _last_draw_idx, 0.98, 1.02)


func _get_selected_item_id() -> StringName:
	var selected_item_id = _inventory.get_selected_item_id()
	return StringName(selected_item_id) if selected_item_id != null else &""


func _selected_item_is_melee() -> bool:
	if _selected_item_id.is_empty():
		return false
	return _inventory.item_catalog.get_definition(_selected_item_id).primary_action is MeleeAttackActionDefinition


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
	_release_player(_draw_player)
	_clunk_streams.clear()
	_creature_hit_streams.clear()
	_draw_streams.clear()


func _release_player(player: AudioStreamPlayer):
	player.stop()
	player.stream = null
