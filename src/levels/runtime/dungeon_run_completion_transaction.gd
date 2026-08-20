extends RefCounted
class_name DungeonRunCompletionTransaction

enum Outcome {
	INCOMPLETE,
	COMPLETED,
	INVALIDATED,
}

static func try_complete(
	chests: DungeonChestCoordinator,
	progress: DungeonProgressState,
	dungeon_instance_id: StringName,
) -> Outcome:
	if chests == null or progress == null or dungeon_instance_id.is_empty():
		return Outcome.INVALIDATED
	if not chests.is_completion_context(progress, dungeon_instance_id):
		return Outcome.INVALIDATED
	var qualification := chests.prepare_completion_requirement(progress, dungeon_instance_id)
	if qualification == null:
		return Outcome.INCOMPLETE
	var progress_change := progress.prepare_completion(dungeon_instance_id)
	if (
		progress_change == null
		or not chests.can_commit_prepared_completion_requirement(qualification)
		or not progress.can_commit_prepared_completion(progress_change)
	):
		return Outcome.INVALIDATED
	var progress_committed := progress._commit_prepared_completion(progress_change)
	assert(progress_committed)
	if not progress_committed:
		return Outcome.INVALIDATED
	var qualification_committed := chests._commit_prepared_completion_requirement(qualification)
	assert(qualification_committed)
	if not qualification_committed:
		return Outcome.INVALIDATED
	var progress_notified := progress._notify_prepared_completion(progress_change)
	assert(progress_notified)
	return Outcome.COMPLETED
