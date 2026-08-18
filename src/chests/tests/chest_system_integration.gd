extends SceneTree

var _failures: Array[String] = []

func _init():
	call_deferred("_run")

func _run():
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog.validate(block_catalog), "item catalog invalid")

	var chest_definition := block_catalog.get_definition(BlockId.Type.CHEST)
	var container := chest_definition.container
	_expect(container != null and container.rows == 3 and container.columns == 5, "chest is not a 3x5 container")
	_expect(not chest_definition.is_breakable, "chest block is breakable")

	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var chest_position := Vector3i(2, 10, 3)
	var second_chest_position := Vector3i(5, 10, 3)
	_expect(world.try_place_block(chest_position, BlockId.Type.CHEST).is_success(), "chest placement failed")
	_expect(world.try_place_block(second_chest_position, BlockId.Type.CHEST).is_success(), "second chest placement failed")
	var mine_result := world.try_mine_block(chest_position)
	_expect(mine_result.size() == 1 and mine_result[0].result == BlockEdit.Result.FAIL_NOT_BREAKABLE, "voxel model mined the chest")
	_expect(world.get_block_id_at(chest_position) == BlockId.Type.CHEST, "failed mining removed the chest")

	var storage := ChestInventoryStore.new(item_catalog)
	var first_inventory := storage.get_or_create(chest_position, container.get_slot_count())
	var second_inventory := storage.get_or_create(second_chest_position, container.get_slot_count())
	_expect(first_inventory != null and first_inventory.size == 15, "first chest does not have 15 slots")
	_expect(second_inventory != null and second_inventory != first_inventory, "two world chests share one inventory model")
	_expect(storage.get_or_create(chest_position, container.get_slot_count()) == first_inventory, "reopened chest did not recover its position-linked inventory")
	first_inventory.slots[0] = InventoryStack.new(&"log_block", 2)
	second_inventory.slots[0] = InventoryStack.new(&"leaves_block", 5)

	var encoded: Variant = JSON.parse_string(JSON.stringify(storage.snapshot()))
	var restored_storage := ChestInventoryStore.new(item_catalog)
	_expect(encoded is Dictionary and restored_storage.restore(encoded), "chest storage JSON round trip failed")
	var oversized_storage := ChestInventoryStore.new(item_catalog)
	_expect(not oversized_storage.restore({"0,0,0": {"size": ContainerBlockDefinition.MAX_SLOT_COUNT + 1, "slots": []}}), "oversized chest save was accepted")
	var restored_inventory := restored_storage.get_inventory(chest_position)
	var restored_second_inventory := restored_storage.get_inventory(second_chest_position)
	_expect(restored_inventory != null and restored_inventory.size == 15, "restored chest has the wrong size")
	_expect(restored_inventory.get_slot(0).item_id == &"log_block" and restored_inventory.get_slot(0).count == 2, "restored chest changed its stack")
	_expect(restored_second_inventory != null and restored_second_inventory != restored_inventory, "restored world chests share one inventory model")
	_expect(restored_second_inventory.get_slot(0).item_id == &"leaves_block" and restored_second_inventory.get_slot(0).count == 5, "restored second chest lost its position-linked contents")

	if _failures.is_empty():
		print("CHEST_SYSTEM PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("[chest_system_integration] FAIL: %s" % failure)
		quit(1)

func _expect(condition: bool, message: String):
	if not condition:
		_failures.append(message)
