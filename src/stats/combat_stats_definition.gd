extends ActorStatsDefinition
class_name CombatStatsDefinition

@export_group("Combat Stats")
@export_range(1.0, 999999.0, 1.0, "or_greater") var maximum_hp: float = 100.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var defense: float = 0.0
@export_range(0.0, 999999.0, 1.0, "or_greater") var strength: float = 10.0

func validate() -> bool:
	return (
		super.validate()
		and is_finite(maximum_hp)
		and maximum_hp > 0.0
		and is_finite(defense)
		and defense >= 0.0
		and is_finite(strength)
		and strength >= 0.0
	)

func get_base_stats() -> Dictionary:
	return {
		&"hp": maximum_hp,
		&"defense": defense,
		&"strength": strength,
	}
