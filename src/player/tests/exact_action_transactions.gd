extends SceneTree

var _failures: int = 0
var _blocked_chest_position := Vector3i(2, 1, 0)

func _init() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[exact_action_transactions] FAIL: %s" % message)

func _can_break(position: Vector3i) -> bool:
	return position != _blocked_chest_position

func _run() -> void:
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	_expect(inventory.setup_empty(), "inventory setup failed")
	var pickaxe := InventoryStack.new(&"stone_pickaxe", 1, factory.create(&"stone_pickaxe"))
	var hoe := InventoryStack.new(&"copper_hoe", 1, factory.create(&"copper_hoe"))
	_expect(InventoryTestFixture.restore_slots(inventory, {
		0: pickaxe,
		1: InventoryStack.new(&"grass_block", 3),
		2: hoe,
		3: InventoryStack.new(&"campfire", 2),
	}), "action inventory restore failed")
	var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	var loadout := InventoryTestFixture.create_loadout(inventory, stats)
	_expect(loadout != null, "inventory loadout setup failed")
	var foreign_inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	_expect(foreign_inventory.setup_empty(), "foreign inventory setup failed")
	_expect(not inventory.is_selected_item_source_current(foreign_inventory.create_selected_item_source()), "foreign selected source passed owner validation")
	var unarmed := load("res://items/actions/definitions/unarmed_mining.tres") as MiningActionDefinition
	var mining := MiningActionExecutor.new()
	var tilling := TillingActionExecutor.new()
	var placement := BlockPlacementActionExecutor.new()
	_expect(mining.setup(inventory, loadout, unarmed, _can_break), "mining executor setup failed")
	_expect(tilling.setup(inventory), "tilling executor setup failed")
	_expect(placement.setup(inventory, loadout), "placement executor setup failed")
	var executors := PlayerActionExecutors.new()
	_expect(executors.setup(mining, tilling, placement), "action executor set setup failed")
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	var mine_position := Vector3i(0, 1, 0)
	var stale_mine_position := Vector3i(1, 1, 0)
	var till_position := Vector3i(3, 1, 0)
	var stale_till_position := Vector3i(4, 1, 0)
	var placement_position := Vector3i(5, 1, 0)
	var stale_placement_position := Vector3i(6, 1, 0)
	var protected_till_position := Vector3i(7, 1, 0)
	var campfire_anchor := Vector3i(10, 10, 10)
	world.restore_block_edits({
		mine_position: BlockId.Type.STONE,
		stale_mine_position: BlockId.Type.STONE,
		_blocked_chest_position: BlockId.Type.CHEST,
		till_position: BlockId.Type.GRASS,
		stale_till_position: BlockId.Type.DIRT,
		protected_till_position: BlockId.Type.GRASS,
	}, {})
	executors.bind_world(world)
	var mine_source := inventory.create_selected_item_source()
	_expect(loadout.add_backpack_item(&"copper", 1), "unrelated backpack setup failed")
	_expect(inventory.is_selected_item_source_current(mine_source), "unrelated backpack mutation invalidated mining source")
	var stone_count_before := inventory.get_inventory_item_count(&"stone_block")
	var mine_world_observed := [false]
	var mine_inventory_observed := [false]
	var mine_reentered := [false]
	var mine_world_listener := func(edit: BlockEdit) -> void:
		if edit.pos != mine_position:
			return
		mine_world_observed[0] = inventory.get_inventory_item_count(&"stone_block") == stone_count_before + 1
		if not mine_reentered[0]:
			mine_reentered[0] = true
			_expect(loadout.add_backpack_item(&"copper", 1), "mining world listener mutation failed")
	var mine_inventory_listener := func() -> void:
		if world.get_block_id_at(mine_position) == BlockId.Type.AIR:
			mine_inventory_observed[0] = true
	world.block_edit_committed.connect(mine_world_listener)
	inventory.inventory_changed.connect(mine_inventory_listener)
	var mine_edits := mining.try_mine(mine_position, mine_source)
	world.block_edit_committed.disconnect(mine_world_listener)
	inventory.inventory_changed.disconnect(mine_inventory_listener)
	_expect(not mine_edits.is_empty() and world.get_block_id_at(mine_position) == BlockId.Type.AIR, "valid exact-source mining failed")
	_expect(mine_world_observed[0] and mine_inventory_observed[0] and mine_reentered[0], "mining observers saw a partial transaction")
	var stale_mine_source := inventory.create_selected_item_source()
	_expect(loadout.select_slot(1), "stale mining selection setup failed")
	_expect(mining.try_mine(stale_mine_position, stale_mine_source).is_empty(), "stale mining source committed")
	_expect(world.get_block_id_at(stale_mine_position) == BlockId.Type.STONE, "stale mining source changed the world")
	_expect(loadout.select_slot(0), "blocked chest selection setup failed")
	_expect(mining.try_mine(_blocked_chest_position, inventory.create_selected_item_source()).is_empty(), "direct executor broke a blocked chest")
	_expect(world.get_block_id_at(_blocked_chest_position) == BlockId.Type.CHEST, "blocked chest world state changed")
	_expect(loadout.select_slot(2), "tilling selection setup failed")
	var till_source := inventory.create_selected_item_source()
	var till_edit := tilling.try_till(till_position, till_source)
	_expect(till_edit.is_success() and world.get_block_id_at(till_position) == BlockId.Type.FARMLAND_DRY, "valid tilling transaction failed")
	var stale_till_source := inventory.create_selected_item_source()
	_expect(loadout.select_slot(1), "stale till selection setup failed")
	var stale_till_edit := tilling.try_till(stale_till_position, stale_till_source)
	_expect(not stale_till_edit.is_success() and world.get_block_id_at(stale_till_position) == BlockId.Type.DIRT, "stale tilling source changed the world")
	_expect(loadout.select_slot(2), "protected till selection setup failed")
	world.protect_edit_cells([protected_till_position])
	var protected_till_edit := tilling.try_till(protected_till_position, inventory.create_selected_item_source())
	_expect(not protected_till_edit.is_success() and world.get_block_id_at(protected_till_position) == BlockId.Type.GRASS, "direct executor tilled a protected cell")
	_expect(loadout.select_slot(1), "placement selection setup failed")
	var placement_source := inventory.create_selected_item_source()
	var grass_count_before := inventory.get_inventory_item_count(&"grass_block")
	var placement_world_observed := [false]
	var placement_inventory_observed := [false]
	var placement_reentered := [false]
	var placement_world_listener := func(edit: BlockEdit) -> void:
		if edit.pos != placement_position:
			return
		placement_world_observed[0] = inventory.get_inventory_item_count(&"grass_block") == grass_count_before - 1
		if not placement_reentered[0]:
			placement_reentered[0] = true
			_expect(loadout.select_slot(0), "placement world listener mutation failed")
	var placement_inventory_listener := func() -> void:
		if world.get_block_id_at(placement_position) == BlockId.Type.GRASS:
			placement_inventory_observed[0] = true
	world.block_edit_committed.connect(placement_world_listener)
	inventory.inventory_changed.connect(placement_inventory_listener)
	var placement_edit := placement.try_place(placement_position, Vector3i.ZERO, placement_source)
	world.block_edit_committed.disconnect(placement_world_listener)
	inventory.inventory_changed.disconnect(placement_inventory_listener)
	_expect(placement_edit.is_success() and world.get_block_id_at(placement_position) == BlockId.Type.GRASS, "valid placement transaction failed")
	_expect(inventory.get_inventory_item_count(&"grass_block") == grass_count_before - 1, "placement did not consume exactly one selected block")
	_expect(placement_world_observed[0] and placement_inventory_observed[0] and placement_reentered[0], "placement observers saw a partial transaction")
	_expect(loadout.select_slot(1), "stale placement source setup failed")
	var stale_placement_source := inventory.create_selected_item_source()
	_expect(loadout.select_slot(0), "stale placement selection mutation failed")
	var stale_count_before := inventory.get_inventory_item_count(&"grass_block")
	var stale_placement_edit := placement.try_place(stale_placement_position, Vector3i.ZERO, stale_placement_source)
	_expect(not stale_placement_edit.is_success(), "stale placement source committed")
	_expect(world.get_block_id_at(stale_placement_position) == BlockId.Type.AIR, "stale placement source changed the world")
	_expect(inventory.get_inventory_item_count(&"grass_block") == stale_count_before, "stale placement source consumed inventory")
	var campfire_definition := block_catalog.get_definition(BlockId.Type.CAMPFIRE)
	for offset in campfire_definition.emplacement.support_offsets:
		_expect(VoxelWorldTestFixture.commit_place(world, campfire_anchor + offset, BlockId.Type.STONE) != null, "campfire support setup failed")
	_expect(loadout.select_slot(3), "campfire placement selection failed")
	var campfire_count_before := inventory.get_inventory_item_count(&"campfire")
	var campfire_source := inventory.create_selected_item_source()
	var campfire_edit := placement.try_place(campfire_anchor, Vector3i.ZERO, campfire_source)
	_expect(campfire_edit.is_success(), "campfire action placement failed")
	_expect(inventory.get_inventory_item_count(&"campfire") == campfire_count_before - 1, "campfire placement did not consume exactly one item")
	for offset in campfire_definition.emplacement.occupied_offsets:
		_expect(world.get_block_id_at(campfire_anchor + offset) == BlockId.Type.CAMPFIRE, "campfire action placement did not commit the full footprint")
	_expect(loadout.select_slot(0), "campfire mining selection failed")
	var campfire_mining := mining.try_mine(campfire_anchor + Vector3i(-1, 0, -1), inventory.create_selected_item_source())
	_expect(campfire_mining.size() == 1 and campfire_mining[0].old_id == BlockId.Type.CAMPFIRE, "campfire outer-cell mining failed")
	_expect(inventory.get_inventory_item_count(&"campfire") == campfire_count_before, "campfire mining did not return exactly one item")
	_expect(loadout.select_slot(3), "campfire replacement selection failed")
	_expect(placement.try_place(campfire_anchor, Vector3i.ZERO, inventory.create_selected_item_source()).is_success(), "campfire replacement failed")
	_expect(loadout.select_slot(0), "campfire support mining selection failed")
	var support_mining := mining.try_mine(campfire_anchor + Vector3i.DOWN, inventory.create_selected_item_source())
	_expect(support_mining.size() == 2 and support_mining[1].old_id == BlockId.Type.CAMPFIRE, "support mining did not cascade through the campfire action transaction")
	_expect(world.snapshot_emplacements().is_empty(), "support mining retained campfire world state")
	_expect(inventory.get_inventory_item_count(&"campfire") == campfire_count_before, "support mining did not return the campfire item")
	executors.unbind_world()
	if _failures == 0:
		print("EXACT_ACTION_TRANSACTIONS PASS")
		quit(0)
	else:
		print("EXACT_ACTION_TRANSACTIONS FAIL failures=%d" % _failures)
		quit(1)
