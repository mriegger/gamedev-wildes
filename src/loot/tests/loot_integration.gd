extends SceneTree

var _errors: Array[String] = []
var _position_is_ready: bool = true

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var entity_catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var drop_scene := load("res://loot/presentation/loot_drop_view.tscn") as PackedScene
	var pickup_audio_scene := load("res://loot/presentation/world_loot_pickup_audio.tscn") as PackedScene
	var player_scene := load("res://player/player.tscn") as PackedScene
	var stats_definition := load("res://player/player_stats.tres") as PlayerStatsDefinition
	_expect(block_catalog != null and block_catalog.validate(), "block catalog invalid")
	_expect(item_catalog != null and item_catalog.validate(block_catalog), "item catalog invalid")
	_expect(entity_catalog != null and entity_catalog.validate(), "entity catalog invalid")
	_expect(drop_scene != null and drop_scene.can_instantiate(), "loot drop view did not load")
	_expect(pickup_audio_scene != null and pickup_audio_scene.can_instantiate(), "loot pickup audio did not load")
	_expect(player_scene != null and player_scene.can_instantiate(), "player scene did not load")
	_expect(stats_definition != null and stats_definition.validate(), "player stats definition invalid")
	_test_variant_stats(item_catalog, stats_definition)
	_test_partial_inventory_preparation(item_catalog)
	await _test_lootless_skeleton_lifecycle(
		block_catalog,
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
	)
	await _test_bird_feather_drops(entity_catalog, item_catalog, drop_scene, pickup_audio_scene, player_scene)
	await _test_partial_pickup_streaming_and_lifetime(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
	)
	await _test_equipment_exact_pickup(entity_catalog, item_catalog, drop_scene, player_scene)
	await _test_reentrant_defeat_queue(entity_catalog, item_catalog, drop_scene, player_scene)
	await _test_suspended_defeat_queue(entity_catalog, item_catalog, drop_scene, player_scene)
	await _test_full_capacity_batch_evicts_atomically(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
	)
	_finish()

func _test_variant_stats(item_catalog: ItemCatalog, stats_definition: PlayerStatsDefinition) -> void:
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_empty()
	var backpack_start := InventoryModel.HOTBAR_SIZE
	var helmet_index := InventoryModel.get_equipment_index(ArmorDefinition.Slot.HEAD)
	var factory := inventory.equipment_instance_factory
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"copper_sword", 1, factory.create(&"copper_sword", _affixes([item_catalog.get_equipment_affix(&"vicious")]))))
	InventoryTestFixture.restore_slot(inventory, 1, InventoryStack.new(&"copper_sword", 1, factory.create(&"copper_sword")))
	InventoryTestFixture.restore_slot(inventory, backpack_start, InventoryStack.new(&"copper_helmet", 1, factory.create(&"copper_helmet")))
	InventoryTestFixture.restore_slot(inventory, helmet_index, InventoryStack.new(&"copper_helmet", 1, factory.create(&"copper_helmet", _affixes([item_catalog.get_equipment_affix(&"stout")]))))
	var stats := ActorStats.new(stats_definition)
	var coordinator := InventoryLoadoutCoordinator.new()
	_expect(coordinator.setup(inventory, stats, ItemProficiency.new(item_catalog)), "variant stat coordinator setup failed")
	var base_strength := stats.get_base_value(&"strength")
	var base_defense := stats.get_base_value(&"defense")
	_expect(is_equal_approx(stats.get_value(&"strength"), base_strength + 2.0), "selected vicious sword did not add strength")
	_expect(is_equal_approx(stats.get_value(&"defense"), base_defense + 3.0), "equipped stout helmet did not add base and variant defense")
	_expect(coordinator.handle_drop(1, 0, 1), "plain sword did not swap with the selected vicious sword")
	_expect(inventory.get_slot(1).equipment_instance.affixes[0].affix_id == &"vicious", "same-base swap lost the vicious sword instance")
	_expect(is_equal_approx(stats.get_value(&"strength"), base_strength), "plain selected sword gained variant strength")
	_expect(coordinator.handle_drop(1, 0, 1), "vicious sword did not swap back into the selected slot")
	_expect(is_equal_approx(stats.get_value(&"strength"), base_strength + 2.0), "returned vicious sword did not restore strength")
	_expect(coordinator.try_unequip_armor(helmet_index), "stout helmet did not unequip")
	_expect(is_equal_approx(stats.get_value(&"defense"), base_defense), "unequipped stout helmet retained defense")
	_expect(coordinator.try_equip_armor(backpack_start), "plain helmet did not equip")
	_expect(is_equal_approx(stats.get_value(&"defense"), base_defense + 1.0), "plain helmet retained stout defense")

