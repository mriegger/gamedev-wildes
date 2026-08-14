extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var recipe_catalog := load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	var unarmed_mining := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var stone_pickaxe_mining := load("res://items/actions/definitions/stone_pickaxe_mining.tres") as MiningActionDefinition
	var copper_pickaxe_mining := load("res://items/actions/definitions/copper_pickaxe_mining.tres") as MiningActionDefinition
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(recipe_catalog.validate(item_catalog), "recipe catalog invalid")
	_expect(BlockId.Type.FARMLAND_DRY == 15, "farmland stable ID changed")
	_expect(BlockId.Type.BRICK == 100, "brick stable ID changed")
	_expect(BlockId.Type.CRACKED_CINDER_BRICKS == 101, "cracked cinder bricks stable ID changed")
	_expect(BlockId.Type.DEEPSTONE_BRICK == 102, "deepstone brick stable ID changed")
	_expect(BlockId.Type.SEDIMENTARY_STONE == 103, "sedimentary stone stable ID changed")
	_expect(BlockId.Type.CHISELED_MARBLE == 104, "chiseled marble stable ID changed")
	_expect(not BlockId.is_valid(99), "unassigned block ID accepted")
	var expected: Dictionary = {
		BlockId.Type.BRICK: [&"brick_block", "Brick", "brick.png"],
		BlockId.Type.CRACKED_CINDER_BRICKS: [&"cracked_cinder_bricks_block", "Cracked Cinder Bricks", "cracked_cinder_bricks.png"],
		BlockId.Type.DEEPSTONE_BRICK: [&"deepstone_brick_block", "Deepstone Brick", "deepstone_brick.png"],
		BlockId.Type.SEDIMENTARY_STONE: [&"sedimentary_stone_block", "Sedimentary Stone", "sedimentary_stone.png"],
		BlockId.Type.CHISELED_MARBLE: [&"chiseled_marble_block", "Chiseled Marble", "chiseled_marble.png"],
	}
	var texture_set := BlockTextureSet.new(block_catalog)
	for block_id in expected:
		var values := expected[block_id] as Array
		var item_id := values[0] as StringName
		var display_name := values[1] as String
		var texture_path := "res://assets/textures/blocks/%s" % (values[2] as String)
		var block := block_catalog.get_definition(block_id)
		var item := item_catalog.get_item_for_block(block_id)
		_expect(BlockId.get_display_name(block_id) == display_name, "display name mismatch for %s" % item_id)
		_expect(block.is_solid and block.is_opaque and block.is_raycast_solid and block.is_breakable, "physical properties invalid for %s" % item_id)
		_expect(block.mining_tool_tag == &"pickaxe" and block.minimum_mining_power == 1, "mining requirement invalid for %s" % item_id)
		_expect(not unarmed_mining.can_mine(block), "bare hands can mine %s" % item_id)
		_expect(stone_pickaxe_mining.can_mine(block), "stone pickaxe cannot mine %s" % item_id)
		_expect(copper_pickaxe_mining.can_mine(block), "copper pickaxe cannot mine %s" % item_id)
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
		_expect(not recipe_catalog.has_definition(item_id), "unexpected recipe for %s" % item_id)
	if _errors.is_empty():
		print("MASONRY_BLOCK_CONTENT PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
