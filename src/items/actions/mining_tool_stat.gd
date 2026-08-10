extends Resource
class_name MiningToolStat

@export var tag: StringName
@export_range(0, 999) var power: int = 0
@export_range(0.01, 100.0, 0.01) var speed_multiplier: float = 1.0

func validate(source: String) -> bool:
	var valid := true
	if tag.is_empty():
		push_error("[MiningToolStat] Empty tag at %s" % source)
		valid = false
	if power < 0:
		push_error("[MiningToolStat] Negative power at %s" % source)
		valid = false
	if speed_multiplier <= 0.0:
		push_error("[MiningToolStat] Non-positive speed at %s" % source)
		valid = false
	return valid