func _test_partial_inventory_preparation(item_catalog: ItemCatalog) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory, InventoryModel.HOTBAR_SIZE)
	inventory.setup_empty()
	var dirt_max := item_catalog.get_definition(&"dirt_block").max_stack
	var sand_max := item_catalog.get_definition(&"sand_block").max_stack
	for index in range(inventory.get_size()):
		InventoryTestFixture.restore_slot(inventory, index, InventoryStack.new(&"dirt_block", dirt_max))
	InventoryTestFixture.restore_slot(inventory, 0, InventoryStack.new(&"sand_block", sand_max - 2))
	var before := inventory.to_dict()
	_expect(inventory.prepare_add_stack(InventoryStack.new(&"sand_block", 5)) == null, "exact material add accepted partial capacity")
	_expect(inventory.to_dict() == before, "rejected exact material preparation changed inventory")
	var partial := inventory.prepare_add_stack_up_to(InventoryStack.new(&"sand_block", 5))
	_expect(partial != null, "partial material add did not prepare")
	if partial != null:
		var accepted := partial.get_result_stack()
		_expect(accepted != null and accepted.item_id == &"sand_block" and accepted.count == 2, "partial material add reported the wrong accepted stack")
		accepted.count = 99
		_expect(partial.get_result_stack().count == 2, "partial material result exposed prepared state")
		_expect(inventory.can_commit_prepared_change(partial), "partial material preparation was not committable")
		inventory._commit_prepared_change(partial)
		_expect(inventory.get_inventory_item_count(&"sand_block") == sand_max, "partial material commit added the wrong count")
	var sword := factory.create(&"copper_sword")
	_expect(sword != null, "partial equipment fixture allocation failed")
	_expect(inventory.prepare_add_stack_up_to(InventoryStack.new(&"copper_sword", 1, sword)) == null, "equipment add accepted partial capacity")

func _test_lootless_skeleton_lifecycle(
	block_catalog: BlockCatalog,
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	var skeleton := entity_catalog.get_definition(&"skeleton")
	_expect(skeleton.loot_pool == null, "Skeleton unexpectedly has a loot pool")
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var state := WorldLootState.new(item_catalog, factory)
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var player := player_scene.instantiate() as PlayerMotor
	var entity_coordinator := WorldEntityCoordinator.new()
	var loot_coordinator := OverworldLootCoordinator.new()
	root.add_child(player)
	root.add_child(entity_coordinator)
	root.add_child(loot_coordinator)
	player.global_position = Vector3(0.5, 2.0, 0.5)
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-2, ceili(WorldEntityCoordinator.DESPAWN_DISTANCE) + 4):
		for z in range(-2, 3):
			world.height_map_dict[Vector2i(x, z)] = 1
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.STONE
	entity_coordinator.setup(entity_catalog, world, 9901, _always_ready)
	var runtime := entity_coordinator.get_runtime()
	loot_coordinator.setup(
		entity_catalog,
		item_catalog,
		factory,
		state,
		inventory,
		loadout,
		player,
		runtime,
		world,
		_always_ready,
		drop_scene,
	)
	var defeat_count := [0]
	var state_change_count := [0]
	runtime.entity_defeated.connect(func(_defeat: EntityDefeat) -> void: defeat_count[0] += 1)
	loot_coordinator.state_changed.connect(func() -> void: state_change_count[0] += 1)
	var initial_entry_count := state.get_entry_count()
	var initial_instance_id := factory.get_next_instance_id()
	var ordinary_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"skeleton", Vector3(0.5, 2.0, 0.5), 7001),
	])
	_expect(ordinary_ids.size() == 1 and runtime.try_despawn(ordinary_ids[0]), "ordinary Skeleton despawn failed")
	_expect(defeat_count[0] == 0, "ordinary Skeleton despawn emitted a defeat")
	_expect(state.get_entry_count() == initial_entry_count, "ordinary Skeleton despawn changed world loot")
	_expect(factory.get_next_instance_id() == initial_instance_id, "ordinary Skeleton despawn allocated equipment")
	_expect(loot_coordinator.get_child_count() == 0 and state_change_count[0] == 0, "ordinary Skeleton despawn presented or announced loot")
	var lethal_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"skeleton", Vector3(2.5, 2.0, 0.5), 7002),
	])
	var lethal_result: EntityDamageResult
	if lethal_ids.size() == 1:
		lethal_result = runtime.try_apply_damage(lethal_ids[0], 1000.0)
	_expect(lethal_result != null and lethal_result.defeated, "lethal Skeleton fixture did not die")
	_expect(defeat_count[0] == 1, "lethal Skeleton defeat did not emit exactly once")
	_expect(state.get_entry_count() == initial_entry_count, "lethal Skeleton defeat changed world loot")
	_expect(factory.get_next_instance_id() == initial_instance_id, "lethal Skeleton defeat allocated equipment")
	_expect(loot_coordinator.get_child_count() == 0 and state_change_count[0] == 0, "lethal Skeleton defeat presented or announced loot")
	var distant_position := Vector3(WorldEntityCoordinator.DESPAWN_DISTANCE + 2.5, 2.0, 0.5)
	var distant_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"skeleton", distant_position, 7003),
	])
	var observation := EntityTargetObservation.create(player.global_position, player.global_position, Vector3.FORWARD, Vector3.RIGHT)
	entity_coordinator.tick(0.0, observation, 20.0)
	_expect(distant_ids.size() == 1 and runtime.get_actor(distant_ids[0]) == null, "distant Skeleton did not despawn")
	_expect(defeat_count[0] == 1, "distant Skeleton despawn emitted a defeat")
	_expect(state.get_entry_count() == initial_entry_count, "distant Skeleton despawn changed world loot")
	_expect(factory.get_next_instance_id() == initial_instance_id, "distant Skeleton despawn allocated equipment")
	_expect(loot_coordinator.get_child_count() == 0 and state_change_count[0] == 0, "distant Skeleton despawn presented or announced loot")
	var zombie := entity_catalog.get_definition(&"zombie")
	var zombie_seed := _find_single_drop_seed(zombie.loot_pool, item_catalog)
	_expect(zombie_seed >= 0, "suspended defeat fixture found no dropping zombie seed")
	var suspended_ids := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"zombie", Vector3(4.5, 2.0, 0.5), zombie_seed),
	])
	_expect(suspended_ids.size() == 1, "suspended defeat zombie did not spawn")
	var entry_count_before_suspend := state.get_entry_count()
	var allocator_before_suspend := factory.get_next_instance_id()
	loot_coordinator.suspend()
	var suspended_result: EntityDamageResult
	if suspended_ids.size() == 1:
		suspended_result = runtime.try_apply_damage(suspended_ids[0], 1000.0)
	_expect(suspended_result != null and suspended_result.defeated, "loot-suspended runtime did not accept direct lethal damage")
	_expect(defeat_count[0] == 2, "suspended lethal damage did not emit its entity defeat")
	_expect(state.get_entry_count() == entry_count_before_suspend, "suspended entity defeat changed world loot")
	_expect(factory.get_next_instance_id() == allocator_before_suspend, "suspended entity defeat allocated equipment")
	_expect(state_change_count[0] == 0, "suspended entity defeat announced world loot")
	loot_coordinator.shutdown()
	entity_coordinator.shutdown()
	loot_coordinator.queue_free()
	entity_coordinator.queue_free()
	player.queue_free()
	await process_frame
	await process_frame

