extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _hud: HUD = null
var _inv: InventoryModel = null
var _item_catalog: ItemCatalog = null
var _stats: ActorStats = null
var _item_proficiency: ItemProficiency = null
var _inventory_stat_coordinator: InventoryStatCoordinator = null
var _crafting_coordinator: CraftingCoordinator = null
var _crafting_recipe_catalog: CraftingRecipeCatalog = null
var _errors: Array[String] = []
var _orphan_before: int = 0
var _src_center: Vector2 = Vector2.ZERO
var _dst_center: Vector2 = Vector2.ZERO
var _right_src_center: Vector2 = Vector2.ZERO
var _right_dst_center: Vector2 = Vector2.ZERO
var _left_start_frame: int = 0
var _right_start_frame: int = 0
var _left_destination_index: int = -1
var _left_destination_ui_index: int = -1
var _right_destination_index: int = -1
var _right_destination_ui_index: int = -1
var _hotbar_click_destination_index: int = -1
var _hotbar_click_destination_ui_index: int = -1
var _helmet_inventory_slot: InventorySlot = null
var _original_window_size: Vector2i

func _init() -> void:
	print("[hud_integration] starting")
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_inv = InventoryModel.new(_item_catalog)
	_inv.setup_starter()
	_stats = ActorStats.new(load("res://player/player_stats.tres") as ActorStatsDefinition)
	_item_proficiency = ItemProficiency.new(_item_catalog)
	if not _stats.set_progression(1, 0):
		_fail("player progression setup failed")
	_inventory_stat_coordinator = InventoryStatCoordinator.new()
	if not _inventory_stat_coordinator.setup(_inv, _stats):
		_fail("equipment coordinator setup failed")
	_crafting_recipe_catalog = load("res://crafting/crafting_recipe_catalog.tres") as CraftingRecipeCatalog
	_crafting_coordinator = CraftingCoordinator.new()
	_crafting_coordinator.setup(_inv, _crafting_recipe_catalog)
	_orphan_before = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("[hud_integration] orphan before %d" % _orphan_before)

