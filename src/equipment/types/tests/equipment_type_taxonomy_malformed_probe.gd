extends SceneTree

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var source := load("res://items/item_catalog.tres") as ItemCatalog
	var cycle_first := EquipmentTypeDefinition.new()
	cycle_first.id = &"cycle_first"
	cycle_first.display_name = "Cycle First"
	var cycle_second := EquipmentTypeDefinition.new()
	cycle_second.id = &"cycle_second"
	cycle_second.display_name = "Cycle Second"
	cycle_first.parent = cycle_second
	cycle_second.parent = cycle_first
	var cycle_catalog := _catalog(_types_with(source, [cycle_first, cycle_second]), source.definitions, source.equipment_affixes)

	var noncanonical_parent := source.get_equipment_type(&"weapon").duplicate() as EquipmentTypeDefinition
	var detached_type := EquipmentTypeDefinition.new()
	detached_type.id = &"weapon_detached"
	detached_type.display_name = "Detached Weapons"
	detached_type.parent = noncanonical_parent
	var parent_catalog := _catalog(_types_with(source, [detached_type]), source.definitions, source.equipment_affixes)

	var noncanonical_sword := source.get_equipment_type(&"weapon_sword").duplicate() as EquipmentTypeDefinition
	var detached_sword := source.get_definition(&"copper_sword").duplicate() as ItemDefinition
	detached_sword.id = &"detached_sword"
	detached_sword.display_name = "Detached Sword"
	detached_sword.equipment_type = noncanonical_sword
	var detached_definitions: Array[ItemDefinition] = []
	detached_definitions.assign(source.definitions)
	detached_definitions.append(detached_sword)
	var item_catalog := _catalog(source.equipment_types, detached_definitions, source.equipment_affixes)

	var untyped_sword := source.get_definition(&"copper_sword").duplicate() as ItemDefinition
	untyped_sword.id = &"untyped_sword"
	untyped_sword.display_name = "Untyped Sword"
	untyped_sword.equipment_type = null
	var untyped_definitions: Array[ItemDefinition] = []
	untyped_definitions.assign(source.definitions)
	untyped_definitions.append(untyped_sword)
	var melee_catalog := _catalog(source.equipment_types, untyped_definitions, source.equipment_affixes)

	if (
		block_catalog != null
		and source != null
		and not cycle_catalog.validate(block_catalog)
		and not parent_catalog.validate(block_catalog)
		and not item_catalog.validate(block_catalog)
		and not melee_catalog.validate(block_catalog)
	):
		print("EQUIPMENT_TYPE_TAXONOMY_MALFORMED PASS")
		quit(0)
	else:
		print("EQUIPMENT_TYPE_TAXONOMY_MALFORMED FAILED")
		quit(1)

func _types_with(source: ItemCatalog, additions: Array[EquipmentTypeDefinition]) -> Array[EquipmentTypeDefinition]:
	var types: Array[EquipmentTypeDefinition] = []
	types.assign(source.equipment_types)
	types.append_array(additions)
	return types

func _catalog(
	types: Array[EquipmentTypeDefinition],
	definitions: Array[ItemDefinition],
	equipment_affixes: Array[EquipmentAffixDefinition],
) -> ItemCatalog:
	var catalog := ItemCatalog.new()
	catalog.equipment_types = types
	catalog.definitions = definitions
	catalog.equipment_affixes = equipment_affixes
	return catalog