func _test_bird_feather_drops(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	pickup_audio_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var state := WorldLootState.new(item_catalog, factory)
	var fixture := _create_runtime_fixture(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
		inventory,
		state,
		Vector3(1000.0, 0.0, 1000.0),
	)
	var entity_runtime := fixture["entity_runtime"] as EntityRuntime
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	var pickup_audio := pickup_audio_scene.instantiate() as WorldLootPickupAudio
	root.add_child(pickup_audio)
	pickup_audio.setup(coordinator)
	var pickup_player := pickup_audio.get_node("Player") as AudioStreamPlayer
	var pickup_events: Array[Dictionary] = []
	coordinator.pickup_committed.connect(func(item_id: StringName, count: int) -> void:
		pickup_events.append({"item_id": item_id, "count": count})
	)
	var expected_item_ids: Array[StringName] = [&"black_feather", &"red_feather", &"blue_feather"]
	var variants: Array[int] = [BirdColorVariant.Type.CROW, BirdColorVariant.Type.REDBIRD, BirdColorVariant.Type.BLUEBIRD]
	for item_id in expected_item_ids:
		var item_definition := item_catalog.get_definition(item_id)
		_expect(item_definition.world_model != null and item_definition.world_material != null, "%s has incomplete world presentation" % item_id)
		_expect(is_equal_approx(item_definition.world_presentation_scale, 1.125), "%s world model scale changed" % item_id)
		_expect(is_equal_approx(item_catalog.get_definition(item_id).world_pickup_radius_multiplier, 2.0), "%s pickup radius multiplier is not doubled" % item_id)
	for index in variants.size():
		var seed := BirdColorVariant.behavior_seed_for_common_variant(variants[index], 8000 + index * 100)
		entity_runtime.entity_defeated.emit(EntityDefeat.new(index + 1, &"bird", Vector3(float(index) * 4.0, 10.0, 0.0), seed))
	var entries := state.get_entries()
	_expect(entries.size() == 3, "three feather-dropping birds did not create three world loot entries")
	var dropped_item_ids: Array[StringName] = []
	for entry in entries:
		dropped_item_ids.append(entry.stack.item_id)
		_expect(is_equal_approx(entry.world_position.y, 2.0), "airborne feather was not stored at terrain height")
	dropped_item_ids.sort()
	expected_item_ids.sort()
	_expect(dropped_item_ids == expected_item_ids, "bird color variants dropped the wrong feather items")
	_expect(coordinator.get_child_count() == 3, "feather drops did not create three world views")
	for child in coordinator.get_children():
		var icon_sprite := child.get_node("Icon") as Sprite3D
		var model := child.get_node("Model") as MeshInstance3D
		var hover_box := child.get_node("HoverBox") as Node3D
		var pickup_area := child.get_node("PickupArea") as Area3D
		_expect(not icon_sprite.visible and model.visible and model.mesh != null, "feather world view did not use its 3D model")
		_expect(model.scale.is_equal_approx(Vector3.ONE * 1.125), "feather world model used the wrong scale")
		pickup_area.mouse_entered.emit()
		_expect(hover_box.visible, "feather hover did not show its selection box")
		pickup_area.mouse_exited.emit()
		_expect(not hover_box.visible, "feather hover selection box did not clear")
		_expect((child as LootDropView).is_falling(), "airborne feather view did not begin falling")
	await create_timer(1.1).timeout
	for child in coordinator.get_children():
		_expect(not (child as LootDropView).is_falling(), "airborne feather view did not finish falling")
		_expect(is_equal_approx((child as LootDropView).global_position.y, 2.0), "airborne feather view did not land at terrain height")
	var player := fixture["player"] as PlayerMotor
	var black_feather_entry: WorldLootEntry
	for entry in state.get_entries():
		if entry.stack.item_id == &"black_feather":
			black_feather_entry = entry
			break
	_expect(black_feather_entry != null, "black feather pickup fixture was missing")
	if black_feather_entry != null:
		var black_feather_view: LootDropView
		for child in coordinator.get_children():
			if (child as LootDropView).global_position.is_equal_approx(black_feather_entry.world_position):
				black_feather_view = child as LootDropView
				break
		_expect(black_feather_view != null, "black feather pickup view was missing")
		if black_feather_view != null:
			(black_feather_view.get_node("PickupArea") as Area3D).mouse_entered.emit()
			_expect(coordinator.handle_hovered_pickup(6.0), "highlighted distant feather did not consume interaction")
			_expect(state.has_entry(black_feather_entry.entry_id), "distant highlighted feather was collected outside player reach")
			_expect(pickup_events.is_empty() and pickup_player.stream == null, "failed feather pickup played feedback")
			player.global_position = black_feather_entry.world_position + Vector3(0.0, 0.0, 2.5)
			coordinator.tick()
		_expect(inventory.get_inventory_item_count(&"black_feather") == 1, "nearby black feather was not collected automatically")
		_expect(not state.has_entry(black_feather_entry.entry_id), "collected black feather remained in world loot")
		_expect(pickup_events == [{"item_id": &"black_feather", "count": 1}], "successful feather pickup emitted the wrong feedback event")
		_expect(pickup_player.stream != null and pickup_player.stream.resource_path.ends_with("click-b.ogg"), "successful feather pickup did not play the configured sound")
	var count_before_lootless_birds := state.get_entry_count()
	var duck_seed := BirdColorVariant.behavior_seed_for_common_variant(BirdColorVariant.Type.DUCK, 9000)
	entity_runtime.entity_defeated.emit(EntityDefeat.new(4, &"bird", Vector3(16.0, 2.0, 0.0), duck_seed))
	entity_runtime.entity_defeated.emit(EntityDefeat.new(5, &"owl", Vector3(20.0, 2.0, 0.0), 9001))
	_expect(state.get_entry_count() == count_before_lootless_birds, "duck or owl unexpectedly created feather loot")
	pickup_audio.queue_free()
	await _cleanup_runtime_fixture(fixture)

func _test_partial_pickup_streaming_and_lifetime(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	var root_child_baseline := root.get_child_count()
	var orphan_baseline := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var dirt_max := item_catalog.get_definition(&"dirt_block").max_stack
	var sand_max := item_catalog.get_definition(&"sand_block").max_stack
	var copper_max := item_catalog.get_definition(&"copper").max_stack
	for index in range(InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(inventory, index, InventoryStack.new(&"dirt_block", dirt_max))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE, InventoryStack.new(&"sand_block", sand_max - 2))
	InventoryTestFixture.restore_slot(inventory, InventoryModel.HOTBAR_SIZE + 1, InventoryStack.new(&"copper", copper_max - 1))
	var state := WorldLootState.new(item_catalog, factory)
	var drop_position := Vector3(2.5, 4.0, -3.5)
	_expect(_add_world_stack(state, InventoryStack.new(&"sand_block", 5), drop_position), "partial pickup world fixture failed")
	_expect(_add_world_stack(state, InventoryStack.new(&"copper", 1), drop_position), "reentrant pickup world fixture failed")
	_expect(_advance_world_time(state, 25.0), "partial pickup lifetime fixture failed")
	_position_is_ready = true
	var fixture := _create_runtime_fixture(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
		inventory,
		state,
		drop_position,
	)
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	var entity_runtime := fixture["entity_runtime"] as EntityRuntime
	_expect(state.get_entry_count() == 2, "persistent materials were not active after setup")
	_expect(coordinator.get_child_count() == 2, "ready persistent materials did not create views")
	var state_observations: Array[Dictionary] = []
	var inventory_observations: Array[Dictionary] = []
	var notification_order: Array[String] = []
	var reentrant_copper_presence: Array[bool] = []
	var state_observer := func() -> void:
		notification_order.append("state")
		state_observations.append({
			"sand_inventory": inventory.get_inventory_item_count(&"sand_block"),
			"copper_inventory": inventory.get_inventory_item_count(&"copper"),
			"sand_world": 0 if state.get_entry(1) == null else state.get_entry(1).stack.count,
			"copper_world": 0 if state.get_entry(2) == null else state.get_entry(2).stack.count,
		})
		coordinator.tick()
		reentrant_copper_presence.append(state.has_entry(2))
	var inventory_observer := func() -> void:
		notification_order.append("inventory")
		inventory_observations.append({
			"sand_inventory": inventory.get_inventory_item_count(&"sand_block"),
			"copper_inventory": inventory.get_inventory_item_count(&"copper"),
			"sand_world": 0 if state.get_entry(1) == null else state.get_entry(1).stack.count,
			"copper_world": 0 if state.get_entry(2) == null else state.get_entry(2).stack.count,
		})
	coordinator.state_changed.connect(state_observer)
	inventory.inventory_changed.connect(inventory_observer)
	coordinator.tick()
	var remaining := state.get_entry(1)
	_expect(remaining != null and remaining.stack.count == 3, "partial material pickup removed the wrong count")
	_expect(not state.has_entry(2), "reentrant pickup left the second collectible material")
	_expect(remaining != null and is_equal_approx(remaining.remaining_lifetime, 275.0), "partial material pickup refreshed lifetime")
	_expect(inventory.get_inventory_item_count(&"sand_block") == sand_max, "partial material pickup did not fill available capacity")
	_expect(inventory.get_inventory_item_count(&"copper") == copper_max, "second material pickup did not fill available capacity")
	_expect(not reentrant_copper_presence.is_empty() and reentrant_copper_presence[0], "nested pickup collected the second entry before the first transaction notified")
	_expect(notification_order == ["state", "inventory", "state", "inventory"], "reentrant pickup notifications completed out of transaction order")
	_expect(state_observations.size() == 2 and inventory_observations.size() == 2, "reentrant pickup emitted the wrong notification count")
	if state_observations.size() == 2 and inventory_observations.size() == 2:
		_expect(state_observations[0] == {
			"sand_inventory": sand_max,
			"copper_inventory": copper_max - 1,
			"sand_world": 3,
			"copper_world": 1,
		}, "first world observer saw a partially committed pickup")
		_expect(inventory_observations[0] == state_observations[0], "first inventory observer saw a partially committed pickup")
		_expect(state_observations[1] == {
			"sand_inventory": sand_max,
			"copper_inventory": copper_max,
			"sand_world": 3,
			"copper_world": 0,
		}, "second world observer saw a partially committed pickup")
		_expect(inventory_observations[1] == state_observations[1], "second inventory observer saw a partially committed pickup")
	coordinator.tick()
	_expect(state_observations.size() == 2 and inventory_observations.size() == 2, "double pickup changed committed state")
	_position_is_ready = false
	coordinator.tick()
	_expect(state.has_entry(1), "streaming unload removed persistent material")
	_expect(coordinator.get_child_count() == 0, "streaming unload retained a loot view")
	_position_is_ready = true
	coordinator.tick()
	_expect(coordinator.get_child_count() == 1, "streaming readiness did not recreate a loot view")
	coordinator.suspend()
	var suspended_lifetime := state.get_entry(1).remaining_lifetime
	coordinator.tick(10.0)
	_expect(is_equal_approx(state.get_entry(1).remaining_lifetime, suspended_lifetime), "suspended coordinator advanced material lifetime")
	_expect(coordinator.get_child_count() == 0, "suspended coordinator retained loot views")
	coordinator.resume()
	_expect(coordinator.get_child_count() == 1, "resume did not recreate ready loot views")
	coordinator.tick(0.5)
	coordinator.tick(0.5)
	_expect(is_equal_approx(state.get_entry(1).remaining_lifetime, 274.0), "coarse lifetime step did not advance at one second")
	_expect(state_observations.size() == 2, "non-expiring lifetime step emitted state changed")
	coordinator.tick(274.0)
	_expect(not state.has_entry(1), "expired material remained in persistent state")
	_expect(coordinator.get_child_count() == 0, "expired material retained a loot view")
	_expect(state_observations.size() == 3, "material expiration did not emit one state change")
	var zombie := entity_catalog.get_definition(&"zombie")
	var seed := _find_single_drop_seed(zombie.loot_pool, item_catalog)
	_expect(seed >= 0, "no deterministic single-drop zombie seed found")
	if seed >= 0:
		entity_runtime.entity_defeated.emit(EntityDefeat.new(1, &"zombie", drop_position, seed))
		_expect(state.get_entry_count() == 1, "zombie defeat did not commit persistent loot")
		_expect(state_observations.size() == 4, "zombie loot spawn did not emit state changed")
	var state_before_shutdown := state.snapshot()
	var allocator_before_shutdown := factory.get_next_instance_id()
	coordinator.shutdown()
	_expect(state.snapshot() == state_before_shutdown, "shutdown cleared persistent loot state")
	_expect(factory.get_next_instance_id() == allocator_before_shutdown, "shutdown reset equipment instance IDs")
	_expect(coordinator.get_child_count() == 0, "shutdown retained loot views")
	if seed >= 0:
		entity_runtime.entity_defeated.emit(EntityDefeat.new(2, &"zombie", drop_position, seed))
		_expect(state.snapshot() == state_before_shutdown, "shutdown coordinator remained connected to entity defeats")
	coordinator.state_changed.disconnect(state_observer)
	inventory.inventory_changed.disconnect(inventory_observer)
	await _cleanup_runtime_fixture(fixture)
	_expect(root.get_child_count() == root_child_baseline, "partial loot integration retained root children")
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == orphan_baseline, "partial loot cleanup changed orphan count from %d to %d" % [orphan_baseline, orphan_count])
	_position_is_ready = true

func _test_equipment_exact_pickup(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	_position_is_ready = true
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var dirt_max := item_catalog.get_definition(&"dirt_block").max_stack
	for index in range(InventoryModel.FILLABLE_SIZE):
		InventoryTestFixture.restore_slot(inventory, index, InventoryStack.new(&"dirt_block", dirt_max))
	var sword := factory.create(&"copper_sword")
	_expect(sword != null, "equipment pickup fixture allocation failed")
	var state := WorldLootState.new(item_catalog, factory)
	var drop_position := Vector3(-4.0, 2.0, 3.0)
	_expect(_add_world_stack(state, InventoryStack.new(&"copper_sword", 1, sword), drop_position), "equipment pickup world fixture failed")
	var fixture := _create_runtime_fixture(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
		inventory,
		state,
		drop_position,
	)
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	var loadout := fixture["loadout"] as InventoryLoadoutCoordinator
	coordinator.tick()
	_expect(state.has_entry(1), "full inventory partially collected equipment")
	_expect(_find_equipment_instance(inventory, sword.instance_id) == -1, "full inventory duplicated equipment")
	_expect(loadout.discard_stack(InventoryModel.HOTBAR_SIZE, dirt_max), "equipment pickup capacity did not open")
	var state_observations: Array[Dictionary] = []
	var inventory_observations: Array[Dictionary] = []
	var state_observer := func() -> void:
		state_observations.append({
			"world_has_entry": state.has_entry(1),
			"inventory_index": _find_equipment_instance(inventory, sword.instance_id),
		})
	var inventory_observer := func() -> void:
		inventory_observations.append({
			"world_has_entry": state.has_entry(1),
			"inventory_index": _find_equipment_instance(inventory, sword.instance_id),
		})
	coordinator.state_changed.connect(state_observer)
	inventory.inventory_changed.connect(inventory_observer)
	coordinator.tick()
	var inventory_index := _find_equipment_instance(inventory, sword.instance_id)
	_expect(not state.has_entry(1), "equipment exact pickup retained its world entry")
	_expect(inventory_index >= 0, "equipment exact pickup lost instance identity")
	_expect(state_observations == [{"world_has_entry": false, "inventory_index": inventory_index}], "world observer saw a partial equipment pickup")
	_expect(inventory_observations == [{"world_has_entry": false, "inventory_index": inventory_index}], "inventory observer saw a partial equipment pickup")
	coordinator.tick()
	_expect(_find_equipment_instance(inventory, sword.instance_id) == inventory_index, "double equipment pickup duplicated its instance")
	coordinator.state_changed.disconnect(state_observer)
	inventory.inventory_changed.disconnect(inventory_observer)
	await _cleanup_runtime_fixture(fixture)

func _test_full_capacity_batch_evicts_atomically(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var encoded_entries: Array = []
	for index in range(WorldLootState.MAXIMUM_ENTRY_COUNT):
		var sword := factory.create(&"copper_sword")
		_expect(sword != null, "bounded equipment fixture allocation %d failed" % index)
		if sword != null:
			encoded_entries.append(WorldLootEntry.new(
				index + 1,
				InventoryStack.new(&"copper_sword", 1, sword),
				Vector3(float(index) * 2.0, 0.0, 0.0),
				WorldLootEntry.NO_LIFETIME,
			).to_dict())
	var state := WorldLootState.new(item_catalog, factory)
	_expect(state.restore({
		"next_entry_id": WorldLootState.MAXIMUM_ENTRY_COUNT + 1,
		"entries": encoded_entries,
	}), "bounded equipment world fixture did not restore")
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	_position_is_ready = false
	var drop_position := Vector3(500.0, 0.0, 0.0)
	var fixture := _create_runtime_fixture(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
		inventory,
		state,
		drop_position,
	)
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	var entity_runtime := fixture["entity_runtime"] as EntityRuntime
	var zombie := entity_catalog.get_definition(&"zombie")
	var seed := _find_equipment_drop_seed(zombie.loot_pool, item_catalog)
	_expect(seed >= 0, "no deterministic equipment-drop zombie seed found")
	var before_state := state.snapshot()
	var before_allocator := factory.get_next_instance_id()
	var expected_factory := EquipmentInstanceFactory.new(item_catalog, before_allocator)
	var expected_resolution := LootResolver.prepare(zombie.loot_pool, seed, expected_factory)
	var expected_drop_count := 0 if expected_resolution == null else expected_resolution.get_drops().size()
	var state_change_count := [0]
	coordinator.state_changed.connect(func() -> void: state_change_count[0] += 1)
	if seed >= 0:
		entity_runtime.entity_defeated.emit(EntityDefeat.new(1, &"zombie", drop_position, seed))
	_expect(state.snapshot() != before_state, "full-cap loot batch was silently rejected")
	_expect(state.get_entry_count() == WorldLootState.MAXIMUM_ENTRY_COUNT, "full-cap loot batch exceeded the state bound")
	_expect(factory.get_next_instance_id() == before_allocator + 1, "full-cap loot batch did not advance its equipment ID atomically")
	_expect(state.get_equipment_instance_ids().has(before_allocator), "full-cap loot batch lost its new equipment instance")
	_expect(state_change_count[0] == 1, "full-cap loot batch did not emit one state change")
	_expect(expected_drop_count >= 1, "full-cap fixture resolved no drops")
	for evicted_index in range(expected_drop_count):
		_expect(not state.has_entry(evicted_index + 1), "full-cap loot batch did not evict the oldest required entry")
	_expect(coordinator.get_child_count() == 0, "unready bounded loot created views")
	var committed_state := state.snapshot()
	var committed_allocator := factory.get_next_instance_id()
	coordinator.shutdown()
	_expect(state.snapshot() == committed_state, "bounded-state shutdown changed persistent loot")
	_expect(factory.get_next_instance_id() == committed_allocator, "bounded-state shutdown reset equipment IDs")
	await _cleanup_runtime_fixture(fixture)
	_position_is_ready = true

func _test_reentrant_defeat_queue(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	_position_is_ready = true
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var state := WorldLootState.new(item_catalog, factory)
	var fixture := _create_runtime_fixture(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
		inventory,
		state,
		Vector3(100.0, 0.0, 100.0),
	)
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	var entity_runtime := fixture["entity_runtime"] as EntityRuntime
	var zombie := entity_catalog.get_definition(&"zombie")
	var seed := _find_equipment_drop_seed(zombie.loot_pool, item_catalog)
	_expect(seed >= 0, "no deterministic equipment seed found for reentrant defeat")
	var notification_count := [0]
	var nested_emitted := [false]
	var observer := func() -> void:
		notification_count[0] += 1
		if nested_emitted[0]:
			return
		nested_emitted[0] = true
		entity_runtime.entity_defeated.emit(EntityDefeat.new(
			2,
			&"zombie",
			Vector3(12.0, 0.0, 0.0),
			seed,
		))
	coordinator.state_changed.connect(observer)
	var expected_first_instance_id := factory.get_next_instance_id()
	if seed >= 0:
		entity_runtime.entity_defeated.emit(EntityDefeat.new(
			1,
			&"zombie",
			Vector3.ZERO,
			seed,
		))
	var equipment_instance_ids := state.get_equipment_instance_ids()
	_expect(notification_count[0] == 2, "reentrant defeat did not complete both state notifications")
	_expect(equipment_instance_ids == [expected_first_instance_id, expected_first_instance_id + 1], "reentrant defeat lost or duplicated equipment identity")
	_expect(factory.get_next_instance_id() == expected_first_instance_id + 2, "reentrant defeat advanced the allocator incorrectly")
	coordinator.state_changed.disconnect(observer)
	await _cleanup_runtime_fixture(fixture)

func _test_suspended_defeat_queue(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
) -> void:
	var factory := EquipmentInstanceFactory.new(item_catalog)
	var inventory := InventoryModel.new(item_catalog, factory)
	inventory.setup_empty()
	var state := WorldLootState.new(item_catalog, factory)
	_expect(
		_add_world_stack(state, InventoryStack.new(&"copper", 1), Vector3.ZERO),
		"suspended queue pickup fixture add failed",
	)
	var fixture := _create_runtime_fixture(
		entity_catalog,
		item_catalog,
		drop_scene,
		player_scene,
		inventory,
		state,
		Vector3.ZERO,
	)
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	var entity_runtime := fixture["entity_runtime"] as EntityRuntime
	var zombie := entity_catalog.get_definition(&"zombie")
	var seed := _find_single_drop_seed(zombie.loot_pool, item_catalog)
	_expect(seed >= 0, "no deterministic drop seed found for suspended defeat")
	var notification_count := [0]
	var queued := [false]
	var observer := func() -> void:
		notification_count[0] += 1
		if queued[0]:
			return
		queued[0] = true
		entity_runtime.entity_defeated.emit(EntityDefeat.new(
			2,
			&"zombie",
			Vector3(12.0, 0.0, 0.0),
			seed,
		))
		coordinator.suspend()
	inventory.inventory_changed.connect(observer)
	coordinator.tick()
	_expect(notification_count[0] == 1 and queued[0], "pickup did not queue a defeat before suspension")
	_expect(state.get_entry_count() == 0, "suspension committed queued loot")
	var suspended_allocator := factory.get_next_instance_id()
	entity_runtime.entity_defeated.emit(EntityDefeat.new(
		3,
		&"zombie",
		Vector3(24.0, 0.0, 0.0),
		seed,
	))
	_expect(state.get_entry_count() == 0, "defeat emitted during suspension changed world loot")
	_expect(factory.get_next_instance_id() == suspended_allocator, "defeat emitted during suspension allocated equipment")
	coordinator.resume()
	_expect(state.get_entry_count() == 1, "resume lost queued loot")
	inventory.inventory_changed.disconnect(observer)
	await _cleanup_runtime_fixture(fixture)

func _create_runtime_fixture(
	entity_catalog: EntityCatalog,
	item_catalog: ItemCatalog,
	drop_scene: PackedScene,
	player_scene: PackedScene,
	inventory: InventoryModel,
	state: WorldLootState,
	player_position: Vector3,
) -> Dictionary:
	var loadout := InventoryTestFixture.create_loadout(inventory)
	var player := player_scene.instantiate() as PlayerMotor
	var entity_runtime := EntityRuntime.new()
	var coordinator := OverworldLootCoordinator.new()
	var voxel_world := VoxelWorld.new(16, 32, 5, 8.0, load("res://blocks/block_catalog.tres") as BlockCatalog)
	for x in range(-32, 33):
		voxel_world.height_map_dict[Vector2i(x, 0)] = 1
		voxel_world.type_map_dict[Vector2i(x, 0)] = BlockId.Type.GRASS
	root.add_child(player)
	root.add_child(entity_runtime)
	root.add_child(coordinator)
	player.global_position = player_position
	coordinator.setup(
		entity_catalog,
		item_catalog,
		inventory.equipment_instance_factory,
		state,
		inventory,
		loadout,
		player,
		entity_runtime,
		voxel_world,
		_position_ready,
		drop_scene,
	)
	return {
		"loadout": loadout,
		"player": player,
		"entity_runtime": entity_runtime,
		"coordinator": coordinator,
	}

func _cleanup_runtime_fixture(fixture: Dictionary) -> void:
	var coordinator := fixture["coordinator"] as OverworldLootCoordinator
	coordinator.shutdown()
	coordinator.queue_free()
	(fixture["entity_runtime"] as EntityRuntime).queue_free()
	(fixture["player"] as PlayerMotor).queue_free()
	await process_frame
	await process_frame

func _add_world_stack(state: WorldLootState, stack: InventoryStack, position: Vector3) -> bool:
	var prepared := state._prepare_add_stack(stack, position)
	if prepared == null:
		return false
	return state.commit_prepared_change(prepared)

func _advance_world_time(state: WorldLootState, delta: float) -> bool:
	var prepared := state.prepare_advance_time(delta)
	if prepared == null:
		return false
	return state.commit_prepared_change(prepared)

func _find_single_drop_seed(pool: LootPoolDefinition, item_catalog: ItemCatalog) -> int:
	for seed in range(1, 100000):
		if _resolve(pool, seed, EquipmentInstanceFactory.new(item_catalog)).size() == 1:
			return seed
	return -1

func _find_equipment_drop_seed(pool: LootPoolDefinition, item_catalog: ItemCatalog) -> int:
	for seed in range(1, 100000):
		for stack in _resolve(pool, seed, EquipmentInstanceFactory.new(item_catalog)):
			if stack.equipment_instance != null:
				return seed
	return -1

func _resolve(
	pool: LootPoolDefinition,
	seed: int,
	factory: EquipmentInstanceFactory,
) -> Array[InventoryStack]:
	var prepared := LootResolver.prepare(pool, seed, factory)
	if prepared == null or not LootResolver._commit(prepared, factory):
		return []
	return prepared.get_drops()

func _find_equipment_instance(inventory: InventoryModel, instance_id: int) -> int:
	for index in range(inventory.get_size()):
		var stack := inventory.get_slot(index)
		if stack != null and stack.equipment_instance != null and stack.equipment_instance.instance_id == instance_id:
			return index
	return -1

func _affixes(values: Array[EquipmentAffixDefinition]) -> Array[EquipmentAffixDefinition]:
	return values

func _position_ready(_position: Vector3) -> bool:
	return _position_is_ready

func _always_ready(_position: Vector3) -> bool:
	return true

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)

func _finish() -> void:
	if _errors.is_empty():
		print("LOOT_INTEGRATION PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)
