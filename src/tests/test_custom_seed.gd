extends SceneTree

func _init():
	print("[TestCustomSeed] Testing editable seed text box - custom seed input")

	SaveManager.ensure_save_dir()
	SaveManager.delete_slot(0)

	# Test parsing logic from save_slot_screen
	var screen_scene = load("res://ui/main_menu/save_slot_screen.tscn") as PackedScene
	var screen = screen_scene.instantiate() as SaveSlotScreen
	root.add_child(screen)
	await create_timer(0.3).timeout

	# Simulate user typing custom seed 999999
	screen._pending_creation_slot = 0
	screen._pending_creation_seed = 12345
	if screen.dialog_name_edit:
		screen.dialog_name_edit.text = "CustomSeedWorld"
	if screen.dialog_seed_edit:
		screen.dialog_seed_edit.text = "999999"
		print("[TestCustomSeed] Set SeedEdit to 999999")

	var parsed = screen._parse_seed_input()
	print("[TestCustomSeed] Parsed seed %d expected 999999" % parsed)
	assert(parsed == 999999)

	# Test empty -> random
	screen.dialog_seed_edit.text = ""
	var parsed_random = screen._parse_seed_input()
	print("[TestCustomSeed] Empty input parsed to random %d" % parsed_random)
	assert(parsed_random != 0 and parsed_random != 999999)

	# Test string seed -> hashed
	screen.dialog_seed_edit.text = "MyCustomWorld"
	var parsed_hash = screen._parse_seed_input()
	print("[TestCustomSeed] String 'MyCustomWorld' hashed to %d" % parsed_hash)
	assert(parsed_hash != 0)

	# Create world with custom seed via SaveManager
	var data = SaveManager.create_new_world(0, parsed, "CustomSeedWorld")
	assert(data["seed"] == 999999)
	print("[TestCustomSeed] Created world with custom seed 999999 OK")

	# Verify world generation uses custom seed
	var wc = load("res://world/world.tscn").instantiate() as WorldController
	wc.set_pending_save_data(data)
	root.add_child(wc)
	await create_timer(0.2).timeout
	print("[TestCustomSeed] WorldController seed=%d expected 999999" % wc.seed_value)
	assert(wc.seed_value == 999999)

	print("[TestCustomSeed] PASS - Seed editable text box works, custom worlds can be whatever seed user wants")
	quit(0)