func _process(_delta: float) -> bool:
	_frame += 1
	if _phase == 0 and _frame == 2:
		var packed: PackedScene = load("res://ui/hud/hud.tscn") as PackedScene
		if packed == null:
			_fail("failed to load hud.tscn")
			return false
		_hud = packed.instantiate() as HUD
		if _hud == null:
			_fail("hud instantiate null")
			return false
		root.add_child(_hud)
		_hud.setup_with_camera(_inv, _inventory_stat_coordinator, _crafting_coordinator, _crafting_recipe_catalog, null, _stats, _item_proficiency)
		print("[hud_integration] hud added orphan=%d" % int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
		_phase = 1
	elif _phase == 1 and _frame == 4:
		_check_health_bar_geometry()
		_check_health_bar(100.0, 100.0)
		_check_experience_bar_geometry()
		_check_experience_bar(1, 0, 100)
		_stats.add_experience(50)
		_stats.damage(25.0)
	elif _phase == 1 and _frame == 5:
		_check_health_bar(75.0, 100.0)
		_check_experience_bar(1, 50, 100)
		_stats.add_experience(50)
		_stats.heal(10.0)
	elif _phase == 1 and _frame == 6:
		_check_health_bar(85.0, 100.0)
		_check_experience_bar(2, 0, 125)
		var maximum_hp_modifier := StatModifier.new()
		maximum_hp_modifier.id = &"hud_test_hp"
		maximum_hp_modifier.source_id = &"hud_test"
		maximum_hp_modifier.stat_id = &"hp"
		maximum_hp_modifier.operation = StatModifier.Operation.ADD
		maximum_hp_modifier.amount = 50.0
		if not _stats.add_modifier(maximum_hp_modifier):
			_fail("health bar maximum HP modifier was rejected")
	elif _phase == 1 and _frame == 7:
		_check_health_bar(85.0, 150.0)
		if not _stats.remove_modifier(&"hud_test_hp"):
			_fail("health bar maximum HP modifier was not removed")
		_stats.heal(100.0)
		print("[hud_integration] health bar ok")
	elif _phase == 1 and _frame == 8:
		_original_window_size = root.size
		_check_health_bar_panel_transitions()
		root.size = Vector2i(684, 480)
	elif _phase == 1 and _frame == 10:
		_check_health_bar_panel_clearance(0.0, "684px closed")
		_check_experience_bar_geometry()
		_hud.side_panel.open()
		_hud.side_panel._process(1.0)
		_check_health_bar_panel_clearance(1.0, "684px open")
		root.size = Vector2i(640, 480)
	elif _phase == 1 and _frame == 12:
		_check_health_bar_panel_clearance(1.0, "640px open")
		_check_experience_bar_geometry()
		root.size = Vector2i(1024, 640)
	elif _phase == 1 and _frame == 14:
		_check_health_bar_panel_clearance(1.0, "1024px open")
		_check_experience_bar_geometry()
		root.size = _original_window_size
	elif _phase == 1 and _frame == 16:
		_check_health_bar_panel_clearance(1.0, "restored open")
		_hud.side_panel.close_immediate()
		_check_health_bar_panel_clearance(0.0, "restored immediate close")
		_check_experience_bar_geometry()
	elif _phase == 1 and _frame == 122:
		if _hud == null or not is_instance_valid(_hud):
			_fail("hud invalid")
			return false
		if _hud.hotbar == null or _hud.hotbar.slot_nodes.is_empty():
			_fail("hotbar not ready")
			return false
		if _hud.side_panel == null:
			_fail("side_panel null")
			return false
		var grass_item := _item_catalog.get_item_for_block(BlockId.Type.GRASS)
		var hotbar_grass := _hud.hotbar.slot_nodes[1] as HotbarSlot
		if hotbar_grass.icon.texture != grass_item.icon:
			_fail("grass hotbar icon mismatch")
			return false
		_check_hotbar_gear_tooltips()
		_hud.side_panel.open()
		print("[hud_integration] side panel open progress %f" % _hud.side_panel.get_progress())
		_phase = 2
	elif _phase == 2 and _frame >= 150:
		if _hud.side_panel.get_progress() < 0.95:
			if _frame < 170:
				return false
			_fail("panel not open %f" % _hud.side_panel.get_progress())
			return false
		var src_slot: Control = _hud.hotbar.slot_nodes[1] as Control
		var inv_slots: Array[InventorySlot] = _hud.side_panel.get_inventory_slots()
		if inv_slots.is_empty():
			_fail("no inventory slots")
			return false
		_check_backpack_gear_tooltip(inv_slots)
		_left_destination_ui_index = _find_empty_inventory_ui_index(inv_slots)
		if _left_destination_ui_index < 0:
			_fail("no empty inventory slot for left drag")
			return false
		var dst_inventory_slot := inv_slots[_left_destination_ui_index]
		_left_destination_index = dst_inventory_slot.slot_index
		var dst_slot: Control = dst_inventory_slot as Control
		_src_center = src_slot.get_global_rect().get_center()
		_dst_center = dst_slot.get_global_rect().get_center()
		print("[hud_integration] left drag src %s dst %s" % [str(_src_center), str(_dst_center)])
		if _src_center == Vector2.ZERO or _dst_center == Vector2.ZERO:
			_fail("slot center zero")
			return false
		_start_left_drag(_src_center, _dst_center)
		_left_start_frame = _frame
		_phase = 3
	elif _phase == 3 and _frame == _left_start_frame + 3:
		_check_mid_drag("left", 1)
		_phase = 4
	elif _phase == 4 and _frame == _left_start_frame + 5:
		_end_left_drag(_dst_center)
		_phase = 5
	elif _phase == 5 and _frame == _left_start_frame + 10:
		_check_left_drag_result()
		_phase = 6
	elif _phase == 6 and _frame == 170:
		var src_slot2: Control = _hud.hotbar.slot_nodes[6] as Control
		var inv_slots2: Array[InventorySlot] = _hud.side_panel.get_inventory_slots()
		_right_destination_ui_index = _find_empty_inventory_ui_index(inv_slots2)
		if _right_destination_ui_index < 0:
			_fail("no empty inventory slot for right drag")
			return false
		var dst_inventory_slot2 := inv_slots2[_right_destination_ui_index]
		_right_destination_index = dst_inventory_slot2.slot_index
		var dst_slot2: Control = dst_inventory_slot2 as Control
		_right_src_center = src_slot2.get_global_rect().get_center()
		_right_dst_center = dst_slot2.get_global_rect().get_center()
		print("[hud_integration] right drag src %s dst %s" % [str(_right_src_center), str(_right_dst_center)])
		_start_right_drag(_right_src_center, _right_dst_center)
		_right_start_frame = _frame
		_phase = 7
	elif _phase == 7 and _frame == _right_start_frame + 3:
		_check_mid_drag("right", 1)
		_phase = 8
	elif _phase == 8 and _frame == _right_start_frame + 5:
		_end_right_drag(_right_dst_center)
		_phase = 9
	elif _phase == 9 and _frame == _right_start_frame + 10:
		_check_right_drag_result()
		_phase = 10
	elif _phase == 10 and _frame == 185:
		_start_armor_equip()
		_phase = 11
	elif _phase == 11 and _frame == 187:
		_check_armor_equipped_and_open_tab()
		_phase = 12
	elif _phase == 12 and _frame == 189:
		_start_armor_unequip()
		_phase = 13
	elif _phase == 13 and _frame == 191:
		_check_armor_unequipped()
		_phase = 14
	elif _phase == 14 and _frame == 193:
		_start_number_assignment()
		_phase = 15
	elif _phase == 15 and _frame == 195:
		_check_number_assignment()
		_phase = 16
	elif _phase == 16 and _frame == 197:
		_check_hotbar_reassignment()
		_phase = 17
	elif _phase == 17 and _frame == 199:
		_check_hotbar_reassignment_restored()
		_phase = 18
	elif _phase == 18 and _frame == 201:
		_fill_backpack_and_start_hotbar_click()
		_phase = 19
	elif _phase == 19 and _frame == 203:
		_check_hotbar_press_and_release()
		_phase = 20
	elif _phase == 20 and _frame == 205:
		_check_full_backpack_click_result()
		_phase = 21
	elif _phase == 21 and _frame == 207:
		_check_hotbar_press_and_release()
		_phase = 22
	elif _phase == 22 and _frame == 209:
		_check_hotbar_click_result()
		_phase = 23
	elif _phase == 23 and _frame == 211:
		_start_closed_hotbar_click()
		_phase = 24
	elif _phase == 24 and _frame == 213:
		_check_closed_hotbar_press_and_release()
		_phase = 25
	elif _phase == 25 and _frame == 215:
		_check_closed_hotbar_click_result()
		_phase = 26
	elif _phase == 26 and _frame == 217:
		_check_final_and_quit()
	return false

func _check_health_bar(current_hp: float, maximum_hp: float) -> void:
	if _hud.health_bar == null:
		_fail("health bar missing")
		return
	var progress_bar := _hud.health_bar.progress_bar
	var expected_text := "HP %d / %d" % [roundi(current_hp), roundi(maximum_hp)]
	if not is_equal_approx(progress_bar.value, current_hp):
		_fail("health bar current HP expected %.1f got %.1f" % [current_hp, progress_bar.value])
		return
	if not is_equal_approx(progress_bar.max_value, maximum_hp):
		_fail("health bar maximum HP expected %.1f got %.1f" % [maximum_hp, progress_bar.max_value])
		return
	if _hud.health_bar.value_label.text != expected_text:
		_fail("health bar hover text expected %s got %s" % [expected_text, _hud.health_bar.value_label.text])

func _check_experience_bar(level: int, experience: int, required_experience: int) -> void:
	if _hud.experience_bar == null:
		_fail("experience bar missing")
		return
	var progress_bar := _hud.experience_bar.progress_bar
	var expected_text := "Level %d - %d / %d XP" % [level, experience, required_experience]
	if not is_equal_approx(progress_bar.value, experience):
		_fail("experience bar current XP expected %d got %.1f" % [experience, progress_bar.value])
		return
	if not is_equal_approx(progress_bar.max_value, required_experience):
		_fail("experience bar required XP expected %d got %.1f" % [required_experience, progress_bar.max_value])
		return
	if _hud.experience_bar.value_label.text != expected_text:
		_fail("experience bar text expected %s got %s" % [expected_text, _hud.experience_bar.value_label.text])

func _check_experience_bar_geometry() -> void:
	if _hud.experience_bar == null:
		_fail("experience bar missing for geometry check")
		return
	var viewport_size := root.get_visible_rect().size
	var root_rect := _hud.experience_bar.get_global_rect()
	var progress_bar := _hud.experience_bar.progress_bar
	var progress_rect := progress_bar.get_global_rect()
	var right_inset := SidePanel.PANEL_WIDTH * _hud.side_panel.get_progress()
	var expected_width := minf(PlayerExperienceBar.PREFERRED_WIDTH, maxf(viewport_size.x - right_inset - PlayerExperienceBar.EDGE_MARGIN * 2.0, 0.0))
	var expected_position := Vector2((viewport_size.x - right_inset - expected_width) * 0.5, viewport_size.y - PlayerExperienceBar.HOTBAR_TOP_INSET - PlayerExperienceBar.BAR_HEIGHT)
	if not root_rect.position.is_equal_approx(Vector2.ZERO) or not root_rect.size.is_equal_approx(viewport_size):
		_fail("experience bar root does not cover the viewport")
		return
	if not progress_rect.position.is_equal_approx(expected_position):
		_fail("experience bar expected position %s got %s" % [str(expected_position), str(progress_rect.position)])
		return
	if not progress_rect.size.is_equal_approx(Vector2(expected_width, PlayerExperienceBar.BAR_HEIGHT)):
		_fail("experience bar expected responsive size got %s" % str(progress_rect.size))
		return
	if not is_equal_approx(progress_rect.end.y, viewport_size.y - PlayerExperienceBar.HOTBAR_TOP_INSET):
		_fail("experience bar is not directly above the hotbar")
		return
	if not is_equal_approx(progress_rect.get_center().x, _hud.hotbar.get_global_rect().get_center().x):
		_fail("experience bar is not centered above the shifted hotbar")
		return
	if progress_rect.end.x > viewport_size.x - right_inset - PlayerExperienceBar.EDGE_MARGIN + 0.001:
		_fail("experience bar overlaps the side panel")
		return
	if _hud.experience_bar.mouse_filter != Control.MOUSE_FILTER_IGNORE or progress_bar.mouse_filter != Control.MOUSE_FILTER_IGNORE or _hud.experience_bar.value_label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("experience bar presentation intercepts mouse input")
		return
	var track := progress_bar.get_theme_stylebox(&"background") as StyleBoxFlat
	var fill := progress_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if track == null or track.bg_color.a >= 1.0 or track.bg_color.r >= 0.2:
		_fail("experience bar track is not dark and translucent")
		return
	if fill == null or fill.bg_color.g <= fill.bg_color.r or fill.bg_color.g <= fill.bg_color.b:
		_fail("experience bar fill is not green")
		return
	if _hud.experience_bar.value_label.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER or _hud.experience_bar.value_label.vertical_alignment != VERTICAL_ALIGNMENT_CENTER:
		_fail("experience bar value text is not centered")

func _check_health_bar_geometry() -> void:
	if _hud.health_bar == null:
		_fail("health bar missing for geometry check")
		return
	var viewport_size := root.get_visible_rect().size
	var root_rect := _hud.health_bar.get_global_rect()
	var progress_bar := _hud.health_bar.progress_bar
	var progress_rect := progress_bar.get_global_rect()
	var expected_position := Vector2(viewport_size.x - PlayerHealthBar.EDGE_MARGIN - PlayerHealthBar.PREFERRED_WIDTH, PlayerHealthBar.EDGE_MARGIN)
	if not root_rect.position.is_equal_approx(Vector2.ZERO) or not root_rect.size.is_equal_approx(viewport_size):
		_fail("health bar root does not cover the viewport")
		return
	if not progress_rect.position.is_equal_approx(expected_position):
		_fail("health bar expected position %s got %s" % [str(expected_position), str(progress_rect.position)])
		return
	if not progress_rect.size.is_equal_approx(Vector2(PlayerHealthBar.PREFERRED_WIDTH, PlayerHealthBar.BAR_HEIGHT)):
		_fail("health bar expected preferred size got %s" % str(progress_rect.size))
		return
	if not is_equal_approx(viewport_size.x - progress_rect.end.x, PlayerHealthBar.EDGE_MARGIN) or not is_equal_approx(progress_rect.position.y, PlayerHealthBar.EDGE_MARGIN):
		_fail("health bar does not preserve its 24-pixel top-right margins")
		return
	if _hud.health_bar.mouse_filter != Control.MOUSE_FILTER_IGNORE or progress_bar.mouse_filter != Control.MOUSE_FILTER_PASS or _hud.health_bar.hover_panel.mouse_filter != Control.MOUSE_FILTER_IGNORE or _hud.health_bar.value_label.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("health bar hover target has incorrect mouse filtering")
		return
	if _hud.health_bar.hover_panel.visible:
		_fail("health bar hover panel is visible without a hover")
		return
	progress_bar.mouse_entered.emit()
	if not _hud.health_bar.hover_panel.visible:
		_fail("health bar hover panel did not appear immediately")
		return
	progress_bar.mouse_exited.emit()
	if _hud.health_bar.hover_panel.visible:
		_fail("health bar hover panel remained visible after exit")
		return
	var hover_style := _hud.health_bar.hover_panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	if hover_style == null or not (_hud.health_bar.hover_panel.material is ShaderMaterial):
		_fail("health bar hover panel is not frosted")
		return
	var track := progress_bar.get_theme_stylebox(&"background") as StyleBoxFlat
	var fill := progress_bar.get_theme_stylebox(&"fill") as StyleBoxFlat
	if track == null or track.bg_color.a >= 1.0 or track.bg_color.r >= 0.2:
		_fail("health bar track is not dark and translucent")
		return
	if track.border_width_left != 1 or track.border_width_top != 1 or track.border_width_right != 1 or track.border_width_bottom != 1:
		_fail("health bar track border is not subtle and uniform")
		return
	if fill == null or fill.bg_color.r <= fill.bg_color.g or fill.bg_color.r <= fill.bg_color.b:
		_fail("health bar fill is not red")
		return
	if fill.border_width_left != 1 or fill.border_width_top != 1 or fill.border_width_right != 1 or fill.border_width_bottom != 1:
		_fail("health bar fill border is not uniform")
		return

func _check_health_bar_panel_transitions() -> void:
	_hud.side_panel.open()
	_hud.side_panel._process(0.02)
	var opening_progress := _hud.side_panel.get_progress()
	if opening_progress <= 0.0 or opening_progress >= 1.0:
		_fail("side panel opening did not produce intermediate progress")
		return
	_check_health_bar_panel_clearance(opening_progress, "opening")
	_hud.side_panel.close()
	_hud.side_panel._process(0.02)
	var closing_progress := _hud.side_panel.get_progress()
	if closing_progress <= 0.0 or closing_progress >= opening_progress:
		_fail("side panel closing did not produce lower intermediate progress")
		return
	_check_health_bar_panel_clearance(closing_progress, "closing")
	_hud.side_panel.close_immediate()
	_check_health_bar_panel_clearance(0.0, "immediate close")

func _check_health_bar_panel_clearance(progress: float, context: String) -> void:
	var viewport_size := root.get_visible_rect().size
	var expected_inset := SidePanel.PANEL_WIDTH * progress
	var expected_width := minf(PlayerHealthBar.PREFERRED_WIDTH, maxf(viewport_size.x - expected_inset - PlayerHealthBar.EDGE_MARGIN * 2.0, 0.0))
	var expected_right_offset := -(PlayerHealthBar.EDGE_MARGIN + expected_inset)
	var expected_left_offset := expected_right_offset - expected_width
	var progress_bar := _hud.health_bar.progress_bar
	var progress_rect := progress_bar.get_global_rect()
	var panel_rect := _hud.side_panel.get_global_rect()
	if not is_equal_approx(_hud.side_panel.get_progress(), progress):
		_fail("%s side panel progress changed before layout assertion" % context)
		return
	if not is_equal_approx(progress_bar.offset_right, expected_right_offset) or not is_equal_approx(progress_bar.offset_left, expected_left_offset):
		_fail("%s health offsets do not equal 380 times panel progress" % context)
		return
	if not is_equal_approx(progress_rect.end.x, viewport_size.x + expected_right_offset):
		_fail("%s health bar right edge does not match its authoritative inset" % context)
		return
	if not is_equal_approx(progress_rect.size.x, expected_width):
		_fail("%s health bar width did not fit the unobstructed viewport" % context)
		return
	if not is_equal_approx(panel_rect.position.x, viewport_size.x - expected_inset):
		_fail("%s side panel position does not match its authoritative progress" % context)
		return
	if not is_equal_approx(panel_rect.position.x - progress_rect.end.x, PlayerHealthBar.EDGE_MARGIN):
		_fail("%s health bar did not preserve its 24-pixel panel gap" % context)
		return
	if progress_rect.end.x > panel_rect.position.x or progress_rect.position.x < -0.001:
		_fail("%s health bar overlaps the inventory panel or viewport edge" % context)

func _start_left_drag(src: Vector2, dst: Vector2) -> void:
	print("[hud_integration] left drag start")
	var vp: Viewport = root
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = src
	press.global_position = src
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	vp.push_input(press, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = dst
	motion.global_position = dst
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.relative = dst - src
	vp.push_input(motion, true)
	print("[hud_integration] left drag start pushed")

func _end_left_drag(dst: Vector2) -> void:
	print("[hud_integration] left drag end")
	var vp: Viewport = root
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = dst
	release.global_position = dst
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	vp.push_input(release, true)
	print("[hud_integration] left drag end pushed")

func _start_right_drag(src: Vector2, dst: Vector2) -> void:
	print("[hud_integration] right drag start half-split")
	var vp: Viewport = root
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = src
	press.global_position = src
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_RIGHT
	vp.push_input(press, true)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = dst
	motion.global_position = dst
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	motion.relative = dst - src
	vp.push_input(motion, true)
	print("[hud_integration] right drag start pushed")

func _end_right_drag(dst: Vector2) -> void:
	print("[hud_integration] right drag end")
	var vp: Viewport = root
	var release: InputEventMouseButton = InputEventMouseButton.new()
	release.position = dst
	release.global_position = dst
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	vp.push_input(release, true)
	var left_release: InputEventMouseButton = InputEventMouseButton.new()
	left_release.position = dst
	left_release.global_position = dst
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	vp.push_input(left_release, true)
	print("[hud_integration] right drag end pushed")

func _totals(inv: InventoryModel) -> Dictionary:
	var d: Dictionary = {}
	for s in inv.slots:
		if s != null:
			d[s.item_id] = d.get(s.item_id, 0) + s.count
	return d

func _find_empty_inventory_ui_index(slots: Array[InventorySlot]) -> int:
	for index in range(slots.size()):
		if _inv.get_slot(slots[index].slot_index) == null:
			return index
	return -1

func _check_mid_drag(label: String, expected: int) -> void:
	print("[hud_integration] check mid %s drag frame %d" % [label, _frame])
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var previews: Array = []
	_find_drag_previews(root, previews)
	print("[hud_integration] mid %s orphan=%d previews=%d %s" % [label, orphan, previews.size(), str(previews)])
	if orphan != 0:
		_warn("mid %s drag: orphan %d" % [label, orphan])
		_fail("mid %s drag: orphan %d" % [label, orphan])
		return
	if previews.size() != expected:
		_warn("mid %s drag: expected %d preview(s) while dragging, got %d" % [label, expected, previews.size()])
		_fail("mid %s drag: expected %d preview(s) while dragging, got %d %s" % [label, expected, previews.size(), str(previews)])
		return
	if previews.size() == 1:
		var pl = previews[0] as CanvasLayer
		if not is_instance_valid(pl) or not pl.visible:
			_warn("mid %s drag: preview not visible" % label)
			_fail("mid %s drag: preview not visible" % label)
			return
		if pl.get_child_count() == 0:
			_warn("mid %s drag: preview has no child" % label)
			_fail("mid %s drag: preview has no child" % label)
			return
		var preview_panel := pl.get_child(0) as Control
		var preview_icon := preview_panel.get_node_or_null("Icon") as TextureRect
		var expected_block := BlockId.Type.GRASS if label == "left" else BlockId.Type.TORCH
		var expected_icon := _item_catalog.get_item_for_block(expected_block).icon
		if preview_icon == null or preview_icon.texture != expected_icon:
			_fail("mid %s drag: preview icon mismatch" % label)
			return
	print("[hud_integration] mid %s drag ok (preview %d visible)" % [label, expected])

func _check_left_drag_result() -> void:
	print("[hud_integration] check left drag result frame %d" % _frame)
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("[hud_integration] orphan=%d" % orphan)
	var previews: Array = []
	_find_drag_previews(root, previews)
	print("[hud_integration] previews %d %s" % [previews.size(), str(previews)])
	if orphan != 0:
		_fail("orphan after left drag %d" % orphan)
		return
	if not previews.is_empty():
		_fail("leaked preview after left drag %s" % str(previews))
		return
	var s1 = _inv.get_slot(1)
	var destination = _inv.get_slot(_left_destination_index)
	var grass_id := _item_catalog.get_item_for_block(BlockId.Type.GRASS).id
	var stone_id := _item_catalog.get_item_for_block(BlockId.Type.STONE).id
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	print("[hud_integration] slot1 %s destination %s" % [str(s1), str(destination)])
	if s1 != null:
		_fail("left drag: slot 1 should be null after move but got %s" % str(s1))
		return
	if destination == null or destination.item_id != grass_id or destination.count != 12:
		_fail("left drag: destination expected grass 12 got %s" % str(destination))
		return
	var n1: HotbarSlot = _hud.hotbar.slot_nodes[1] as HotbarSlot
	if n1.item_id != null:
		_fail("left drag: hotbar node 1 should be null")
		return
	var inv_node: InventorySlot = _hud.side_panel.get_inventory_slots()[_left_destination_ui_index]
	if inv_node.item_id != grass_id or inv_node.item_count != 12:
		_fail("left drag: inventory node mismatch %s %d" % [str(inv_node.item_id), inv_node.item_count])
		return
	if inv_node.icon.texture != _item_catalog.get_definition(grass_id).icon:
		_fail("left drag: inventory icon mismatch")
		return
	var totals: Dictionary = _totals(_inv)
	if totals.get(&"copper_pickaxe", 0) != 0 or totals.get(&"copper_sword", 0) != 1 or totals.get(grass_id, 0) != 12 or totals.get(stone_id, 0) != 8 or totals.get(torch_id, 0) != 16:
		_fail("left drag: totals changed %s" % str(totals))
		return
	print("[hud_integration] left drag ok")

func _check_right_drag_result() -> void:
	print("[hud_integration] check right drag frame %d" % _frame)
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("[hud_integration] orphan=%d" % orphan)
	var previews: Array = []
	_find_drag_previews(root, previews)
	print("[hud_integration] previews %d %s" % [previews.size(), str(previews)])
	if orphan != 0:
		_fail("orphan after right drag %d" % orphan)
		return
	if not previews.is_empty():
		_fail("leaked drag preview after right drag %s" % str(previews))
		return
	var s6 = _inv.get_slot(6)
	var destination = _inv.get_slot(_right_destination_index)
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	print("[hud_integration] slot6 %s destination %s" % [str(s6), str(destination)])
	if s6 == null or s6.count != 8 or s6.item_id != torch_id:
		_fail("right drag: slot6 expected torch 8 got %s" % str(s6))
		return
	if destination == null or destination.count != 8 or destination.item_id != torch_id:
		_fail("right drag: destination expected torch 8 got %s" % str(destination))
		return
	var n6: HotbarSlot = _hud.hotbar.slot_nodes[6] as HotbarSlot
	if n6.item_count != 8 or n6.item_id != torch_id:
		_fail("right drag: hotbar node6 mismatch")
		return
	var inv_node: InventorySlot = _hud.side_panel.get_inventory_slots()[_right_destination_ui_index]
	if inv_node.item_id != torch_id or inv_node.item_count != 8:
		_fail("right drag: inventory node1 mismatch")
		return
	for i in range(_inv.size):
		var s = _inv.get_slot(i)
		if s != null:
			var max_stack := _item_catalog.get_definition(s.item_id).max_stack
			if s.count <= 0 or s.count > max_stack:
				_fail("right drag: invariant at %d" % i)
				return
			if not _inv.can_slot_accept_item_id(i, s.item_id):
				_fail("right drag: slot %d not accepted" % i)
				return
	print("[hud_integration] right drag ok")

func _start_number_assignment() -> void:
	var backpack_slot := _hud.side_panel.get_inventory_slots()[_right_destination_ui_index]
	var backpack_center := backpack_slot.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = backpack_center
	motion.global_position = backpack_center
	root.push_input(motion, true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_4
	key.pressed = true
	root.push_input(key, true)

func _check_number_assignment() -> void:
	var hotbar_stack := _inv.get_slot(3)
	var backpack_stack := _inv.get_slot(_right_destination_index)
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	if hotbar_stack == null or hotbar_stack.item_id != torch_id or hotbar_stack.count != 8:
		_fail("number assignment: hotbar slot 4 expected torch 8 got %s" % str(hotbar_stack))
		return
	if backpack_stack == null or backpack_stack.item_id != &"copper_sword" or backpack_stack.count != 1:
		_fail("number assignment: backpack expected copper sword got %s" % str(backpack_stack))
		return
	var hotbar_node := _hud.hotbar.slot_nodes[3]
	var backpack_node := _hud.side_panel.get_inventory_slots()[_right_destination_ui_index]
	if hotbar_node.item_id != torch_id or hotbar_node.item_count != 8:
		_fail("number assignment: hotbar visuals not refreshed")
		return
	if backpack_node.item_id != &"copper_sword" or backpack_node.item_count != 1:
		_fail("number assignment: backpack visuals not refreshed")
		return
	if _inv.selected_slot != 0:
		_fail("number assignment: selected hotbar slot changed")
		return
	print("[hud_integration] number assignment ok")
	_push_hotbar_assignment(3, KEY_5)

func _push_hotbar_assignment(source_index: int, keycode: Key) -> void:
	var source_center := _hud.hotbar.slot_nodes[source_index].get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = source_center
	motion.global_position = source_center
	root.push_input(motion, true)
	var key := InputEventKey.new()
	key.physical_keycode = keycode
	key.pressed = true
	root.push_input(key, true)

func _check_hotbar_reassignment() -> void:
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	if _inv.get_slot(3) != null:
		_fail("hotbar reassignment: source slot was not cleared")
		return
	var reassigned_stack := _inv.get_slot(4)
	if reassigned_stack == null or reassigned_stack.item_id != torch_id or reassigned_stack.count != 8:
		_fail("hotbar reassignment: destination expected torch 8 got %s" % str(reassigned_stack))
		return
	_push_hotbar_assignment(4, KEY_4)

func _check_hotbar_reassignment_restored() -> void:
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	var restored_stack := _inv.get_slot(3)
	if restored_stack == null or restored_stack.item_id != torch_id or restored_stack.count != 8:
		_fail("hotbar reassignment: restored slot expected torch 8 got %s" % str(restored_stack))
		return
	if _inv.get_slot(4) != null:
		_fail("hotbar reassignment: temporary destination was not cleared")
		return
	if _inv.selected_slot != 0:
		_fail("hotbar reassignment: selected hotbar slot changed")
		return
	_hud.side_panel._switch_to_tab_id("equipment")
	_push_hotbar_assignment(3, KEY_5)
	var equipment_tab_stack := _inv.get_slot(4)
	if equipment_tab_stack == null or equipment_tab_stack.item_id != torch_id or equipment_tab_stack.count != 8:
		_fail("hotbar reassignment: equipment tab blocked reassignment")
		return
	_push_hotbar_assignment(4, KEY_4)
	var equipment_tab_restored := _inv.get_slot(3)
	if equipment_tab_restored == null or equipment_tab_restored.item_id != torch_id or equipment_tab_restored.count != 8:
		_fail("hotbar reassignment: equipment tab restore failed")
		return
	_hud.side_panel._switch_to_tab_id("inventory")
	_push_hotbar_assignment(4, KEY_3)
	if not root.is_input_handled():
		_fail("hotbar reassignment: empty hovered slot did not consume hotkey input")
		return
	var unchanged_stack := _inv.get_slot(2)
	var stone_id := _item_catalog.get_item_for_block(BlockId.Type.STONE).id
	if unchanged_stack == null or unchanged_stack.item_id != stone_id or unchanged_stack.count != 8:
		_fail("hotbar reassignment: empty hovered slot changed inventory")
		return
	print("[hud_integration] hotbar reassignment ok")

func _start_hotbar_click() -> void:
	var hotbar_center := _hud.hotbar.slot_nodes[3].get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = hotbar_center
	motion.global_position = hotbar_center
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = hotbar_center
	press.global_position = hotbar_center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press, true)

func _fill_backpack_and_start_hotbar_click() -> void:
	var inventory_slots := _hud.side_panel.get_inventory_slots()
	_hotbar_click_destination_ui_index = _find_empty_inventory_ui_index(inventory_slots)
	if _hotbar_click_destination_ui_index < 0:
		_fail("hotbar click: no empty backpack destination")
		return
	_hotbar_click_destination_index = inventory_slots[_hotbar_click_destination_ui_index].slot_index
	var stone_id := _item_catalog.get_item_for_block(BlockId.Type.STONE).id
	var max_stack: int = _item_catalog.get_definition(stone_id).max_stack
	for backpack_idx in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		if _inv.get_slot(backpack_idx) == null:
			_inv.slots[backpack_idx] = InventoryStack.new(stone_id, max_stack)
	_inv.inventory_changed.emit()
	_start_hotbar_click()

func _check_hotbar_press_and_release() -> void:
	var hotbar_stack := _inv.get_slot(3)
	if hotbar_stack == null:
		_fail("hotbar click: item moved before mouse release")
		return
	var hotbar_center := _hud.hotbar.slot_nodes[3].get_global_rect().get_center()
	var release := InputEventMouseButton.new()
	release.position = hotbar_center
	release.global_position = hotbar_center
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)

func _check_full_backpack_click_result() -> void:
	var hotbar_stack := _inv.get_slot(3)
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	if hotbar_stack == null or hotbar_stack.item_id != torch_id or hotbar_stack.count != 8:
		_fail("full backpack click: hotbar item changed")
		return
	for backpack_idx in range(InventoryModel.HOTBAR_SIZE, InventoryModel.FILLABLE_SIZE):
		var backpack_stack := _inv.get_slot(backpack_idx)
		if backpack_stack == null:
			_fail("full backpack click: backpack slot %d became empty" % backpack_idx)
			return
		if backpack_stack.item_id == torch_id:
			_fail("full backpack click: hotbar item moved to backpack slot %d" % backpack_idx)
			return
	print("[hud_integration] full backpack click rejected")
	_inv.slots[_hotbar_click_destination_index] = null
	_inv.inventory_changed.emit()
	_start_hotbar_click()

func _check_hotbar_click_result() -> void:
	if _inv.get_slot(3) != null:
		_fail("hotbar click: hotbar slot was not cleared")
		return
	var backpack_stack := _inv.get_slot(_hotbar_click_destination_index)
	var torch_id := _item_catalog.get_item_for_block(BlockId.Type.TORCH).id
	if backpack_stack == null or backpack_stack.item_id != torch_id or backpack_stack.count != 8:
		_fail("hotbar click: backpack expected torch 8 got %s" % str(backpack_stack))
		return
	if _hud.hotbar.slot_nodes[3].item_id != null:
		_fail("hotbar click: hotbar visuals not refreshed")
		return
	var backpack_node := _hud.side_panel.get_inventory_slots()[_hotbar_click_destination_ui_index]
	if backpack_node.item_id != torch_id or backpack_node.item_count != 8:
		_fail("hotbar click: backpack visuals not refreshed")
		return
	print("[hud_integration] hotbar click ok")

func _start_armor_equip() -> void:
	print("[hud_integration] armor equip double click")
	for slot in _hud.side_panel.get_inventory_slots():
		var stack := _inv.get_slot(slot.slot_index)
		if stack != null and stack.item_id == &"copper_helmet":
			_helmet_inventory_slot = slot
			break
	if _helmet_inventory_slot == null:
		_fail("helmet inventory slot missing")
		return
	_push_double_click(_helmet_inventory_slot)

func _check_hotbar_gear_tooltips() -> void:
	var sword_slot := _hud.hotbar.slot_nodes[3]
	if sword_slot.tooltip_text != "Copper Sword":
		_fail("sword hotbar slot did not expose its gear tooltip")
		return
	var tooltip := _create_gear_tooltip(sword_slot, "sword hotbar")
	if tooltip == null:
		return
	if tooltip.item_name_label.text != "Copper Sword" or tooltip.rarity_label.text != "Common":
		_fail("sword tooltip identity is incorrect")
	if tooltip.rarity_label.get_theme_color("font_color") != _item_catalog.get_definition(&"copper_sword").rarity.display_color:
		_fail("sword tooltip rarity color is incorrect")
	if tooltip.proficiency_level_label.text != "Proficiency Level 0 / 1" or tooltip.proficiency_experience_label.text != "Proficiency XP: 0 / 100":
		_fail("sword tooltip initial proficiency is incorrect")
	for expected_stat in ["Base Damage: 10", "Reach: 2.5", "Cooldown: 0.48s", "Sweep: 120°"]:
		if not tooltip.stats_label.text.contains(expected_stat):
			_fail("sword tooltip is missing %s" % expected_stat)
	if _item_proficiency.add_experience(&"copper_sword", 100.0) != 1:
		_fail("sword tooltip test could not reach maximum proficiency")
		tooltip.free()
		return
	tooltip._process(0.0)
	if tooltip.proficiency_level_label.text != "Proficiency Level 1 / 1" or tooltip.proficiency_experience_label.text != "Proficiency XP: Max":
		_fail("visible sword tooltip did not refresh maximum proficiency")
	tooltip.free()
	var grass_slot := _hud.hotbar.slot_nodes[1]
	if not grass_slot.tooltip_text.is_empty() or grass_slot._make_custom_tooltip("") != null:
		_fail("ordinary block exposed a gear tooltip")

func _check_backpack_gear_tooltip(slots: Array[InventorySlot]) -> void:
	for slot in slots:
		if slot.item_id == &"copper_helmet":
			_check_helmet_tooltip(slot, "backpack")
			return
	_fail("helmet backpack tooltip slot is missing")

func _check_helmet_tooltip(slot: InventorySlot, context: String) -> void:
	var tooltip := _create_gear_tooltip(slot, context)
	if tooltip == null:
		return
	if tooltip.item_name_label.text != "Copper Helmet" or tooltip.rarity_label.text != "Common":
		_fail("%s helmet tooltip identity is incorrect" % context)
	if tooltip.proficiency_level_label.text != "Proficiency Level 0 / 1" or tooltip.proficiency_experience_label.text != "Proficiency XP: 0 / 100":
		_fail("%s helmet tooltip proficiency is incorrect" % context)
	if not tooltip.stats_label.text.contains("Slot: Head") or not tooltip.stats_label.text.contains("Defense: +1"):
		_fail("%s helmet tooltip stats are incorrect" % context)
	tooltip.free()

func _create_gear_tooltip(slot: InventorySlot, context: String) -> GearTooltip:
	var tooltip := slot._make_custom_tooltip(slot.tooltip_text) as GearTooltip
	if tooltip == null:
		_fail("%s gear tooltip was not created" % context)
		return null
	root.add_child(tooltip)
	return tooltip

func _check_armor_equipped_and_open_tab() -> void:
	var equipped := _inv.get_equipped_armor(ArmorDefinition.Slot.HEAD)
	if equipped == null or equipped.id != &"copper_helmet":
		_fail("helmet double click did not equip")
		return
	if not is_equal_approx(_stats.get_value(&"defense"), 1.0):
		_fail("helmet equip did not apply defense")
		return
	var equipment_slots := _hud.side_panel.get_equipment_slots()
	for armor_slot in range(ArmorDefinition.SLOT_COUNT):
		if equipment_slots[armor_slot].empty_label != ArmorDefinition.get_slot_label(armor_slot):
			_fail("equipment label mismatch for slot %d" % armor_slot)
			return
	_check_helmet_tooltip(equipment_slots[ArmorDefinition.Slot.HEAD], "equipment")
	var button := _hud.side_panel.get_node("Margin/Content/ActionButtons/EquipmentButton/Button") as Control
	_push_left_click(button)

func _start_armor_unequip() -> void:
	var equipment_view := _hud.side_panel.get_node("Margin/Content/ViewRoot/EquipmentView") as Control
	if not equipment_view.visible:
		_fail("equipment button did not open the equipment tab")
		return
	var equipment_slot := _hud.side_panel.get_equipment_slots()[ArmorDefinition.Slot.HEAD]
	if equipment_slot.item_id != &"copper_helmet":
		_fail("helmet equipment UI did not refresh")
		return
	_push_double_click(equipment_slot)

func _check_armor_unequipped() -> void:
	if _inv.get_equipped_armor(ArmorDefinition.Slot.HEAD) != null:
		_fail("helmet double click did not unequip")
		return
	if _find_item_index(&"copper_helmet") < 0:
		_fail("unequipped helmet did not return to inventory")
		return
	if not is_equal_approx(_stats.get_value(&"defense"), 0.0):
		_fail("helmet unequip did not remove defense")
		return
	_hud.side_panel._switch_to_tab_id("inventory")
	print("[hud_integration] armor double click ok")

func _push_double_click(control: Control) -> void:
	var position := control.get_global_rect().get_center()
	var double_click := InputEventMouseButton.new()
	double_click.position = position
	double_click.global_position = position
	double_click.button_index = MOUSE_BUTTON_LEFT
	double_click.pressed = true
	double_click.button_mask = MOUSE_BUTTON_MASK_LEFT
	double_click.double_click = true
	root.push_input(double_click, true)
	var release := InputEventMouseButton.new()
	release.position = position
	release.global_position = position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)

