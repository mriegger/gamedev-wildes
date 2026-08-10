extends ActorStatsDefinition
class_name PlayerStatsDefinition

@export_group("Core Stats")
@export_range(1.0, 999999.0, 1.0, "or_greater") var maximum_hp: float = 100.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var defense: float = 0.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var strength: float = 10.0

@export_group("Player Stats")
@export_range(0.0, 999999.0, 1.0, "or_greater") var mobility: float = 10.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var resilience: float = 0.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var recovery: float = 0.0

func get_base_stats() -> Dictionary:
	return {
		&"hp": maximum_hp,
		&"defense": defense,
		&"strength": strength,
		&"mobility": mobility,
		&"resilience": resilience,
		&"recovery": recovery,
	}
