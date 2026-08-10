extends Resource
class_name ItemCatalog

@export var definitions: Array[ItemDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _definitions_by_id: Dictionary = {}
var _definitions_by_block: Array[ItemDefinition] = []
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_definitions_by_id.clear()
	_definitions_by_block.clear()
	_definitions_by_block.resize(BlockId.Type.COUNT)
	_is_valid = true
	for definition in definitions:
		if definition == null:
			push_error("[ItemCatalog] Null item definition")
			_is_valid = false
			continue
		var source := definition.resource_path
		if definition.id.is_empty():
			push_error("[ItemCatalog] Empty item ID at %s" % source)
			_is_valid = false
			continue
		if _definitions_by_id.has(definition.id):
			push_error("[ItemCatalog] Duplicate item ID %s at %s" % [definition.id, source])
			_is_valid = false
			continue
		if definition.icon == null:
			push_error("[ItemCatalog] Missing icon for %s at %s" % [definition.id, source])
			_is_valid = false
		if definition.max_stack < 1:
			push_error("[ItemCatalog] Invalid max stack for %s at %s" % [definition.id, source])
			_is_valid = false
		if definition.stat_modifier_activation == ItemDefinition.StatModifierActivation.EQUIPPED and not definition is ArmorDefinition:
			push_error("[ItemCatalog] Equipped modifiers require armor for %s at %s" % [definition.id, source])
			_is_valid = false
		_definitions_by_id[definition.id] = definition
		if not _is_supported_primary_action(definition.primary_action):
			push_error("[ItemCatalog] Unsupported primary action for %s at %s" % [definition.id, source])
			_is_valid = false
		if not _is_supported_secondary_action(definition.secondary_action):
			push_error("[ItemCatalog] Unsupported secondary action for %s at %s" % [definition.id, source])
			_is_valid = false
		if definition.held_scene != null:
			var scene_state := definition.held_scene.get_state()
			if scene_state.get_node_count() == 0 or not ClassDB.is_parent_class(scene_state.get_node_type(0), &"Node3D"):
				push_error("[ItemCatalog] Held scene root must be Node3D for %s at %s" % [definition.id, source])
				_is_valid = false
		for action in [definition.primary_action, definition.secondary_action]:
			if action == null:
				continue
			_is_valid = action.validate(source) and _is_valid
		var placement := definition.secondary_action as BlockPlacementActionDefinition
		if placement == null or placement.block == null:
			continue
		var block_id := int(placement.block.id)
		if not BlockId.is_valid(block_id) or block_id == BlockId.Type.AIR:
			continue
		if _definitions_by_block[block_id] != null:
			push_error("[ItemCatalog] Duplicate block mapping for %s at %s" % [BlockId.get_display_name(block_id), source])
			_is_valid = false
			continue
		_definitions_by_block[block_id] = definition

func _is_supported_primary_action(action: ItemActionDefinition) -> bool:
	return action == null or action is MiningActionDefinition or action is MeleeAttackActionDefinition

func _is_supported_secondary_action(action: ItemActionDefinition) -> bool:
	return action == null or action is BlockPlacementActionDefinition

func _ensure_lookup() -> void:
	if _definitions_by_block.size() != BlockId.Type.COUNT:
		_rebuild_lookup()

func validate(block_catalog: BlockCatalog) -> bool:
	_ensure_lookup()
	var valid := _is_valid
	var block_tags: Dictionary = {}
	var maximum_power_by_tag: Dictionary = {}
	for block in block_catalog.definitions:
		if block != null and not block.mining_tool_tag.is_empty():
			block_tags[block.mining_tool_tag] = true
	for definition in definitions:
		if definition == null:
			continue
		var armor := definition as ArmorDefinition
		if armor != null:
			valid = armor.validate(definition.resource_path) and valid
		var placement := definition.secondary_action as BlockPlacementActionDefinition
		if placement != null and placement.block != null and BlockId.is_valid(placement.block.id):
			if block_catalog.get_definition(placement.block.id) != placement.block:
				push_error("[ItemCatalog] Non-canonical block resource for %s" % definition.id)
				valid = false
		var mining := definition.primary_action as MiningActionDefinition
		if mining == null:
			continue
		for stat in mining.tool_stats:
			if stat == null or stat.tag.is_empty():
				continue
			if not block_tags.has(stat.tag):
				push_error("[ItemCatalog] Mining tag %s on %s has no matching block" % [stat.tag, definition.id])
				valid = false
			maximum_power_by_tag[stat.tag] = maxi(int(maximum_power_by_tag.get(stat.tag, 0)), stat.power)
	for block in block_catalog.definitions:
		if block == null:
			continue
		if not block.drop_item_id.is_empty() and not _definitions_by_id.has(block.drop_item_id):
			push_error("[ItemCatalog] Unknown drop item %s for %s" % [block.drop_item_id, BlockId.get_display_name(block.id)])
			valid = false
		if block.minimum_mining_power > int(maximum_power_by_tag.get(block.mining_tool_tag, 0)):
			push_error("[ItemCatalog] No tool can mine %s at power %d" % [BlockId.get_display_name(block.id), block.minimum_mining_power])
			valid = false
	return valid

func has_definition(id: StringName) -> bool:
	_ensure_lookup()
	return _definitions_by_id.has(id)

func get_definition(id: StringName) -> ItemDefinition:
	_ensure_lookup()
	assert(_definitions_by_id.has(id))
	return _definitions_by_id[id] as ItemDefinition

func get_item_for_block(block_id: int) -> ItemDefinition:
	_ensure_lookup()
	assert(BlockId.is_valid(block_id))
	assert(_definitions_by_block[block_id] != null)
	return _definitions_by_block[block_id]
