extends Resource
class_name ItemCatalog

@export var equipment_types: Array[EquipmentTypeDefinition]:
	set(value):
		equipment_types = value
		_rebuild_lookup()

@export var definitions: Array[ItemDefinition]:
	set(value):
		definitions = value
		_rebuild_lookup()

var _equipment_types_by_id: Dictionary = {}
var _definitions_by_id: Dictionary = {}
var _definitions_by_block: Array[ItemDefinition] = []
var _is_valid: bool = false

func _rebuild_lookup() -> void:
	_equipment_types_by_id.clear()
	_definitions_by_id.clear()
	_definitions_by_block.clear()
	_definitions_by_block.resize(BlockId.Type.COUNT)
	_is_valid = true
	for equipment_type in equipment_types:
		if equipment_type == null:
			push_error("[ItemCatalog] Null equipment type")
			_is_valid = false
			continue
		var source := equipment_type.resource_path
		if not equipment_type.validate(source):
			_is_valid = false
		if equipment_type.id.is_empty():
			continue
		if _equipment_types_by_id.has(equipment_type.id):
			push_error("[ItemCatalog] Duplicate equipment type ID %s at %s" % [equipment_type.id, source])
			_is_valid = false
			continue
		_equipment_types_by_id[equipment_type.id] = equipment_type
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
		if definition.display_name.is_empty():
			push_error("[ItemCatalog] Empty display name for %s at %s" % [definition.id, source])
			_is_valid = false
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
		if definition.proficiency != null and not definition.proficiency.validate():
			push_error("[ItemCatalog] Invalid proficiency for %s at %s" % [definition.id, source])
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
		if definition.equip_audio != null:
			_is_valid = definition.equip_audio.validate(source) and _is_valid
		var consumption := definition.secondary_action as ConsumableActionDefinition
		if consumption != null and definition.consume_audio == null:
			push_error("[ItemCatalog] Missing consume audio for %s at %s" % [definition.id, source])
			_is_valid = false
		elif consumption == null and definition.consume_audio != null:
			push_error("[ItemCatalog] Consume audio requires a consumable action for %s at %s" % [definition.id, source])
			_is_valid = false
		elif definition.consume_audio != null:
			_is_valid = definition.consume_audio.validate(source) and _is_valid
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
	return action == null or action is MiningActionDefinition or action is MeleeAttackActionDefinition or action is TillingActionDefinition

func _is_supported_secondary_action(action: ItemActionDefinition) -> bool:
	return action == null or action is BlockPlacementActionDefinition or action is ConsumableActionDefinition

func _ensure_lookup() -> void:
	if (
		_equipment_types_by_id.size() != equipment_types.size()
		or _definitions_by_block.size() != BlockId.Type.COUNT
		or _definitions_by_id.size() != definitions.size()
	):
		_rebuild_lookup()

func validate(block_catalog: BlockCatalog) -> bool:
	_ensure_lookup()
	var valid := _is_valid
	valid = _validate_equipment_type_hierarchy() and valid
	var weapon_type := _equipment_types_by_id.get(&"weapon") as EquipmentTypeDefinition
	var armor_type := _equipment_types_by_id.get(&"armor") as EquipmentTypeDefinition
	var armor_sets_by_id: Dictionary = {}
	var rarities_by_id: Dictionary = {}
	var block_tags: Dictionary = {}
	var maximum_power_by_tag: Dictionary = {}
	for block in block_catalog.definitions:
		if block != null and not block.mining_tool_tag.is_empty():
			block_tags[block.mining_tool_tag] = true
	for definition in definitions:
		if definition == null:
			continue
		var armor := definition as ArmorDefinition
		var rune := definition as RuneDefinition
		var melee := definition.primary_action as MeleeAttackActionDefinition
		if definition.equipment_type != null and not _is_canonical_equipment_type(definition.equipment_type):
			push_error("[ItemCatalog] Non-canonical equipment type %s for %s" % [definition.equipment_type.id, definition.id])
			valid = false
		if melee != null and (weapon_type == null or definition.equipment_type == null or not definition.equipment_type.is_or_inherits(weapon_type)):
			push_error("[ItemCatalog] Melee item %s has a non-weapon equipment type" % definition.id)
			valid = false
		if armor != null:
			if armor_type == null or definition.equipment_type == null or not definition.equipment_type.is_or_inherits(armor_type):
				push_error("[ItemCatalog] Armor item %s has a non-armor equipment type" % definition.id)
				valid = false
		elif definition.equipment_type != null and armor_type != null and definition.equipment_type.is_or_inherits(armor_type):
			push_error("[ItemCatalog] Non-armor item %s uses an armor equipment type" % definition.id)
			valid = false
		var combat_item := _is_combat_definition(definition)
		if combat_item and definition.proficiency == null:
			push_error("[ItemCatalog] Missing proficiency for combat item %s" % definition.id)
			valid = false
		if combat_item and definition.rarity == null:
			push_error("[ItemCatalog] Missing rarity for combat item %s" % definition.id)
			valid = false
		var rarity := definition.rarity
		if rarity != null:
			if not rarity.validate():
				push_error("[ItemCatalog] Invalid rarity for %s" % definition.id)
				valid = false
			elif rarities_by_id.has(rarity.id):
				if rarities_by_id[rarity.id] != rarity:
					push_error("[ItemCatalog] Non-canonical rarity %s for %s" % [rarity.id, definition.id])
					valid = false
			else:
				rarities_by_id[rarity.id] = rarity
		if armor != null:
			valid = armor.validate(definition.resource_path) and valid
			var armor_set := armor.armor_set
			if armor_set != null:
				if armor_sets_by_id.has(armor_set.id):
					if armor_sets_by_id[armor_set.id] != armor_set:
						push_error("[ItemCatalog] Non-canonical armor set %s for %s" % [armor_set.id, definition.id])
						valid = false
				else:
					armor_sets_by_id[armor_set.id] = armor_set
					valid = armor_set.validate(armor_set.resource_path) and valid
		if rune != null:
			valid = rune.validate(definition.resource_path, armor_type) and valid
			valid = _validate_compatible_equipment_types(rune.compatible_equipment_types, "rune %s" % rune.id) and valid
		var placement := definition.secondary_action as BlockPlacementActionDefinition
		if placement != null and placement.block != null and BlockId.is_valid(placement.block.id):
			if block_catalog.get_definition(placement.block.id) != placement.block:
				push_error("[ItemCatalog] Non-canonical block resource for %s" % definition.id)
				valid = false
		var tilling := definition.primary_action as TillingActionDefinition
		if tilling != null:
			if tilling.result_block != null and BlockId.is_valid(tilling.result_block.id) and block_catalog.get_definition(tilling.result_block.id) != tilling.result_block:
				push_error("[ItemCatalog] Non-canonical tilling result for %s" % definition.id)
				valid = false
			for source_block in tilling.source_blocks:
				if source_block != null and BlockId.is_valid(source_block.id) and block_catalog.get_definition(source_block.id) != source_block:
					push_error("[ItemCatalog] Non-canonical tilling source for %s" % definition.id)
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