func _push_left_click(control: Control) -> void:
	var position := control.get_global_rect().get_center()
	var press := InputEventMouseButton.new()
	press.position = position
	press.global_position = position
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press, true)
	var release := InputEventMouseButton.new()
	release.position = position
	release.global_position = position
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)

func _find_item_index(item_id: StringName) -> int:
	for index in range(_inv.size):
		var stack := _inv.get_slot(index)
		if stack != null and stack.item_id == item_id:
			return index
	return -1

func _start_closed_hotbar_click() -> void:
	_hud.close_side_panel_immediate()
	var hotbar_center := _hud.hotbar.slot_nodes[2].get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = hotbar_center
	motion.global_position = hotbar_center
	root.push_input(motion, true)
	var press := InputEventMouseButton.new()
	press.position = hotbar_center
	press.global_position = hotbar_center
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(press, true)

func _check_closed_hotbar_press_and_release() -> void:
	if _inv.selected_slot != 0:
		_fail("closed hotbar click: slot activated before mouse release")
		return
	var hotbar_center := _hud.hotbar.slot_nodes[2].get_global_rect().get_center()
	var release := InputEventMouseButton.new()
	release.position = hotbar_center
	release.global_position = hotbar_center
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release, true)

func _check_closed_hotbar_click_result() -> void:
	if _inv.selected_slot != 2:
		_fail("closed hotbar click: slot 3 was not activated")
		return
	var hotbar_stack := _inv.get_slot(2)
	var stone_id := _item_catalog.get_item_for_block(BlockId.Type.STONE).id
	if hotbar_stack == null or hotbar_stack.item_id != stone_id or hotbar_stack.count != 8:
		_fail("closed hotbar click: hotbar item moved")
		return
	print("[hud_integration] closed hotbar click activated slot")

func _find_drag_previews(node: Node, out: Array) -> void:
	if node.name.contains("DragPreview"):
		out.append(node)
	for c in node.get_children():
		_find_drag_previews(c, out)

func _check_final_and_quit() -> void:
	print("[hud_integration] final check")
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var previews: Array = []
	_find_drag_previews(root, previews)
	print("[hud_integration] final orphan=%d previews=%d" % [orphan, previews.size()])
	if orphan != 0:
		_fail("final orphan %d" % orphan)
		return
	if not previews.is_empty():
		_fail("final leaked previews %s" % str(previews))
		return
	if _errors.is_empty():
		print("HUD_INTEGRATION PASS orphan=%d previews=0" % orphan)
		quit(0)
	else:
		print("HUD_INTEGRATION FAIL %s" % str(_errors))
		quit(1)

func _warn(msg: String) -> void:
	print("[hud_integration] WARNING: %s" % msg)

func _error(msg: String) -> void:
	print("[hud_integration] ERROR: %s" % msg)

func _fail(msg: String) -> void:
	_error(msg)
	print("FAIL: %s" % msg)
	_errors.append(msg)
	quit(1)
