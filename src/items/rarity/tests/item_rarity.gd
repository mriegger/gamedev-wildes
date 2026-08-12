extends SceneTree

var _errors: Array[String] = []

func _init():
	var common := load("res://items/rarity/definitions/common.tres") as ItemRarityDefinition
	_expect(common != null and common.validate(), "Common rarity is invalid")
	_expect(common.id == &"common" and common.display_name == "Common", "Common rarity identity changed")
	_expect(common.display_color.a > 0.0, "Common rarity color is transparent")

	var invalid := ItemRarityDefinition.new()
	_expect(not invalid.validate(), "empty rarity passed validation")
	invalid.id = &"invalid"
	invalid.display_name = "Invalid"
	invalid.display_color = Color(NAN, 1.0, 1.0, 1.0)
	_expect(not invalid.validate(), "non-finite rarity color passed validation")
	invalid.display_color = Color(-0.1, 1.0, 1.0, 1.0)
	_expect(not invalid.validate(), "out-of-range rarity color passed validation")

	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(item_catalog.validate(block_catalog), "item catalog is invalid")
	var sword := item_catalog.get_definition(&"copper_sword")
	_expect(item_catalog.is_combat_item(sword.id), "copper sword is not classified as combat gear")
	_expect(sword.rarity == common, "copper sword does not use canonical Common rarity")
	for armor_id in [&"copper_helmet", &"copper_chest_plate", &"copper_pants", &"copper_shoes"]:
		_expect(item_catalog.is_combat_item(armor_id), "%s is not classified as combat gear" % armor_id)
		_expect(item_catalog.get_definition(armor_id).rarity == common, "%s does not use canonical Common rarity" % armor_id)
	_expect(not item_catalog.is_combat_item(&"copper_pickaxe"), "non-combat pickaxe is classified as combat gear")
	_expect(item_catalog.get_definition(&"copper_pickaxe").rarity == null, "non-combat pickaxe gained a rarity")

	if _errors.is_empty():
		print("ITEM_RARITY PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
