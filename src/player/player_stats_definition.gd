extends CombatStatsDefinition
class_name PlayerStatsDefinition

@export_group("Player Stats")
@export_range(0.0, 999999.0, 1.0, "or_greater") var mobility: float = 10.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var resilience: float = 0.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var recovery: float = 0.0

func get_base_stats() -> Dictionary:
	var stats := super.get_base_stats()
	stats[&"mobility"] = mobility
	stats[&"resilience"] = resilience
	stats[&"recovery"] = recovery
	return stats
