extends RefCounted

const RUNTIME_SCENE: String = "res://structures/runtime/structure_designer_runtime.tscn"
const TERRAIN_SHADER: String = "res://levels/presentation/level_terrain.gdshader"

var _failures: Array[String] = []
var _block_catalog: BlockCatalog
var _item_catalog: ItemCatalog
var _texture_set: BlockTextureSet
var _terrain_shader: Shader
var _runtime_scene: PackedScene
var _tree: SceneTree

func run(tree: SceneTree) -> Array[String]:
	_tree = tree
	_block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	_item_catalog = load("res://items/item_catalog.tres") as ItemCatalog
	_terrain_shader = load(TERRAIN_SHADER) as Shader
	_runtime_scene = load(RUNTIME_SCENE) as PackedScene
	_expect(_block_catalog != null and _block_catalog.validate(), "block catalog did not load")
	_expect(_item_catalog != null and _item_catalog.validate(_block_catalog), "item catalog did not load")
	_expect(_terrain_shader != null, "structure terrain shader did not load")
	_expect(_runtime_scene != null, "structure designer runtime scene did not load")
	if _block_catalog == null or _item_catalog == null or _terrain_shader == null or _runtime_scene == null:
		return _failures.duplicate()
	_texture_set = BlockTextureSet.new(_block_catalog)
	await _test_runtime()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _failures.is_empty():
		print("STRUCTURE_DESIGNER_RUNTIME PASS")
	return _failures.duplicate()

func _test_runtime() -> void:
	var draft := StructureDraft.create(Vector3i(8, 4, 8))
	_expect(draft != null, "draft creation failed")
	if draft == null:
		return
	_expect(draft.try_place_block(Vector3i(1, 1, 4), BlockId.Type.STONE).succeeded, "torch support seed failed")
	var runtime := await _create_runtime(draft)
	if runtime == null:
		return
	var controller := runtime.get_node("StructureDesignerController") as StructureDesignerController
	var ui := runtime.get_node("StructureDesignerUI") as StructureDesignerUI
	var guide := runtime.get_node("StructureDesignerGuideView") as StructureDesignerGuideView
	var torch_renderer := runtime.get_node("TorchRenderer") as TorchRenderer
	_expect(runtime.visible and ui.visible, "activated runtime was not visible")
	_expect(not runtime.has_node("StructureMetadataOverlay"), "generic runtime retained Level Module metadata presentation")
	_expect(controller.camera.current and controller.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "runtime camera was not active and perspective")
	var crosshair := ui.get_node("Crosshair") as Label
	_expect(crosshair.get_global_rect().get_center().is_equal_approx(_tree.root.get_visible_rect().get_center()), "runtime crosshair was not centered")
	var initial_hit := controller.get_centered_raycast()
	_expect(initial_hit != null, "initial centered ray did not hit the guide floor")
	if initial_hit != null:
		_expect(initial_hit.target_cell.y == -1 and initial_hit.face_normal == Vector3i.UP, "initial ray did not target the guide floor top")
		_expect(draft.is_in_bounds(initial_hit.placement_cell) and initial_hit.placement_cell.y == 0, "guide floor did not offer an initial placement")
		runtime._process(0.0)
		var preview := guide.get_node("PlacementPreview") as MeshInstance3D
		_expect(preview.visible and preview.position.is_equal_approx(Vector3(initial_hit.placement_cell) + Vector3.ONE * 0.5), "guide-floor preview was not centered")
		_click(runtime, MOUSE_BUTTON_LEFT)
		_expect(draft.get_cell(initial_hit.placement_cell) == StructureCell.AIR, "left click mutated the guide floor")
		var mesh_before := _chunk_mesh_id(runtime, Vector3i.ZERO)
		_click(runtime, MOUSE_BUTTON_RIGHT)
		_expect(draft.get_cell(initial_hit.placement_cell) == BlockId.Type.GRASS, "right click did not place the selected block")
		_expect(_chunk_mesh_id(runtime, Vector3i.ZERO) != mesh_before, "placement did not rebuild its chunk")
		_click(runtime, MOUSE_BUTTON_LEFT)
		_expect(draft.get_cell(initial_hit.placement_cell) == StructureCell.AIR, "left click did not remove the targeted block")
	runtime.set_external_ui_blocked(true)
	_expect(not controller._input_enabled and not controller._mouse_capture_enabled, "external UI did not release designer control")
	_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "external UI did not expose the mouse")
	runtime.set_external_ui_blocked(false)
	_expect(controller._input_enabled and controller._mouse_capture_enabled, "closing external UI did not restore designer control")
	var tab := InputEventKey.new()
	tab.pressed = true
	tab.keycode = KEY_TAB
	runtime._unhandled_input(tab)
	_expect(ui.is_palette_open() and ui.is_ui_blocking(), "Tab did not open the creative palette")
	_expect(not controller._input_enabled and not controller._mouse_capture_enabled, "open palette did not release designer control")
	_expect(runtime.cancel_active_ui(), "cancellation hook did not consume the open palette")
	_expect(not ui.is_palette_open() and controller._input_enabled, "cancellation hook did not restore designer control")
	_expect(not runtime.cancel_active_ui(), "cancellation hook consumed without active UI")
	_assign_torch_to_selected_slot(ui)
	var support_cell := Vector3i(1, 1, 4)
	var torch_cell := Vector3i(1, 1, 5)
	_aim_at(controller, Vector3(1.5, 0.0, 5.5), Vector3(support_cell) + Vector3.ONE * 0.5)
	_expect(controller.body_intersects_cell(torch_cell), "body-overlap fixture did not intersect the controller")
	_click(runtime, MOUSE_BUTTON_RIGHT)
	_expect(draft.get_torches().is_empty(), "right click placed a torch inside the controller")
	_aim_at(controller, Vector3(1.5, 0.0, 6.5), Vector3(support_cell) + Vector3.ONE * 0.5)
	_click(runtime, MOUSE_BUTTON_RIGHT)
	var torches := draft.get_torches()
	_expect(torches.size() == 1 and torches[0].cell == torch_cell and torches[0].support_direction == Vector3i.FORWARD, "torch placement did not derive wall support")
	_expect(torch_renderer.has_torch(torch_cell), "torch renderer did not present the committed torch")
	_click(runtime, MOUSE_BUTTON_LEFT)
	_expect(draft.get_torches().is_empty() and not torch_renderer.has_torch(torch_cell), "left click did not remove the targeted torch")
	_click(runtime, MOUSE_BUTTON_RIGHT)
	_aim_at(controller, Vector3(1.5, 0.0, 2.5), Vector3(support_cell) + Vector3.ONE * 0.5)
	_click(runtime, MOUSE_BUTTON_LEFT)
	_expect(draft.get_cell(support_cell) == StructureCell.AIR, "left click did not remove the torch support")
	_expect(draft.get_torches().is_empty() and not torch_renderer.has_torch(torch_cell), "support removal did not clean up its torch")
	await _free_runtime(runtime)

