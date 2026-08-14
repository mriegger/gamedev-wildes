extends ItemActionDefinition
class_name BlockPlacementActionDefinition

@export var block: BlockDefinition

func validate(source: String) -> bool:
	if block == null:
		push_error("[BlockPlacementActionDefinition] Missing block at %s" % source)
		return false
	if not BlockId.is_valid(block.id) or block.id == BlockId.Type.AIR:
		push_error("[BlockPlacementActionDefinition] Invalid block at %s" % source)
		return false
	return true