func _validate_equipment_type_hierarchy() -> bool:
	var valid := true
	var root := _equipment_types_by_id.get(&"equipment") as EquipmentTypeDefinition
	if root == null or root.parent != null:
		push_error("[ItemCatalog] Missing canonical equipment root")
		valid = false
	for equipment_type in equipment_types:
		if equipment_type == null:
			continue
		if equipment_type.parent != null and not _is_canonical_equipment_type(equipment_type.parent):
			push_error("[ItemCatalog] Non-canonical parent %s for equipment type %s" % [equipment_type.parent.id, equipment_type.id])
			valid = false
		var visited: Dictionary = {}
		var current: EquipmentTypeDefinition = equipment_type
		while current != null:
			if visited.has(current):
				push_error("[ItemCatalog] Equipment type cycle includes %s" % equipment_type.id)
				valid = false
				break
			visited[current] = true
			current = current.parent
		if root != null and equipment_type != root and not equipment_type.is_or_inherits(root):
			push_error("[ItemCatalog] Equipment type %s is outside the equipment hierarchy" % equipment_type.id)
			valid = false
	return valid

func _validate_compatible_equipment_types(types: Array[EquipmentTypeDefinition], owner: String) -> bool:
	var valid := true
	for equipment_type in types:
		if not _is_canonical_equipment_type(equipment_type):
			var equipment_type_id: StringName = &"" if equipment_type == null else equipment_type.id
			push_error("[ItemCatalog] Non-canonical compatible equipment type %s for %s" % [equipment_type_id, owner])
			valid = false
	return valid

func _is_canonical_equipment_type(equipment_type: EquipmentTypeDefinition) -> bool:
	return (
		equipment_type != null
		and _equipment_types_by_id.has(equipment_type.id)
		and _equipment_types_by_id[equipment_type.id] == equipment_type
	)

func has_definition(id: StringName) -> bool:
	_ensure_lookup()
	return _definitions_by_id.has(id)

func get_equipment_type(id: StringName) -> EquipmentTypeDefinition:
	_ensure_lookup()
	assert(_equipment_types_by_id.has(id))
	return _equipment_types_by_id[id] as EquipmentTypeDefinition

func is_combat_item(id: StringName) -> bool:
	if not has_definition(id):
		return false
	return _is_combat_definition(get_definition(id))

func _is_combat_definition(definition: ItemDefinition) -> bool:
	return definition.equipment_type != null

func get_definition(id: StringName) -> ItemDefinition:
	_ensure_lookup()
	assert(_definitions_by_id.has(id))
	return _definitions_by_id[id] as ItemDefinition

func get_item_for_block(block_id: int) -> ItemDefinition:
	_ensure_lookup()
	assert(BlockId.is_valid(block_id))
	assert(_definitions_by_block[block_id] != null)
	return _definitions_by_block[block_id]