func _create_runtime(draft: StructureDraft) -> StructureDesignerRuntime:
	var runtime := _runtime_scene.instantiate() as StructureDesignerRuntime
	_expect(runtime != null, "structure designer runtime scene root had the wrong type")
	if runtime == null:
		return null
	_tree.root.add_child(runtime)
	await _tree.process_frame
	runtime.setup(draft, _block_catalog, _item_catalog, _texture_set, _terrain_shader)
	runtime.activate()
	await _tree.process_frame
	return runtime

func _free_runtime(runtime: StructureDesignerRuntime) -> void:
	runtime.set_external_ui_blocked(true)
	(runtime.get_node("StructureDesignerController") as StructureDesignerController).set_camera_active(false)
	runtime.queue_free()
	await _tree.process_frame
	await _tree.process_frame

func _click(runtime: StructureDesignerRuntime, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.pressed = true
	event.button_index = button
	runtime._unhandled_input(event)

func _aim_at(controller: StructureDesignerController, feet_position: Vector3, target: Vector3) -> void:
	controller.global_position = feet_position
	controller.rotation = Vector3.ZERO
	controller.pitch.rotation = Vector3.ZERO
	var camera_origin := feet_position + Vector3.UP * controller.pitch.position.y
	var direction := camera_origin.direction_to(target)
	controller.rotation.y = atan2(-direction.x, -direction.z)
	controller.pitch.rotation.x = asin(clampf(direction.y, -1.0, 1.0))

func _assign_torch_to_selected_slot(ui: StructureDesignerUI) -> void:
	ui.open_palette()
	var palette_grid := ui.get_node("PaletteOverlay/PalettePanel/Margin/VBox/Scroll/PaletteGrid") as GridContainer
	for button_value in palette_grid.get_children():
		var button := button_value as Button
		if button.name != "Item_torch":
			continue
		button.mouse_entered.emit()
		var assign := InputEventKey.new()
		assign.pressed = true
		assign.keycode = KEY_1
		ui._unhandled_key_input(assign)
		break
	ui.close_palette()

func _chunk_mesh_id(runtime: StructureDesignerRuntime, chunk: Vector3i) -> int:
	var renderer := runtime.get_node("StructureChunkRenderer") as StructureChunkRenderer
	var instance := renderer._chunks.get(chunk) as MeshInstance3D
	if instance == null or instance.mesh == null:
		return 0
	return instance.mesh.get_instance_id()

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
