extends Resource
class_name EquipmentTypeDefinition

@export var id: StringName
@export var display_name: String
@export var parent: EquipmentTypeDefinition

func validate(source: String) -> bool:
	if id.is_empty() or display_name.is_empty():
		push_error("[EquipmentTypeDefinition] Missing identity at %s" % source)
		return false
	if parent == self:
		push_error("[EquipmentTypeDefinition] Type %s is its own parent at %s" % [id, source])
		return false
	return true

func is_or_inherits(expected_type: EquipmentTypeDefinition) -> bool:
	if expected_type == null:
		return false
	var visited: Dictionary = {}
	var current: EquipmentTypeDefinition = self
	while current != null:
		if current == expected_type:
			return true
		if visited.has(current):
			return false
		visited[current] = true
		current = current.parent
	return false

func overlaps_branch(branch_root: EquipmentTypeDefinition) -> bool:
	return branch_root != null and (is_or_inherits(branch_root) or branch_root.is_or_inherits(self))
