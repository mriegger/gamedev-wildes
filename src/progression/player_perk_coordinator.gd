extends RefCounted
class_name PlayerPerkCoordinator

const MODIFIER_SOURCE_ID: StringName = &"player_perks"
const MODIFIER_SOURCE_INSTANCE_ID: StringName = &"player_perks"

var _player_perks: PlayerPerks
var _actor_stats: ActorStats

func setup(player_perks: PlayerPerks, actor_stats: ActorStats) -> bool:
	assert(player_perks != null)
	assert(actor_stats != null)
	_player_perks = player_perks
	_actor_stats = actor_stats
	return _apply_allocations()

func get_definitions() -> Array[PlayerPerkDefinition]:
	assert(_player_perks != null)
	return _player_perks.get_definitions()

func get_rank(perk_id: StringName) -> int:
	assert(_player_perks != null)
	return _player_perks.get_rank(perk_id)

func get_earned_point_count() -> int:
	assert(_player_perks != null and _actor_stats != null)
	return _player_perks.get_earned_point_count(_actor_stats.level)

func get_unspent_point_count() -> int:
	assert(_player_perks != null and _actor_stats != null)
	return _player_perks.get_unspent_point_count(_actor_stats.level)

func can_allocate(perk_id: StringName) -> bool:
	assert(_player_perks != null and _actor_stats != null)
	return _player_perks.can_allocate(perk_id, _actor_stats.level)

func try_allocate(perk_id: StringName) -> bool:
	assert(_player_perks != null and _actor_stats != null)
	if not _player_perks.can_allocate(perk_id, _actor_stats.level):
		return false
	var projected := PlayerPerks.new(_player_perks.get_rules())
	var projected_restored := projected.restore(_player_perks.snapshot(), _actor_stats.level)
	assert(projected_restored)
	var projected_allocated := projected.try_allocate(perk_id, _actor_stats.level)
	assert(projected_allocated)
	var modifiers := _build_modifiers(projected)
	if not _can_replace_modifiers(modifiers):
		return false
	var allocated := _player_perks.try_allocate(perk_id, _actor_stats.level)
	assert(allocated)
	var applied := _replace_modifiers(modifiers)
	assert(applied)
	return true

func snapshot() -> Dictionary:
	assert(_player_perks != null)
	return _player_perks.snapshot()

func restore(saved_state: Dictionary) -> bool:
	assert(_player_perks != null and _actor_stats != null)
	var projected := PlayerPerks.new(_player_perks.get_rules())
	if not projected.restore(saved_state, _actor_stats.level):
		return false
	var modifiers := _build_modifiers(projected)
	if not _can_replace_modifiers(modifiers):
		return false
	var restored := _player_perks.restore(saved_state, _actor_stats.level)
	assert(restored)
	var applied := _replace_modifiers(modifiers)
	assert(applied)
	return true

func restore_progression(stats_snapshot: Dictionary, perk_snapshot: Dictionary) -> bool:
	assert(_player_perks != null and _actor_stats != null)
	var restored_level := int(stats_snapshot.get("level", 0))
	var projected := PlayerPerks.new(_player_perks.get_rules())
	if not projected.restore(perk_snapshot, restored_level):
		return false
	var modifiers := _build_modifiers(projected)
	if not _actor_stats.can_restore_progression_with_replaced_source_modifiers(
		stats_snapshot,
		MODIFIER_SOURCE_ID,
		MODIFIER_SOURCE_INSTANCE_ID,
		modifiers,
	):
		return false
	var perks_restored := _player_perks.restore(perk_snapshot, restored_level)
	assert(perks_restored)
	var modifiers_applied := _replace_modifiers(modifiers)
	assert(modifiers_applied)
	var stats_restored := _actor_stats.restore_progression(stats_snapshot)
	assert(stats_restored)
	return true

func _apply_allocations() -> bool:
	var modifiers := _build_modifiers(_player_perks)
	if not _can_replace_modifiers(modifiers):
		return false
	return _replace_modifiers(modifiers)

func _build_modifiers(perks: PlayerPerks) -> Array[StatModifier]:
	var modifiers: Array[StatModifier] = []
	for perk_id in perks.get_perk_ids():
		var rank := perks.get_rank(perk_id)
		if rank == 0:
			continue
		var definition := perks.get_definition(perk_id)
		var modifier := StatModifier.new()
		modifier.id = perk_id
		modifier.source_id = MODIFIER_SOURCE_ID
		modifier.stat_id = definition.stat_id
		modifier.amount = definition.get_amount(rank)
		modifiers.append(modifier)
	return modifiers

func _can_replace_modifiers(modifiers: Array[StatModifier]) -> bool:
	return _actor_stats.can_replace_source_modifiers(
		MODIFIER_SOURCE_ID,
		MODIFIER_SOURCE_INSTANCE_ID,
		modifiers,
	)

func _replace_modifiers(modifiers: Array[StatModifier]) -> bool:
	return _actor_stats.replace_source_modifiers_preserving_health_ratio(
		MODIFIER_SOURCE_ID,
		MODIFIER_SOURCE_INSTANCE_ID,
		modifiers,
	)
