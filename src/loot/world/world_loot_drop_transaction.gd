extends RefCounted
class_name WorldLootDropTransaction

static func try_commit(
	resolution: PreparedLootResolution,
	world_loot_state: WorldLootState,
	world_position: Vector3,
) -> bool:
	if resolution == null or world_loot_state == null:
		return false
	var factory := world_loot_state.equipment_instance_factory
	if not LootResolver._can_commit(resolution, factory):
		return false
	var pending_next_instance_id := resolution._get_pending_next_instance_id()
	var world_change := world_loot_state._prepare_add_batch(
		resolution.get_drops(),
		world_position,
		pending_next_instance_id,
	)
	if (
		world_change == null
		or not world_loot_state._can_commit_after_equipment_advance(
			world_change,
			pending_next_instance_id,
		)
	):
		return false
	var allocator_committed := LootResolver._commit(resolution, factory)
	assert(allocator_committed)
	if not allocator_committed:
		return false
	world_loot_state._commit_prepared_change(world_change)
	return true
