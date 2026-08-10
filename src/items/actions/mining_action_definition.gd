extends ItemActionDefinition
class_name MiningActionDefinition

@export var tool_stats: Array[MiningToolStat] = []

func get_tool_stat(tag: StringName) -> MiningToolStat:
	for stat in tool_stats:
		if stat.tag == tag:
			return stat
	return null

func can_mine(block: BlockDefinition) -> bool:
	if not block.is_breakable:
		return false
	if block.minimum_mining_power == 0:
		return true
	var stat := get_tool_stat(block.mining_tool_tag)
	return stat != null and stat.power >= block.minimum_mining_power

func get_mine_duration(block: BlockDefinition) -> float:
	assert(can_mine(block))
	var stat := get_tool_stat(block.mining_tool_tag)
	if stat == null:
		return block.mine_duration
	return block.mine_duration / stat.speed_multiplier

func validate(source: String) -> bool:
	var valid := true
	var seen_tags: Dictionary = {}
	for stat in tool_stats:
		if stat == null:
			push_error("[MiningActionDefinition] Null tool stat at %s" % source)
			valid = false
			continue
		if seen_tags.has(stat.tag):
			push_error("[MiningActionDefinition] Duplicate tool tag %s at %s" % [stat.tag, source])
			valid = false
		seen_tags[stat.tag] = true
		valid = stat.validate(source) and valid
	return valid
