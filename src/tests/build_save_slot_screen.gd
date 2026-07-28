extends SceneTree

func set_owner_recursive(node: Node, owner: Node):
	for child in node.get_children():
		child.owner = owner
		set_owner_recursive(child, owner)

func _init():
	print("[Build] Building SaveSlotScreen.tscn programmatically to fix parse error")

	var root = Control.new()
	root.name = "SaveSlotScreen"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.set_script(load("res://ui/main_menu/save_slot_screen.gd"))

	var bg = ColorRect.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color(0.11, 0.13, 0.16, 1)
	root.add_child(bg)
	bg.owner = root

	var dim = ColorRect.new()
	dim.name = "DimOverlay"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0, 0, 0, 0.22)
	root.add_child(dim)
	dim.owner = root

	var center = CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	center.owner = root

	var panel = Panel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(460, 520)
	panel.size_flags_horizontal = 0
	panel.size_flags_vertical = 0
	if ResourceLoader.exists("res://shaders/frosted_panel_material.tres"):
		panel.material = load("res://shaders/frosted_panel_material.tres")
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.16, 0.22)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.10)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	panel.owner = root

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	vbox.offset_left = 20
	vbox.offset_top = 18
	vbox.offset_right = -20
	vbox.offset_bottom = -18
	panel.add_child(vbox)
	vbox.owner = root

	var title = Label.new()
	title.name = "Title"
	title.custom_minimum_size = Vector2(0, 36)
	title.text = "SELECT WORLD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1))
	vbox.add_child(title)
	title.owner = root

	var slots_container = VBoxContainer.new()
	slots_container.name = "SlotsContainer"
	slots_container.add_theme_constant_override("separation", 12)
	vbox.add_child(slots_container)
	slots_container.owner = root

	var back_scene = load("res://ui/main_menu/wildes_button.tscn") as PackedScene
	var back_btn = back_scene.instantiate()
	back_btn.name = "BackButton"
	back_btn.custom_minimum_size = Vector2(180, 46)
	vbox.add_child(back_btn)
	back_btn.owner = root
	set_owner_recursive(back_btn, root)

	var create_dialog = Panel.new()
	create_dialog.name = "CreateDialog"
	create_dialog.visible = false
	create_dialog.custom_minimum_size = Vector2(400, 240)
	if ResourceLoader.exists("res://shaders/frosted_panel_material.tres"):
		create_dialog.material = load("res://shaders/frosted_panel_material.tres")
	var sb2 = StyleBoxFlat.new()
	sb2.bg_color = Color(0.14, 0.15, 0.18, 0.28)
	sb2.corner_radius_top_left = 14
	sb2.corner_radius_top_right = 14
	sb2.corner_radius_bottom_left = 14
	sb2.corner_radius_bottom_right = 14
	sb2.border_width_left = 1
	sb2.border_width_right = 1
	sb2.border_width_top = 1
	sb2.border_width_bottom = 1
	sb2.border_color = Color(1, 1, 1, 0.10)
	create_dialog.add_theme_stylebox_override("panel", sb2)
	create_dialog.set_anchors_preset(Control.PRESET_CENTER)
	create_dialog.offset_left = -200
	create_dialog.offset_top = -120
	create_dialog.offset_right = 200
	create_dialog.offset_bottom = 120
	root.add_child(create_dialog)
	create_dialog.owner = root

	var cd_vbox = VBoxContainer.new()
	cd_vbox.name = "VBox"
	cd_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_vbox.offset_left = 18
	cd_vbox.offset_top = 18
	cd_vbox.offset_right = -18
	cd_vbox.offset_bottom = -18
	cd_vbox.add_theme_constant_override("separation", 12)
	create_dialog.add_child(cd_vbox)
	cd_vbox.owner = root

	var cd_title = Label.new()
	cd_title.name = "Title"
	cd_title.text = "Create New World"
	cd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_title.add_theme_font_size_override("font_size", 20)
	cd_title.add_theme_color_override("font_color", Color(0.96, 0.95, 0.9, 1))
	cd_vbox.add_child(cd_title)
	cd_title.owner = root

	var name_edit = LineEdit.new()
	name_edit.name = "NameEdit"
	name_edit.custom_minimum_size = Vector2(0, 36)
	name_edit.placeholder_text = "World Name"
	name_edit.add_theme_font_size_override("font_size", 14)
	cd_vbox.add_child(name_edit)
	name_edit.owner = root

	var seed_label = Label.new()
	seed_label.name = "SeedLabel"
	seed_label.text = "Seed: 0 (random)"
	seed_label.add_theme_font_size_override("font_size", 12)
	seed_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72, 1))
	cd_vbox.add_child(seed_label)
	seed_label.owner = root

	var hbox_rand = HBoxContainer.new()
	hbox_rand.name = "HBoxRandomize"
	hbox_rand.alignment = BoxContainer.ALIGNMENT_CENTER
	cd_vbox.add_child(hbox_rand)
	hbox_rand.owner = root

	var rand_btn = Button.new()
	rand_btn.name = "RandomizeButton"
	rand_btn.custom_minimum_size = Vector2(140, 32)
	rand_btn.text = "Randomize Seed"
	rand_btn.add_theme_font_size_override("font_size", 12)
	hbox_rand.add_child(rand_btn)
	rand_btn.owner = root

	var hbox_actions = HBoxContainer.new()
	hbox_actions.name = "HBoxActions"
	hbox_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox_actions.add_theme_constant_override("separation", 14)
	cd_vbox.add_child(hbox_actions)
	hbox_actions.owner = root

	var cancel_btn = Button.new()
	cancel_btn.name = "CancelButton"
	cancel_btn.custom_minimum_size = Vector2(90, 36)
	cancel_btn.text = "Cancel"
	cancel_btn.add_theme_font_size_override("font_size", 13)
	hbox_actions.add_child(cancel_btn)
	cancel_btn.owner = root

	var confirm_btn = back_scene.instantiate()
	confirm_btn.name = "ConfirmButton"
	confirm_btn.custom_minimum_size = Vector2(160, 42)
	hbox_actions.add_child(confirm_btn)
	confirm_btn.owner = root
	set_owner_recursive(confirm_btn, root)

	var del_scene = load("res://ui/main_menu/delete_hold_screen.tscn") as PackedScene
	var del_inst = del_scene.instantiate()
	del_inst.name = "DeleteHoldScreen"
	root.add_child(del_inst)
	del_inst.owner = root
	set_owner_recursive(del_inst, root)

	var packed = PackedScene.new()
	packed.pack(root)

	var err = ResourceSaver.save(packed, "res://ui/main_menu/save_slot_screen.tscn")
	if err == OK:
		print("[Build] Saved SaveSlotScreen.tscn successfully")
	else:
		print("[Build] Failed to save SaveSlotScreen err=%d" % err)

	quit(0)
