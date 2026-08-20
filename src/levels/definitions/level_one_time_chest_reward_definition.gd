extends Resource
class_name LevelOneTimeChestRewardDefinition

@export var reward_id: StringName
@export var loot_bundle: LootBundleDefinition

func validate(source: String) -> bool:
	var valid := true
	if reward_id.is_empty():
		push_error("[LevelOneTimeChestRewardDefinition] Empty reward ID for %s" % source)
		valid = false
	if loot_bundle == null or not loot_bundle.validate():
		push_error("[LevelOneTimeChestRewardDefinition] Invalid loot bundle for %s in %s" % [reward_id, source])
		valid = false
	return valid
