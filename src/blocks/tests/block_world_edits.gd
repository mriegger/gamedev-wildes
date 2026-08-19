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
	var campfire := block_catalog.get_definition(BlockId.Type.CAMPFIRE)
	var anchor := Vector3i(2, 1, 2)
	_expect(not world.try_place_emplacement(anchor, BlockId.Type.CAMPFIRE).is_success(), "campfire placed without support")
	for offset in campfire.emplacement.support_offsets:
		_expect(world.try_place_block(anchor + offset, BlockId.Type.STONE).is_success(), "campfire support placement failed")
	var missing_support := anchor + Vector3i(1, -1, 1)
	_expect(world.try_mine_block(missing_support)[0].is_success(), "campfire support could not be removed")
	_expect(not world.try_place_emplacement(anchor, BlockId.Type.CAMPFIRE).is_success(), "campfire placed on incomplete support")
	_expect(world.try_place_block(missing_support, BlockId.Type.STONE).is_success(), "campfire support could not be restored")
	_expect(world.try_place_emplacement(anchor, BlockId.Type.CAMPFIRE).is_success(), "campfire 3x3 placement failed")
	for offset in campfire.emplacement.occupied_offsets:
		var cell: Vector3i = anchor + offset
		_expect(world.get_block_id_at(cell) == BlockId.Type.CAMPFIRE and world.is_raycast_solid(cell), "campfire footprint was not reserved")
	_expect(world.is_solid(anchor) and not world.is_solid(anchor + Vector3i(-1, 0, -1)), "campfire collision mask is not center-only")
	_expect(not world.try_place_block(anchor + Vector3i.RIGHT, BlockId.Type.STONE).is_success(), "block overlapped campfire footprint")
	_expect(not world.try_replace_block(anchor + Vector3i.RIGHT, BlockId.Type.CAMPFIRE, BlockId.Type.STONE).is_success(), "campfire footprint cell was replaced independently")
	var emplacement_snapshot := world.snapshot_emplacements()
	var block_snapshot := world.snapshot_block_edits()
	var restored_world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	restored_world.restore_block_edits(block_snapshot["placed"], block_snapshot["removed"])
	_expect(restored_world.restore_emplacements(emplacement_snapshot), "campfire snapshot did not restore")
	_expect(restored_world.get_emplacement_anchor(anchor + Vector3i(-1, 0, 1)) == anchor, "restored campfire footprint lost its anchor")
	var campfire_mining_edits := world.try_mine_block(anchor + Vector3i(-1, 0, -1))
	_expect(campfire_mining_edits.size() == 1 and campfire_mining_edits[0].old_id == BlockId.Type.CAMPFIRE and campfire_mining_edits[0].pos == anchor, "outer-cell mining did not remove one anchored campfire")
	_expect(world.try_place_emplacement(anchor, BlockId.Type.CAMPFIRE).is_success(), "campfire could not be replaced")
	var support_mining_edits := world.try_mine_block(anchor + Vector3i.DOWN)
	_expect(support_mining_edits.size() == 2 and support_mining_edits[1].old_id == BlockId.Type.CAMPFIRE, "support mining did not atomically remove campfire")
	_expect(world.snapshot_emplacements().is_empty(), "support mining retained campfire state")
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
