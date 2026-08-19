extends Resource
class_name FoliageCatalog

@export var species: Array[FoliageSpeciesDefinition]:
	set(value):
		species = value
		_rebuild_lookup()

var _species_by_block_id: Array[FoliageSpeciesDefinition] = []
var _total_generation_weight: int = 0
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_species_by_block_id.clear()
	_species_by_block_id.resize(BlockId.Type.COUNT)
	_total_generation_weight = 0
	_is_valid = true
	for definition in species:
		if definition == null:
			push_error("[FoliageCatalog] Null species definition")
			_is_valid = false
			continue
		var source := definition.resource_path
		if not definition.validate(source):
			_is_valid = false
			continue
		var block_id := int(definition.block.id)
		if _species_by_block_id[block_id] != null:
			push_error("[FoliageCatalog] Duplicate species for %s at %s" % [BlockId.get_display_name(block_id), source])
			_is_valid = false
			continue
		_species_by_block_id[block_id] = definition
		_total_generation_weight += definition.generation_weight
	for block_id in BlockId.DISPLAY_NAMES:
		if BlockId.is_foliage(block_id) and _species_by_block_id[block_id] == null:
			push_error("[FoliageCatalog] Missing species for %s" % BlockId.get_display_name(block_id))
			_is_valid = false

func _ensure_lookup() -> void:
	if _species_by_block_id.size() != BlockId.Type.COUNT:
		_rebuild_lookup()

func validate(block_catalog: BlockCatalog) -> bool:
	_ensure_lookup()
	if block_catalog == null:
		push_error("[FoliageCatalog] Block catalog is required")
		return false
	var valid := _is_valid
	for definition in species:
		if definition == null or definition.block == null or not BlockId.is_foliage(definition.block.id):
			continue
		if block_catalog.get_definition(definition.block.id) != definition.block:
			push_error("[FoliageCatalog] Non-canonical block for %s" % BlockId.get_display_name(definition.block.id))
			valid = false
	return valid

func get_species(block_id: int) -> FoliageSpeciesDefinition:
	_ensure_lookup()
	assert(BlockId.is_foliage(block_id))
	assert(_species_by_block_id[block_id] != null)
	return _species_by_block_id[block_id]

func get_total_generation_weight() -> int:
	_ensure_lookup()
	return _total_generation_weight
