extends Resource
class_name StatModifier

enum Operation {
	ADD,
	MULTIPLY,
}

@export var id: StringName
@export var source_item_id: StringName
@export var source_item_instance_id: StringName
@export var stat_id: StringName
@export var operation: Operation = Operation.ADD
@export var amount: float = 0.0
@export_range(0.0, 86400.0, 0.01, "or_greater") var duration_seconds: float = 0.0

func is_valid(stats_definition: ActorStatsDefinition) -> bool:
	if id.is_empty() or source_item_id.is_empty() or stat_id.is_empty() or not stats_definition.has_stat(stat_id):
		return false
	if operation == Operation.MULTIPLY:
		return amount >= 0.0
	return operation == Operation.ADD
