extends SceneTree

var _failures: Array[String] = []
var _selections: Array[int] = []
var _hotkey_requests: Array[int] = []
var _toggle_requests: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://inventory/ui/hotbar_view.tscn") as PackedScene
	_expect(scene != null, "hotbar view scene did not load")
	var hotbar := scene.instantiate() as HotbarView
	_expect(hotbar != null, "hotbar view scene did not instantiate")
	root.add_child(hotbar)
	hotbar.slot_selection_requested.connect(_on_slot_selection_requested)
	hotbar.slot_hotkey_requested.connect(_on_slot_hotkey_requested)
	hotbar.equipped_item_toggle_requested.connect(_on_equipped_item_toggle_requested)
	await process_frame
	_expect(hotbar.slot_nodes.size() == 9, "hotbar view did not build nine slots")
	for index in range(hotbar.slot_nodes.size()):
		var slot := hotbar.slot_nodes[index]
		_expect(slot.slot_index == index, "slot index %d was not assigned" % index)
		_expect(slot.key_label.text == str(index + 1), "slot %d shortcut label was not assigned" % index)
	var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	image.set_pixel(0, 0, Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	hotbar.present_slot(2, texture, 5)
	_expect(hotbar.slot_nodes[2].icon.texture == texture, "present_slot did not present the texture")
	_expect(hotbar.slot_nodes[2].count_label.text == "5", "present_slot did not present the count")
	hotbar.present_slot(3, texture, 8, false)
	_expect(hotbar.slot_nodes[3].icon.texture == texture, "count-free presentation lost the texture")
	_expect(hotbar.slot_nodes[3].count_label.text.is_empty(), "count-free presentation displayed a count")
	hotbar.clear_slot(2)
	_expect(hotbar.slot_nodes[2].icon.texture == null, "clear_slot retained the texture")
	hotbar.set_selected_slot(4)
	for index in range(hotbar.slot_nodes.size()):
		_expect(hotbar.slot_nodes[index].is_selected == (index == 4), "selected presentation diverged at slot %d" % index)
	var keyboard_selection := InputEventKey.new()
	keyboard_selection.pressed = true
	keyboard_selection.keycode = KEY_4
	hotbar._unhandled_key_input(keyboard_selection)
	_expect(_hotkey_requests == [3], "number key did not request slot 3")
	var physical_selection := InputEventKey.new()
	physical_selection.pressed = true
	physical_selection.physical_keycode = KEY_2
	hotbar._unhandled_key_input(physical_selection)
	_expect(_hotkey_requests == [3, 1], "physical number key did not request slot 1")
	var echo_selection := InputEventKey.new()
	echo_selection.pressed = true
	echo_selection.echo = true
	echo_selection.keycode = KEY_1
	hotbar._unhandled_key_input(echo_selection)
	_expect(_hotkey_requests == [3, 1], "echo key requested a slot")
	var toggle_equipped := InputEventKey.new()
	toggle_equipped.pressed = true
	toggle_equipped.physical_keycode = KEY_R
	hotbar._unhandled_key_input(toggle_equipped)
	_expect(_toggle_requests == 1, "R did not request an equipped-item toggle")
	hotbar.set_selection_input_enabled(false)
	hotbar._unhandled_key_input(keyboard_selection)
	hotbar._unhandled_key_input(toggle_equipped)
	hotbar.slot_nodes[5].request_selection()
	_expect(_hotkey_requests == [3, 1] and _toggle_requests == 1 and _selections.is_empty(), "disabled selection input requested a slot or toggle")
	hotbar.set_selection_input_enabled(true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	hotbar.slot_nodes[5]._gui_input(press)
	hotbar.slot_nodes[5]._gui_input(release)
	_expect(_selections == [5], "slot click did not request selection")
	hotbar.queue_free()
	await process_frame
	if _failures.is_empty():
		print("HOTBAR_VIEW PASS")
		quit(0)
	else:
		print("HOTBAR_VIEW FAIL %s" % str(_failures))
		quit(1)

func _on_slot_selection_requested(slot_index: int) -> void:
	_selections.append(slot_index)

func _on_slot_hotkey_requested(slot_index: int) -> void:
	_hotkey_requests.append(slot_index)

func _on_equipped_item_toggle_requested() -> void:
	_toggle_requests += 1

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures.append(message)
	push_error("[hotbar_view] %s" % message)
