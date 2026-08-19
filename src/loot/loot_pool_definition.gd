extends Resource
class_name LootPoolDefinition

@export var id: StringName
@export var independent_rolls: Array[LootIndependentRollDefinition]
@export var exclusive_groups: Array[LootExclusiveGroupDefinition]

func validate() -> bool:
	var valid := true
	if id.is_empty():
		push_error("[LootPoolDefinition] Empty pool ID at %s" % resource_path)
		valid = false
	if independent_rolls.is_empty() and exclusive_groups.is_empty():
		push_error("[LootPoolDefinition] Missing rolls for %s at %s" % [id, resource_path])
		valid = false
	var roll_ids: Dictionary = {}
	for roll_index in range(independent_rolls.size()):
		var roll := independent_rolls[roll_index]
		var source := "%s independent roll %d" % [resource_path, roll_index]
		if roll == null:
			push_error("[LootPoolDefinition] Missing independent roll %d for %s at %s" % [roll_index, id, resource_path])
			valid = false
			continue
		valid = roll.validate(source) and valid
		if roll_ids.has(roll.id):
			push_error("[LootPoolDefinition] Duplicate independent roll ID %s for %s at %s" % [roll.id, id, resource_path])
			valid = false
		roll_ids[roll.id] = true
	var group_ids: Dictionary = {}
	for group_index in range(exclusive_groups.size()):
		var group := exclusive_groups[group_index]
		var source := "%s exclusive group %d" % [resource_path, group_index]
		if group == null:
			push_error("[LootPoolDefinition] Missing exclusive group %d for %s at %s" % [group_index, id, resource_path])
			valid = false
			continue
		valid = group.validate(source) and valid
		if group_ids.has(group.id):
			push_error("[LootPoolDefinition] Duplicate exclusive group ID %s for %s at %s" % [group.id, id, resource_path])
			valid = false
		group_ids[group.id] = true
	return valid
