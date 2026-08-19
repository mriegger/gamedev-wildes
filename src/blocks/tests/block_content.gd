extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var unarmed_mining := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var stone_pickaxe_mining := load("res://items/actions/definitions/stone_pickaxe_mining.tres") as MiningActionDefinition
	var copper_pickaxe_mining := load("res://items/actions/definitions/copper_pickaxe_mining.tres") as MiningActionDefinition
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(BlockId.Type.COPPER == 9, "copper stable ID changed")
	_expect(BlockId.Type.COBBLESTONE == 10, "cobblestone stable ID changed")
	_expect(BlockId.Type.MOSSY_STONE_BRICKS == 11, "mossy stone bricks stable ID changed")
	_expect(BlockId.Type.STONE_BRICKS == 12, "stone bricks stable ID changed")
	_expect(BlockId.Type.TERRACOTTA_BRICKS == 13, "terracotta bricks stable ID changed")
	_expect(BlockId.Type.WOOD_PLANKS == 14, "wood planks stable ID changed")
	_expect(BlockId.Type.ANVIL == 16, "anvil stable ID changed")
	_expect(BlockId.Type.CHEST == 17, "chest stable ID changed")
	_expect(BlockId.Type.CAULDRON == 18, "cauldron stable ID changed")
	var expected: Dictionary = {
		BlockId.Type.COBBLESTONE: [&"cobblestone_block", "Cobblestone", "cobblestone.png", true],
		BlockId.Type.MOSSY_STONE_BRICKS: [&"mossy_stone_bricks_block", "Mossy Stone Bricks", "mossy_stone_bricks.png", true],
		BlockId.Type.STONE_BRICKS: [&"stone_bricks_block", "Stone Bricks", "stone_bricks.png", true],
		BlockId.Type.TERRACOTTA_BRICKS: [&"terracotta_bricks_block", "Terracotta Bricks", "terracotta_bricks.png", true],
		BlockId.Type.WOOD_PLANKS: [&"wood_planks_block", "Wood Planks", "wood_planks.png", false],
	}
	var texture_set := BlockTextureSet.new(block_catalog)
	for block_id in expected:
		var values := expected[block_id] as Array
		var item_id := values[0] as StringName
		var display_name := values[1] as String
		var texture_name := values[2] as String
		var requires_copper_pickaxe := values[3] as bool
		var block := block_catalog.get_definition(block_id)
		var item := item_catalog.get_item_for_block(block_id)
		var texture_path := "res://assets/textures/blocks/%s" % texture_name
		_expect(BlockId.get_display_name(block_id) == display_name, "display name mismatch for %s" % item_id)
		_expect(block.is_solid and block.is_opaque and block.is_raycast_solid and block.is_breakable, "physical properties invalid for %s" % item_id)
		_expect(block.drop_item_id == item_id, "drop mismatch for %s" % item_id)
		_expect(block.top_texture.resource_path == texture_path, "top texture mismatch for %s" % item_id)
		_expect(block.side_texture.resource_path == texture_path, "side texture mismatch for %s" % item_id)
		_expect(block.bottom_texture.resource_path == texture_path, "bottom texture mismatch for %s" % item_id)
		_expect(block.top_texture.get_size() == Vector2(16, 16), "texture dimensions invalid for %s" % item_id)
		_expect(item.id == item_id and item.display_name == display_name, "item identity mismatch for %s" % item_id)
		_expect(item.icon.resource_path == texture_path, "item icon mismatch for %s" % item_id)
		var placement := item.secondary_action as BlockPlacementActionDefinition
		_expect(placement != null and placement.block == block, "placement mapping invalid for %s" % item_id)
		_expect(texture_set.top_layers[block_id] >= 0, "top texture layer missing for %s" % item_id)
		_expect(texture_set.side_layers[block_id] >= 0, "side texture layer missing for %s" % item_id)
		_expect(texture_set.bottom_layers[block_id] >= 0, "bottom texture layer missing for %s" % item_id)
		_expect(unarmed_mining.can_mine(block) != requires_copper_pickaxe, "unarmed mining rule invalid for %s" % item_id)
		_expect(stone_pickaxe_mining.can_mine(block) != requires_copper_pickaxe, "stone pickaxe mining rule invalid for %s" % item_id)
		_expect(copper_pickaxe_mining.can_mine(block), "copper pickaxe cannot mine %s" % item_id)
	var chest := block_catalog.get_definition(BlockId.Type.CHEST)
	var chest_item := item_catalog.get_item_for_block(BlockId.Type.CHEST)
	_expect(chest.container != null and chest.container.rows == 3 and chest.container.columns == 5 and chest.container.get_slot_count() == 15, "canonical chest container dimensions changed")
	_expect(chest.is_solid and chest.is_opaque and chest.is_raycast_solid, "chest physical properties invalid")
	_expect(chest.top_texture.resource_path == "res://assets/textures/blocks/chest_top.png", "chest top texture changed")
	_expect(chest.side_texture.resource_path == "res://assets/textures/blocks/chest_side.png", "chest side texture changed")
	_expect(chest.bottom_texture == chest.top_texture, "chest bottom texture changed")
	_expect(chest.top_texture.get_size() == Vector2(16, 16) and chest.side_texture.get_size() == Vector2(16, 16), "chest texture dimensions invalid")
	_expect(chest_item.id == &"chest" and chest_item.display_name == "Chest", "chest item identity changed")
	_expect(chest_item.icon.resource_path == "res://assets/textures/blocks/chest_front.png", "chest item icon changed")
	var chest_placement := chest_item.secondary_action as BlockPlacementActionDefinition
	_expect(chest_placement != null and chest_placement.block == chest, "chest placement mapping is not canonical")
	_expect(texture_set.top_layers[BlockId.Type.CHEST] == -1 and texture_set.side_layers[BlockId.Type.CHEST] == -1 and texture_set.bottom_layers[BlockId.Type.CHEST] == -1, "separately rendered chest leaked into chunk textures")
	_expect(not unarmed_mining.can_mine(chest), "unarmed mining can break the chest")
	if _errors.is_empty():
		print("BLOCK_CONTENT PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
