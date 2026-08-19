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
		BlockId.Type.CHEST,
	]
	for block_id in block_ids:
		var display_name := BlockId.get_display_name(block_id)
		var position := Vector3i(block_id, 8, 0)
		var placement := VoxelWorldTestFixture.commit_place(world, position, block_id)
		_expect(placement != null, "world placement failed for %s" % display_name)
		_expect(world.get_block_id_at(position) == block_id, "placed world state mismatch for %s" % display_name)
		var mining := VoxelWorldTestFixture.commit_mine(world, position)
		_expect(mining != null and mining.get_edits().size() == 1, "world mining failed for %s" % display_name)
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
