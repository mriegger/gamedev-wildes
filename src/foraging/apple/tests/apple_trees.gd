extends SceneTree

var _failures: int = 0

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var world := VoxelWorld.new(20, 36, 5, 12.0, block_catalog)
	var chunk_manager := ChunkManager.new()
	chunk_manager.visible_chunks[Vector2i.ZERO] = true
	var apple_trees := (load("res://foraging/apple/apple_tree_coordinator.tscn") as PackedScene).instantiate() as AppleTreeCoordinator
	root.add_child(apple_trees)
	_expect(apple_trees.definition.apple_scene.resource_path == "res://assets/models/foraging/apple/apple.glb", "apple trees did not use the Kenney Food Kit model")
	var apple_position := _find_apple_tree_position(apple_trees.definition, 872341)
	_populate_tree(world, apple_position)
	_expect(apple_trees.setup(world, chunk_manager, 872341, null, item_catalog), "apple tree setup rejected valid content")
	_expect(apple_trees.validate_harvest_items(item_catalog), "apple harvest item was not catalogued")
	var apple_tree_count := _count_apple_trees(apple_trees, 10000)
	_expect(apple_tree_count >= 400 and apple_tree_count <= 600, "apple tree rate was not approximately five percent: %d" % apple_tree_count)
	var chunk_root := apple_trees.get_node_or_null("AppleTrees_0_0") as Node3D
	_expect(chunk_root != null, "apple tree presentation was not created")
	if chunk_root != null:
		var ground_count := 0
		var decorative_count := 0
		var lower_canopy_count := 0
		var foliage_count := 0
		for child in chunk_root.get_children():
			if child.name.begins_with("GroundApple_"):
				ground_count += 1
			elif child.name.begins_with("DecorativeApple_"):
				decorative_count += 1
				if (child as Node3D).position.y <= apple_position.y + 5.1:
					lower_canopy_count += 1
				var offset := (child as Node3D).position - Vector3(apple_position.x + 0.5, (child as Node3D).position.y, apple_position.z + 0.5)
				var surface_offset := maxf(absf(offset.x), absf(offset.z))
				_expect(surface_offset >= 1.49 and surface_offset <= 1.51, "decorative apple was not attached to an outer leaf face")
			elif child.name.begins_with("AppleFoliage_"):
				foliage_count += 1
				var foliage := child as MeshInstance3D
				var material := (foliage.mesh as BoxMesh).material as StandardMaterial3D
				_expect(material != null and material.albedo_color == apple_trees.definition.foliage_tint, "apple foliage did not use its distinguishing tint")
		_expect(ground_count >= 2 and ground_count <= 6, "apple tree did not have two to six ground apples")
		_expect(decorative_count == 20, "apple tree did not have exactly twenty decorative apples")
		_expect(lower_canopy_count >= 15, "decorative apples were not biased toward the lower canopy")
		_expect(foliage_count == 9, "apple tree foliage tint did not cover every generated leaf block")
		_expect(apple_trees._targets.size() == ground_count, "decorative apples became harvest targets")
		if not apple_trees._targets.is_empty():
			var first_bounds := apple_trees.get_harvest_target_bounds(int(apple_trees._targets.keys()[0]))
			var ray_target := apple_trees.find_harvest_target(first_bounds.get_center() + Vector3.UP, Vector3.DOWN, 2.0)
			_expect(not ray_target.is_empty(), "ground apple could not be selected by a ray")
			var inventory := InventoryModel.new(item_catalog)
			var target_id := int(apple_trees._targets.keys()[0])
			var item_ids := apple_trees.get_harvest_item_ids(target_id)
			_expect(inventory.can_add_batch(item_ids), "empty inventory rejected an apple")
			_expect(apple_trees.try_harvest_target(target_id), "ground apple could not be picked up")
			_expect(inventory.add_batch(item_ids), "picked apple could not enter inventory")
			_expect(inventory.get_inventory_item_count(&"apple") == 1, "pickup did not add one apple")
			var stats := ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
			var maximum_hp := stats.get_value(&"hp")
			stats.damage(maximum_hp * 0.9)
			var consumption_coordinator := ItemConsumptionCoordinator.new()
			consumption_coordinator.setup(inventory, stats)
			var apple_slot := _find_item_slot(inventory, &"apple")
			_expect(consumption_coordinator.try_consume_at(apple_slot), "apple could not be consumed")
			_expect(is_equal_approx(stats.current_hp, maximum_hp * 0.2), "apple consumption did not heal ten percent of maximum health")
			var snapshot := apple_trees.snapshot()
			var restored := AppleTreeState.new()
			_expect(restored.restore(JSON.parse_string(JSON.stringify(snapshot))), "apple pickup state did not restore")
			_expect(restored.snapshot() == snapshot, "apple pickup state changed during save round trip")
			var before_invalid_restore := restored.snapshot()
			_expect(not restored.restore({"version": 1, "collected_slots": [[0, 6, 0, 6]]}), "out-of-range apple slot restored")
			_expect(restored.snapshot() == before_invalid_restore, "failed apple state restore changed collected slots")
	var apple := item_catalog.get_definition(&"apple")
	var consumption := apple.secondary_action as ConsumableActionDefinition
	_expect(consumption != null and is_equal_approx(consumption.health_restore_fraction, 0.1), "apple did not restore ten percent of maximum health")
	_expect(apple.consume_audio != null and apple.consume_audio.streams.size() == 1, "apple munch audio was not configured")
	apple_trees.free()
	if _failures == 0:
		print("APPLE_TREES PASS")
		quit(0)
	else:
		print("APPLE_TREES FAILED failures=%d" % _failures)
		quit(1)

func _find_apple_tree_position(definition: AppleTreeDefinition, seed_value: int) -> Vector3i:
	var probe := AppleTreeCoordinator.new()
	probe.definition = definition
	probe._world_seed = seed_value
	for x in range(20):
		for z in range(20):
			var position := Vector3i(x, 6, z)
			if probe._is_apple_tree(position):
				probe.free()
				return position
	probe.free()
	return Vector3i(-1, 6, -1)

func _populate_tree(world: VoxelWorld, tree_position: Vector3i) -> void:
	_expect(tree_position.x >= 0, "could not find deterministic apple tree coordinate")
	var column := Vector2i(tree_position.x, tree_position.z)
	world.height_map_dict[column] = tree_position.y - 1
	world.type_map_dict[column] = BlockId.Type.GRASS
	var blocks: Dictionary = {}
	for y in range(tree_position.y, tree_position.y + 4):
		blocks[Vector3i(tree_position.x, y, tree_position.z)] = BlockId.Type.LOG
	for x_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			blocks[Vector3i(tree_position.x + x_offset, tree_position.y + 5, tree_position.z + z_offset)] = BlockId.Type.LEAVES
	world.tree_chunks_fast[Vector2i.ZERO] = blocks
	world.tree_block_fast.merge(blocks)

func _count_apple_trees(coordinator: AppleTreeCoordinator, sample_count: int) -> int:
	var count := 0
	for index in range(sample_count):
		if coordinator._is_apple_tree(Vector3i(index % 100, 6, index / 100)):
			count += 1
	return count

func _find_item_slot(inventory: InventoryModel, item_id: StringName) -> int:
	for index in range(inventory.slots.size()):
		var stack := inventory.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		print("[apple_trees] %s" % message)
