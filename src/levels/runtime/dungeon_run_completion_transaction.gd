extends RefCounted
class_name DungeonRunCompletionTransaction

enum Outcome {
	INCOMPLETE,
	COMPLETED,
	INVENTORY_FULL,
	INVALIDATED,
}

static func try_complete(
	chests: DungeonChestCoordinator,
	progress: DungeonProgressState,
	dungeon_instance_id: StringName,
	one_time_reward: LevelOneTimeChestRewardDefinition,
	loadout: InventoryLoadoutCoordinator,
) -> Outcome:
	if chests == null or progress == null or dungeon_instance_id.is_empty() or loadout == null:
		return Outcome.INVALIDATED
	if (
		one_time_reward != null
		and not progress.has_claimed_reward(dungeon_instance_id, one_time_reward.reward_id)
	):
		return _try_complete_one_time_reward(
			chests,
			progress,
			dungeon_instance_id,
			one_time_reward.reward_id,
			loadout,
		)
	if not chests.repeatable_reward_taken:
		return Outcome.INCOMPLETE
	var progress_change := progress.prepare_completion(dungeon_instance_id)
	if progress_change == null or not progress.can_commit_prepared_completion(progress_change):
		return Outcome.INVALIDATED
	var progress_committed := progress._commit_prepared_completion(progress_change)
	assert(progress_committed)
	if not progress_committed:
		return Outcome.INVALIDATED
	var progress_notified := progress._notify_prepared_completion(progress_change)
	assert(progress_notified)
	return Outcome.COMPLETED

static func _try_complete_one_time_reward(
	chests: DungeonChestCoordinator,
	progress: DungeonProgressState,
	dungeon_instance_id: StringName,
	reward_id: StringName,
	loadout: InventoryLoadoutCoordinator,
) -> Outcome:
	var claim := chests.prepare_one_time_claim()
	if claim == null:
		return Outcome.INCOMPLETE
	if claim.get_reward_id() != reward_id:
		return Outcome.INVALIDATED
	var inventory_change := loadout.inventory_model.prepare_add_stacks_exact(claim.get_stacks())
	if inventory_change == null:
		return Outcome.INVENTORY_FULL
	var loadout_change := loadout.prepare_inventory_change(inventory_change)
	var progress_change := progress.prepare_completion(dungeon_instance_id, reward_id)
	if (
		loadout_change == null
		or progress_change == null
		or not loadout.can_commit_prepared_change(loadout_change)
		or not progress.can_commit_prepared_completion(progress_change)
		or not chests.can_commit_prepared_claim(claim)
	):
		return Outcome.INVALIDATED
	var inventory_committed := loadout._commit_prepared_change(loadout_change)
	assert(inventory_committed)
	if not inventory_committed:
		return Outcome.INVALIDATED
	var progress_committed := progress._commit_prepared_completion(progress_change)
	assert(progress_committed)
	var claim_committed := chests.commit_prepared_claim(claim)
	assert(claim_committed)
	var inventory_notified := loadout._notify_prepared_change(loadout_change)
	assert(inventory_notified)
	var progress_notified := progress._notify_prepared_completion(progress_change)
	assert(progress_notified)
	return Outcome.COMPLETED
