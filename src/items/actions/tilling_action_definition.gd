extends ItemActionDefinition
class_name TillingActionDefinition

@export var source_blocks: Array[BlockDefinition] = []
@export var result_block: BlockDefinition

func can_till(block: BlockDefinition) -> bool:
	return block != null and source_blocks.has(block)

func validate(source: String) -> bool:
	var valid := true
	if result_block == null or not BlockId.is_valid(result_block.id) or result_block.id == BlockId.Type.AIR:
		push_error("[TillingActionDefinition] Invalid result block at %s" % source)
		valid = false
	var source_ids: Dictionary = {}
	for block in source_blocks:
		if block == null or not BlockId.is_valid(block.id) or block.id == BlockId.Type.AIR:
			push_error("[TillingActionDefinition] Invalid source block at %s" % source)
			valid = false
			continue
		if source_ids.has(block.id):
			push_error("[TillingActionDefinition] Duplicate source block at %s" % source)
			valid = false
		source_ids[block.id] = true
		if result_block != null and block.id == result_block.id:
			push_error("[TillingActionDefinition] Source and result match at %s" % source)
			valid = false
	if source_blocks.is_empty():
		push_error("[TillingActionDefinition] Missing source blocks at %s" % source)
		valid = false
	return valid
