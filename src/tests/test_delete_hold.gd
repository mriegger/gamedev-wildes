extends SceneTree

func _init():
	print("[TestDeleteHold] Testing hold-to-delete 3s")

	SaveManager.ensure_save_dir()
	SaveManager.delete_slot(0)
	var data = SaveManager.create_new_world(0, 111111, "DeleteMe")
	print("[TestDeleteHold] Created slot 0")

	var slot_scene = load("res://ui/main_menu/save_slot_screen.tscn") as PackedScene
	var slot_screen = slot_scene.instantiate() as SaveSlotScreen
	root.add_child(slot_screen)
	await create_timer(0.5).timeout

	# Find delete hold screen
	var del_hold = slot_screen.get_node_or_null("DeleteHoldScreen") as DeleteHoldScreen
	if del_hold == null:
		print("[TestDeleteHold] FAIL - DeleteHoldScreen not found")
		quit(1)
		return
	print("[TestDeleteHold] DeleteHoldScreen found")

	# Simulate delete request
	slot_screen._on_slot_delete(0)
	await create_timer(0.2).timeout

	if not del_hold.visible:
		print("[TestDeleteHold] FAIL - DeleteHoldScreen not visible after delete request")
		quit(1)
		return
	print("[TestDeleteHold] DeleteHoldScreen visible for slot %d" % del_hold.slot_id)

	# Simulate holding button for 3 seconds
	del_hold._on_hold_down()
	var elapsed = 0.0
	while elapsed < 3.5:
		await create_timer(0.2).timeout
		elapsed += 0.2
		if not is_instance_valid(del_hold) or not del_hold.visible:
			break
		print("[TestDeleteHold] Holding %.1fs Progress %.0f%%" % [del_hold._hold_time, del_hold.progress_bar.value if del_hold.progress_bar else 0])

	# Check slot deleted
	await create_timer(0.5).timeout
	if not SaveManager.slot_exists(0):
		print("[TestDeleteHold] PASS - Slot 0 deleted after 3s hold")
		quit(0)
	else:
		print("[TestDeleteHold] FAIL - Slot still exists after hold")
		quit(1)
