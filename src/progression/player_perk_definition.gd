extends Resource
class_name PlayerPerkDefinition

@export var id: StringName
@export var display_name: String
@export var stat_id: StringName
@export_range(0.0, 999999999.0, 0.01, "or_greater") var amount_per_rank: float
@export_range(1, 999, 1, "or_greater") var maximum_rank: int = 10

func validate(stats_definition: ActorStatsDefinition) -> bool:
	return (
		stats_definition != null
		and not id.is_empty()
		and not display_name.is_empty()
		and not stat_id.is_empty()
		and stats_definition.has_stat(stat_id)
		and is_finite(amount_per_rank)
		and amount_per_rank > 0.0
		and maximum_rank > 0
		and is_finite(amount_per_rank * maximum_rank)
	)

func get_amount(rank: int) -> float:
	assert(rank >= 0 and rank <= maximum_rank)
	return amount_per_rank * rank
