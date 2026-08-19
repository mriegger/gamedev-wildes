extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	if block_catalog == null or item_catalog == null:
		_finish()
		return

	var equipment_type := item_catalog.get_equipment_type(&"equipment")
	var weapon_type := item_catalog.get_equipment_type(&"weapon")
	var sword_type := item_catalog.get_equipment_type(&"weapon_sword")
	var hammer_type := item_catalog.get_equipment_type(&"weapon_hammer")
	var armor_type := item_catalog.get_equipment_type(&"armor")
	_expect(equipment_type.parent == null, "equipment type is not the root")
	_expect(weapon_type.parent == equipment_type, "weapon type has the wrong parent")
	_expect(sword_type.parent == weapon_type, "sword type has the wrong parent")
	_expect(hammer_type.parent == weapon_type, "hammer type has the wrong parent")
	_expect(armor_type.parent == equipment_type, "armor type has the wrong parent")
	_expect(sword_type.is_or_inherits(equipment_type), "sword does not inherit equipment")
	_expect(not sword_type.is_or_inherits(armor_type), "sword inherits armor")
	_expect(equipment_type.overlaps_branch(armor_type), "equipment root does not overlap the armor branch")
	_expect(armor_type.overlaps_branch(armor_type), "armor does not overlap its own branch")
	_expect(not weapon_type.overlaps_branch(armor_type), "weapon overlaps the armor branch")

	var sword := item_catalog.get_definition(&"copper_sword")
	_expect(sword.equipment_type == sword_type, "copper sword does not use the canonical sword type")
	var hammer := item_catalog.get_definition(&"copper_hammer")
	_expect(hammer.equipment_type == hammer_type, "copper hammer does not use the canonical hammer type")
	for armor_id in [&"copper_helmet", &"copper_chest_plate", &"copper_pants", &"copper_shoes"]:
		_expect(item_catalog.get_definition(armor_id).equipment_type == armor_type, "%s does not use the canonical armor type" % armor_id)

	var basic_rune := item_catalog.get_definition(&"basic_rune") as RuneDefinition
	var vicious := item_catalog.get_equipment_affix(&"vicious")
	var stout := item_catalog.get_equipment_affix(&"stout")
	_expect(basic_rune.is_compatible_with(sword), "basic rune rejected a sword")
	_expect(basic_rune.is_compatible_with(hammer), "basic rune rejected a hammer")
	_expect(vicious.is_compatible_with(sword), "Vicious rejected a sword")
	_expect(not vicious.is_compatible_with(hammer), "sword-only Vicious accepted a hammer")
	_expect(not stout.is_compatible_with(sword), "Stout accepted a sword")
	var helmet := item_catalog.get_definition(&"copper_helmet")
	_expect(basic_rune.is_compatible_with(helmet), "basic rune rejected armor")
	_expect(not vicious.is_compatible_with(helmet), "Vicious accepted armor")
	_expect(stout.is_compatible_with(helmet), "Stout rejected armor")
	var heavy_armor_type := EquipmentTypeDefinition.new()
	heavy_armor_type.id = &"armor_heavy"
	heavy_armor_type.display_name = "Heavy Armor"
	heavy_armor_type.parent = armor_type
	var heavy_helmet := helmet.duplicate() as ArmorDefinition
	heavy_helmet.id = &"test_heavy_helmet"
	heavy_helmet.display_name = "Test Heavy Helmet"
	heavy_helmet.equipment_type = heavy_armor_type
	var heavy_rune := basic_rune.duplicate() as RuneDefinition
	heavy_rune.id = &"test_heavy_rune"
	heavy_rune.display_name = "Test Heavy Rune"
	heavy_rune.compatible_equipment_types = _equipment_types([heavy_armor_type])
	heavy_rune.compatible_armor_slots = RuneDefinition.ArmorSlotMask.HEAD
	var heavy_modifier := basic_rune.socket_modifiers[0].duplicate() as StatModifier
	heavy_modifier.id = &"test_heavy_rune_hp"
	heavy_modifier.source_id = heavy_rune.id
	heavy_rune.socket_modifiers = _stat_modifiers([heavy_modifier])
	_expect(heavy_rune.validate("heavy armor subtype test", armor_type), "heavy-armor rune is invalid")
	_expect(heavy_rune.is_compatible_with(heavy_helmet), "heavy-armor rune rejected heavy armor")
	_expect(not heavy_rune.is_compatible_with(helmet), "heavy-armor rune accepted base armor")
	_expect(not heavy_rune.is_compatible_with(sword), "heavy-armor rune accepted a weapon")
	var heavy_stout := stout.duplicate() as EquipmentAffixDefinition
	heavy_stout.id = &"test_heavy_stout"
	heavy_stout.display_name_suffix = "of Heavy Testing"
	heavy_stout.compatible_equipment_types = _equipment_types([heavy_armor_type])
	heavy_stout.compatible_armor_slots = EquipmentAffixDefinition.ArmorSlotMask.HEAD
	_expect(heavy_stout.validate("heavy armor subtype test", armor_type), "heavy-armor affix is invalid")
	_expect(heavy_stout.is_compatible_with(heavy_helmet), "heavy-armor affix rejected heavy armor")
	_expect(not heavy_stout.is_compatible_with(helmet), "heavy-armor affix accepted base armor")
	_expect(not heavy_stout.is_compatible_with(sword), "heavy-armor affix accepted a weapon")
	var equipment_head_rune := heavy_rune.duplicate() as RuneDefinition
	equipment_head_rune.compatible_equipment_types = _equipment_types([equipment_type])
	_expect(equipment_head_rune.validate("equipment root test", armor_type), "equipment-root rune is invalid")
	_expect(equipment_head_rune.is_compatible_with(sword), "equipment-root rune rejected a weapon")
	_expect(equipment_head_rune.is_compatible_with(helmet), "equipment-root rune rejected head armor")
	_expect(not equipment_head_rune.is_compatible_with(item_catalog.get_definition(&"copper_chest_plate")), "equipment-root rune accepted chest armor")

	var staff_type := EquipmentTypeDefinition.new()
	staff_type.id = &"weapon_staff"
	staff_type.display_name = "Staffs"
	staff_type.parent = weapon_type
	var staff := sword.duplicate() as ItemDefinition
	staff.id = &"test_staff"
	staff.display_name = "Test Staff"
	staff.equipment_type = staff_type
	var equipment_types: Array[EquipmentTypeDefinition] = []
	equipment_types.assign(item_catalog.equipment_types)
	equipment_types.append(staff_type)
	equipment_types.append(heavy_armor_type)
	var definitions: Array[ItemDefinition] = []
	definitions.assign(item_catalog.definitions)
	definitions.append(staff)
	definitions.append(heavy_helmet)
	definitions.append(heavy_rune)
	var extended_catalog := ItemCatalog.new()
	extended_catalog.equipment_types = equipment_types
	extended_catalog.definitions = definitions
	var equipment_affixes: Array[EquipmentAffixDefinition] = []
	equipment_affixes.assign(item_catalog.equipment_affixes)
	equipment_affixes.append(heavy_stout)
	extended_catalog.equipment_affixes = equipment_affixes
	_expect(extended_catalog.validate(block_catalog), "catalog rejected a second weapon family")
	_expect(extended_catalog.is_combat_item(staff.id), "staff is not classified as combat equipment")
	_expect(basic_rune.is_compatible_with(staff), "weapon-compatible rune rejected a staff")
	_expect(not vicious.is_compatible_with(staff), "sword-only Vicious accepted a staff")
	_expect(not stout.is_compatible_with(staff), "armor-only Stout accepted a staff")
	var tooltip := ItemTooltip.new()
	tooltip._item_catalog = extended_catalog
	_expect(tooltip._get_rune_compatibility_line(heavy_rune) == "Compatible: Heavy Armor (Head)", "heavy-armor rune tooltip lost its subtype")
	_expect(tooltip._get_rune_compatibility_line(equipment_head_rune) == "Compatible: Equipment (Armor: Head)", "equipment-root rune tooltip lost its armor slot restriction")
	tooltip.free()

	var probe_output: Array = []
	var probe_exit := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://equipment/types/tests/equipment_type_taxonomy_malformed_probe.gd"],
		probe_output,
		true,
	)
	var probe_text := "\n".join(PackedStringArray(probe_output))
	_expect(probe_exit == 0, "malformed taxonomy probe exited %d" % probe_exit)
	_expect(probe_text.contains("EQUIPMENT_TYPE_TAXONOMY_MALFORMED PASS"), "catalog accepted a malformed taxonomy")
	_finish()

func _finish() -> void:
	if _errors.is_empty():
		print("EQUIPMENT_TYPE_TAXONOMY PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _equipment_types(values: Array[EquipmentTypeDefinition]) -> Array[EquipmentTypeDefinition]:
	return values

func _stat_modifiers(values: Array[StatModifier]) -> Array[StatModifier]:
	return values
