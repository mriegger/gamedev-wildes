extends Node
class_name SlimeAttachmentCoordinator

const MAX_ATTACHMENTS: int = 4
const MIN_MOVEMENT_MULTIPLIER: float = 0.4
const DETACH_KNOCKBACK_SPEED: float = 5.0
const REATTACH_COOLDOWN_SECONDS: float = 4.0
const MODIFIER_SOURCE_ID: StringName = &"slime_attachment"
const MODIFIER_SOURCE_INSTANCE_ID: StringName = &"slime_attachments"

class Attachment:
	var runtime_id: int
	var slot_index: int
	var sequence: int
	var slow_fraction: float

	func _init(p_runtime_id: int, p_slot_index: int, p_sequence: int, p_slow_fraction: float) -> void:
		runtime_id = p_runtime_id
		slot_index = p_slot_index
		sequence = p_sequence
		slow_fraction = p_slow_fraction

var _player: PlayerMotor
var _player_stats: ActorStats
var _runtime: EntityRuntime
var _attachments: Dictionary = {}
var _next_sequence: int = 0

func _ready() -> void:
	process_physics_priority = 10
	set_physics_process(false)

func setup(player: PlayerMotor, player_stats: ActorStats) -> void:
	assert(player != null)
	assert(player.get_slime_attachment_anchor_count() == MAX_ATTACHMENTS)
	assert(player_stats != null and player_stats.has_stat(&"movement_speed_multiplier"))
	assert(_player == null and _player_stats == null)
	_player = player
	_player_stats = player_stats
	_player.jump_committed.connect(_on_jump_committed)
	var multiplier_applied := _apply_movement_multiplier(1.0)
	assert(multiplier_applied)

func bind_runtime(runtime: EntityRuntime) -> void:
	assert(_player != null and _player_stats != null)
	assert(runtime != null)
	if _runtime == runtime:
		return
	unbind_runtime()
	_runtime = runtime
	_runtime.entity_defeated.connect(_on_entity_defeated)
	set_physics_process(true)

func unbind_runtime() -> void:
	if _runtime == null:
		return
	_detach_all()
	if _runtime.entity_defeated.is_connected(_on_entity_defeated):
		_runtime.entity_defeated.disconnect(_on_entity_defeated)
	_runtime = null
	set_physics_process(false)

func clear_attachments() -> void:
	_detach_all()

func get_attached_count() -> int:
	return _attachments.size()

func is_attached(runtime_id: int) -> bool:
	return _attachments.has(runtime_id)

func _physics_process(_delta: float) -> void:
	if _runtime == null:
		return
	if _player.is_defeated() or _player_stats.is_dead():
		if not _attachments.is_empty():
			_detach_all()
		return
	if _runtime.is_suspended():
		return
	_sync_attachment_positions()
	_attach_overlapping_slimes()

func _attach_overlapping_slimes() -> void:
	if _attachments.size() >= MAX_ATTACHMENTS:
		return
	var candidate_ids := _runtime.get_active_runtime_ids_overlapping(_player.get_world_bounds())
	candidate_ids.sort()
	for runtime_id in candidate_ids:
		if _attachments.size() >= MAX_ATTACHMENTS:
			return
		if _attachments.has(runtime_id):
			continue
		var actor := _runtime.get_actor(runtime_id) as SlimeActor
		if actor == null or not actor.can_attach():
			continue
		var slot_index := _get_first_free_slot()
		assert(slot_index >= 0)
		var slow_fraction := actor.get_attachment_slow_fraction()
		var projected_multiplier := _calculate_movement_multiplier(slow_fraction)
		if not _can_apply_movement_multiplier(projected_multiplier):
			continue
		if not actor.attach(slot_index):
			continue
		_attachments[runtime_id] = Attachment.new(
			runtime_id,
			slot_index,
			_next_sequence,
			slow_fraction,
		)
		_next_sequence += 1
		var multiplier_applied := _apply_movement_multiplier(projected_multiplier)
		assert(multiplier_applied)
		_sync_attachment_position(_attachments[runtime_id] as Attachment)
		var initial_contact_committed := actor.commit_initial_attachment_contact()
		assert(initial_contact_committed)
		if _player_stats.is_dead():
			_detach_all()
			return

func _sync_attachment_positions() -> void:
	var runtime_ids: Array = _attachments.keys()
	runtime_ids.sort()
	for runtime_id in runtime_ids:
		_sync_attachment_position(_attachments[runtime_id] as Attachment)

func _sync_attachment_position(attachment: Attachment) -> void:
	var actor := _runtime.get_actor(attachment.runtime_id) as SlimeActor
	if actor == null:
		_remove_missing_attachment(attachment.runtime_id)
		return
	var position := _player.get_slime_attachment_anchor_position(attachment.slot_index)
	var relocated := _runtime.try_relocate_actor(attachment.runtime_id, position)
	assert(relocated)

