extends Resource
class_name FoliageSpeciesDefinition

@export var block: BlockDefinition
@export_range(1, 100, 1) var generation_weight: int = 1

func validate(source: String) -> bool:
	var valid := true
	if block == null:
		push_error("[FoliageSpeciesDefinition] Missing block at %s" % source)
		valid = false
	elif not BlockId.is_foliage(block.id):
		push_error("[FoliageSpeciesDefinition] Non-foliage block at %s" % source)
		valid = false
	elif block.is_solid or block.is_opaque or not block.is_raycast_solid or not block.is_breakable or not block.is_replaceable:
		push_error("[FoliageSpeciesDefinition] Invalid block properties at %s" % source)
		valid = false
	if block != null and block.sprite_texture == null:
		push_error("[FoliageSpeciesDefinition] Missing texture at %s" % source)
		valid = false
	elif block != null and (block.sprite_texture.get_width() != 16 or block.sprite_texture.get_height() != 16):
		push_error("[FoliageSpeciesDefinition] Texture must be 16x16 at %s" % source)
		valid = false
	if block != null and block.interaction_bounds == null:
		push_error("[FoliageSpeciesDefinition] Missing interaction bounds at %s" % source)
		valid = false
	if generation_weight <= 0:
		push_error("[FoliageSpeciesDefinition] Generation weight must be positive at %s" % source)
		valid = false
	return valid
