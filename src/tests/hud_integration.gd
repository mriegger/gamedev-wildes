extends SceneTree

var _frame: int = 0
var _phase: int = 0
var _hud: HUD = null
var _inv: InventoryModel = null
var _errors: Array[String] = []
var _orphan_before: int = 0
var _src_center: Vector2 = Vector2.ZERO
var _dst_center: Vector2 = Vector2.ZERO
var _right_src_center: Vector2 = Vector2.ZERO
var _right_dst_center: Vector2 = Vector2.ZERO
var _left_start_frame: int = 0
var _right_start_frame: int = 0

func _init() -> void:
	print("[hud_integration] starting")
	_inv = InventoryModel.new()
	_inv.setup_starter()
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
		_hud.setup_with_camera(_inv, null)
		print("[hud_integration] hud added orphan=%d" % int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
		_phase = 1
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
		_hud.side_panel.open()
		print("[hud_integration] side panel open progress %f" % _hud.side_panel.get_progress())
		_phase = 2
	elif _phase == 2 and _frame >= 150:
		if _hud.side_panel.get_progress() < 0.95:
			if _frame < 170:
				return false
			_fail("panel not open %f" % _hud.side_panel.get_progress())
			return false
		var src_slot: Control = _hud.hotbar.slot_nodes[0] as Control
		var inv_slots: Array[InventorySlot] = _hud.side_panel.get_inventory_slots()
		if inv_slots.is_empty():
			_fail("no inventory slots")
			return false
		var dst_slot: Control = inv_slots[0] as Control
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
		if inv_slots2.size() < 2:
			_fail("not enough backpack slots for right test")
			return false
		var dst_slot2: Control = inv_slots2[1] as Control
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
		_check_final_and_quit()
	return false

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
			d[s["type"]] = d.get(s["type"], 0) + int(s["count"])
	return d

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
	var s0 = _inv.get_slot(0)
	var s9 = _inv.get_slot(9)
	print("[hud_integration] slot0 %s slot9 %s" % [str(s0), str(s9)])
	if s0 != null:
		_fail("left drag: slot 0 should be null after move but got %s" % str(s0))
		return
	if s9 == null or s9["type"] != BlockId.Type.GRASS or int(s9["count"]) != 12:
		_fail("left drag: slot 9 expected grass 12 got %s" % str(s9))
		return
	var n0: HotbarSlot = _hud.hotbar.slot_nodes[0] as HotbarSlot
	if n0.item_type != null:
		_fail("left drag: hotbar node 0 should be null")
		return
	var inv_node: InventorySlot = _hud.side_panel.get_inventory_slots()[0]
	if inv_node.item_type != BlockId.Type.GRASS or inv_node.item_count != 12:
		_fail("left drag: inventory node mismatch %s %d" % [str(inv_node.item_type), inv_node.item_count])
		return
	var totals: Dictionary = _totals(_inv)
	if totals.get(BlockId.Type.GRASS, 0) != 12 or totals.get(BlockId.Type.STONE, 0) != 8 or totals.get(BlockId.Type.TORCH, 0) != 16:
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
	var s10 = _inv.get_slot(10)
	print("[hud_integration] slot6 %s slot10 %s" % [str(s6), str(s10)])
	if s6 == null or int(s6["count"]) != 8 or s6["type"] != BlockId.Type.TORCH:
		_fail("right drag: slot6 expected torch 8 got %s" % str(s6))
		return
	if s10 == null or int(s10["count"]) != 8 or s10["type"] != BlockId.Type.TORCH:
		_fail("right drag: slot10 expected torch 8 got %s" % str(s10))
		return
	var n6: HotbarSlot = _hud.hotbar.slot_nodes[6] as HotbarSlot
	if n6.item_count != 8 or n6.item_type != BlockId.Type.TORCH:
		_fail("right drag: hotbar node6 mismatch")
		return
	var inv_node: InventorySlot = _hud.side_panel.get_inventory_slots()[1]
	if inv_node.item_type != BlockId.Type.TORCH or inv_node.item_count != 8:
		_fail("right drag: inventory node1 mismatch")
		return
	for i in range(_inv.size):
		var s = _inv.get_slot(i)
		if s != null:
			if int(s["count"]) <= 0 or (_inv.max_stack > 0 and int(s["count"]) > _inv.max_stack):
				_fail("right drag: invariant at %d" % i)
				return
			if not _inv.can_slot_accept_type(i, s["type"]):
				_fail("right drag: slot %d not accepted" % i)
				return
	print("[hud_integration] right drag ok")

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