func _remove_missing_attachment(runtime_id: int) -> void:
	if not _attachments.erase(runtime_id):
		return
	var multiplier_applied := _apply_movement_multiplier(_calculate_movement_multiplier())
	assert(multiplier_applied)

func _on_jump_committed() -> void:
	if _runtime == null or _runtime.is_suspended() or _attachments.is_empty():
		return
	var selected: Attachment
	for attachment_value in _attachments.values():
		var attachment := attachment_value as Attachment
		if (
			selected == null
			or attachment.slow_fraction > selected.slow_fraction
			or (
				is_equal_approx(attachment.slow_fraction, selected.slow_fraction)
				and attachment.sequence < selected.sequence
			)
		):
			selected = attachment
	assert(selected != null)
	_detach(selected.runtime_id)

func _detach(runtime_id: int) -> void:
	var attachment := _attachments.get(runtime_id) as Attachment
	if attachment == null:
		return
	var actor := _runtime.get_actor(runtime_id) as SlimeActor
	if actor != null:
		var direction := actor.global_position - _player.global_position
		direction.y = 0.0
		var detached := actor.detach(direction, DETACH_KNOCKBACK_SPEED, REATTACH_COOLDOWN_SECONDS)
		assert(detached)
	_attachments.erase(runtime_id)
	var multiplier_applied := _apply_movement_multiplier(_calculate_movement_multiplier())
	assert(multiplier_applied)

func _detach_all() -> void:
	if _attachments.is_empty():
		var multiplier_applied := _apply_movement_multiplier(1.0)
		assert(multiplier_applied)
		return
	var runtime_ids: Array = _attachments.keys()
	runtime_ids.sort()
	for runtime_id in runtime_ids:
		var actor := _runtime.get_presented_actor(runtime_id) as SlimeActor if _runtime != null else null
		if actor == null or not actor.is_attached():
			continue
		var direction := actor.global_position - _player.global_position
		direction.y = 0.0
		var detached := actor.detach(direction, DETACH_KNOCKBACK_SPEED, REATTACH_COOLDOWN_SECONDS)
		assert(detached)
	_attachments.clear()
	var multiplier_applied := _apply_movement_multiplier(1.0)
	assert(multiplier_applied)

func _on_entity_defeated(defeat: EntityDefeat) -> void:
	if not _attachments.erase(defeat.runtime_id):
		return
	var multiplier_applied := _apply_movement_multiplier(_calculate_movement_multiplier())
	assert(multiplier_applied)

func _get_first_free_slot() -> int:
	var occupied: Dictionary = {}
	for attachment_value in _attachments.values():
		occupied[(attachment_value as Attachment).slot_index] = true
	for slot_index in MAX_ATTACHMENTS:
		if not occupied.has(slot_index):
			return slot_index
	return -1

func _calculate_movement_multiplier(additional_slow_fraction: float = 0.0) -> float:
	var total_slow := additional_slow_fraction
	for attachment_value in _attachments.values():
		total_slow += (attachment_value as Attachment).slow_fraction
	return maxf(MIN_MOVEMENT_MULTIPLIER, 1.0 - total_slow)

func _can_apply_movement_multiplier(multiplier: float) -> bool:
	return _player_stats.can_replace_source_modifiers(
		MODIFIER_SOURCE_ID,
		MODIFIER_SOURCE_INSTANCE_ID,
		_create_movement_modifiers(multiplier),
	)

func _apply_movement_multiplier(multiplier: float) -> bool:
	return _player_stats.replace_source_modifiers(
		MODIFIER_SOURCE_ID,
		MODIFIER_SOURCE_INSTANCE_ID,
		_create_movement_modifiers(multiplier),
	)

func _create_movement_modifiers(multiplier: float) -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	if is_equal_approx(multiplier, 1.0):
		return modifiers
	var modifier := StatModifier.new()
	modifier.id = &"slime_attachment_movement"
	modifier.source_id = MODIFIER_SOURCE_ID
	modifier.source_instance_id = MODIFIER_SOURCE_INSTANCE_ID
	modifier.stat_id = &"movement_speed_multiplier"
	modifier.operation = StatModifier.Operation.MULTIPLY
	modifier.amount = multiplier
	modifiers.append(modifier)
	return modifiers

func _exit_tree() -> void:
	unbind_runtime()
	if is_instance_valid(_player) and _player.jump_committed.is_connected(_on_jump_committed):
		_player.jump_committed.disconnect(_on_jump_committed)
	_player = null
	_player_stats = null
