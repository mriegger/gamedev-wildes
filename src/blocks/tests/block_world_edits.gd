extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var block_ids: Array[int] = [
		BlockId.Type.COBBLESTONE,
		BlockId.Type.MOSSY_STONE_BRICKS,
		BlockId.Type.STONE_BRICKS,
		BlockId.Type.TERRACOTTA_BRICKS,
		BlockId.Type.WOOD_PLANKS,
	]
	for block_id in block_ids:
		var display_name := BlockId.get_display_name(block_id)
		var position := Vector3i(block_id, 8, 0)
		var placement_edit := world.try_place_block(position, block_id)
		_expect(placement_edit.is_success(), "world placement failed for %s" % display_name)
		_expect(world.get_block_id_at(position) == block_id, "placed world state mismatch for %s" % display_name)
		var mining_edits := world.try_mine_block(position)
		_expect(mining_edits.size() == 1 and mining_edits[0].is_success(), "world mining failed for %s" % display_name)
		_expect(world.get_block_id_at(position) == BlockId.Type.AIR, "mined block remained for %s" % display_name)
	if _errors.is_empty():
		print("BLOCK_WORLD_EDITS PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
