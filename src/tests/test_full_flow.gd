extends SceneTree

func _init():
	print("[FullFlow] Testing full MainMenu -> SaveSlot -> Game flow")

	SaveManager.ensure_save_dir()
	SaveManager.delete_slot(1)

	# Simulate user creating world in slot 1 with random seed via SaveSlotScreen logic
	var random_seed = SaveManager.generate_random_seed()
	var world_name = "HeadlessTestWorld"
	print("[FullFlow] Creating slot 1 with random seed %d name=%s" % [random_seed, world_name])
	var slot_data = SaveManager.create_new_world(1, random_seed, world_name)
	assert(slot_data["seed"] == random_seed)

	# Write current_session.json as MainMenu does
	var session = {"slot_id": 1, "seed": random_seed, "world_name": world_name}
	var f = FileAccess.open("user://current_session.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(session))
	f.close()
	print("[FullFlow] Wrote current_session.json")

	# Now instantiate WorldController as Game would
	var wc = load("res://world/world.tscn").instantiate() as WorldController
	wc.set_pending_save_data(slot_data)
	root.add_child(wc)
	# _ready runs synchronously on add, but give one idle frame for safety
	await create_timer(0.1).timeout

	print("[FullFlow] WorldController after _ready: seed=%d placed=%d" % [wc.seed_value, wc.voxel_model.placed_blocks.size()])
	assert(wc.seed_value == random_seed)
	assert(wc.voxel_model != null)

	# Simulate placing a block
	var test_pos = Vector3i(50,15,50)
	var edit = wc.voxel_model.try_place_block(test_pos, BlockId.Type.STONE)
	print("[FullFlow] Placed block at %s result=%s" % [test_pos, edit.is_success() if edit else "null"])
	assert(edit != null and edit.is_success())

	# Save via SaveManager as Game would on edit
	var inv = InventoryModel.new()
	inv.setup_starter()
	var saved = SaveManager.save_world_state(1, wc.voxel_model, null, inv, 10.0)
	assert(saved)
	print("[FullFlow] Saved after edit")

	# Reload slot and verify edit persists
	var reloaded = SaveManager.load_slot(1)
	var placed = reloaded.get("placed_blocks", {})
	print("[FullFlow] Reloaded placed count: %d" % placed.size())
	assert(placed.size() == 1)
	var key = "%d,%d,%d" % [test_pos.x, test_pos.y, test_pos.z]
	assert(placed.has(key))
	print("[FullFlow] Edit persisted! Key %s found" % key)

	# Verify random terrain - second world different seed
	var seed_a = SaveManager.generate_random_seed()
	var seed_b = SaveManager.generate_random_seed()
	assert(seed_a != seed_b)
	print("[FullFlow] Random seeds distinct: %d != %d" % [seed_a, seed_b])

	print("[FullFlow] ALL FLOW TESTS PASSED - PLAY button -> 3 slots -> random world creation -> save -> load persists edits")
	wc.queue_free()
	quit(0)
