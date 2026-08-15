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

class TrackingTorchRenderer extends TorchRenderer:
	var shadow_refresh_count: int

	func _refresh_shadow_targets() -> void:
		shadow_refresh_count += 1
		super._refresh_shadow_targets()

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
	await _test_shadow_disabled_torch_updates()
	await _test_runtime()
	await _test_module_runtime()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _failures.is_empty():
		print("STRUCTURE_DESIGNER_RUNTIME PASS")
	return _failures.duplicate()

func _test_shadow_disabled_torch_updates() -> void:
	var renderer := TrackingTorchRenderer.new()
	_tree.root.add_child(renderer)
	renderer.setup(_block_catalog, 0, 0.0)
	var first_cell := Vector3i(1, 1, 1)
	var second_cell := Vector3i(2, 1, 1)
	var first_node := renderer.spawn_torch(first_cell, Vector3i.LEFT)
	renderer.spawn_torch(second_cell, Vector3i.LEFT)
	_expect(renderer.shadow_refresh_count == 0, "shadow-disabled torch additions performed a global shadow refresh")
	_expect(renderer.torch_instances.get(first_cell) == first_node, "second torch addition replaced the first torch node")
	renderer.remove_torch(second_cell)
	_expect(renderer.torch_instances.get(first_cell) == first_node, "torch removal replaced an unaffected torch node")
	renderer.queue_free()
	await _tree.process_frame

func _test_runtime() -> void:
	var draft := StructureDraft.create_generic(Vector3i(8, 4, 8))
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
	var metadata_overlay := runtime.get_node("StructureMetadataOverlay") as StructureMetadataOverlay
	_expect(runtime.visible and ui.visible, "activated runtime was not visible")
	_expect(metadata_overlay.get_child_count() == 0, "generic runtime created Level Module metadata geometry")
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
	runtime._input(tab)
	_expect(ui.is_palette_open() and ui.is_ui_blocking(), "Tab did not open the creative palette")
	_expect(not controller._input_enabled and not controller._mouse_capture_enabled, "open palette did not release designer control")
	_expect(runtime.cancel_active_ui(), "cancellation hook did not consume the open palette")
	_expect(not ui.is_palette_open() and controller._input_enabled, "cancellation hook did not restore designer control")
	_expect(not runtime.cancel_active_ui(), "cancellation hook consumed without active UI")
	_toggle_module_tools(runtime)
	_expect(not ui.is_module_panel_open() and controller._input_enabled and controller._mouse_capture_enabled, "generic M opened or blocked Level Module tools")
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
	var first_support := Vector3i(3, 1, 3)
	var first_torch := Vector3i(4, 1, 3)
	var second_support := Vector3i(5, 1, 5)
	var second_torch := Vector3i(6, 1, 5)
	runtime._apply_change(draft.try_place_block(first_support, BlockId.Type.STONE))
	runtime._apply_change(draft.try_place_block(second_support, BlockId.Type.STONE))
	runtime._apply_change(draft.try_place_torch(first_torch, Vector3i.LEFT))
	runtime._apply_change(draft.try_place_torch(second_torch, Vector3i.LEFT))
	var retained_torch_node := torch_renderer.torch_instances.get(second_torch) as Node3D
	_expect(torch_renderer.has_torch(first_torch) and retained_torch_node != null, "incremental torch fixture did not render both torches")
	runtime._apply_change(draft.try_remove_block(first_support))
	_expect(not torch_renderer.has_torch(first_torch), "support removal retained its rendered torch")
	_expect(torch_renderer.torch_instances.get(second_torch) == retained_torch_node, "torch edit rebuilt an unaffected torch node")
	await _free_runtime(runtime)

func _test_module_runtime() -> void:
	var draft := StructureDraft.create_level_module(Vector3i(32, 8, 7))
	_expect(draft != null, "Level Module draft creation failed")
	if draft == null:
		return
	_build_boundary_wall(draft, LevelSocketDefinition.Direction.NORTH)
	_build_boundary_wall(draft, LevelSocketDefinition.Direction.SOUTH)
	for y in range(1, 7):
		for x in range(2, 5):
			_expect(draft.try_remove_block(Vector3i(x, y, 6)).succeeded, "large south opening setup failed")
	for cell in [
		Vector3i(1, 0, 2),
		Vector3i(2, 0, 2),
		Vector3i(5, 0, 4),
		Vector3i(1, 0, 4),
		Vector3i(1, 1, 4),
		Vector3i(1, 2, 4),
		Vector3i(20, 1, 5),
	]:
		_expect(draft.try_place_block(cell, BlockId.Type.STONE).succeeded, "Level Module runtime seed failed at %s" % cell)
	var carved_torch := Vector3i(3, 2, 1)
	var retained_torch := Vector3i(1, 1, 5)
	_expect(draft.try_place_torch(carved_torch, Vector3i.FORWARD).succeeded, "socket-support torch seed failed")
	_expect(draft.try_place_torch(retained_torch, Vector3i.FORWARD).succeeded, "unrelated torch seed failed")
	_expect(draft.try_set_weight(3.25).succeeded, "Level Module weight seed failed")
	var snapshot := StructureResourceAdapter.create_snapshot(draft, &"runtime_module") as LevelModuleDefinition
	draft = StructureResourceAdapter.create_draft(snapshot, "/tmp/runtime_module.tres")
	_expect(draft != null and draft.get_weight() == 3.25, "Level Module runtime fixture did not round-trip its exact weight")
	if draft == null:
		return
	var runtime := await _create_runtime(draft)
	if runtime == null:
		return
	var controller := runtime.get_node("StructureDesignerController") as StructureDesignerController
	var ui := runtime.get_node("StructureDesignerUI") as StructureDesignerUI
	var overlay := runtime.get_node("StructureMetadataOverlay") as StructureMetadataOverlay
	var torch_renderer := runtime.get_node("TorchRenderer") as TorchRenderer
	var module_panel := ui.get_node("ModulePanel") as PanelContainer
	var module_tools_hint := ui.get_node("ModuleToolsHint") as Label
	var socket_list := ui.get_node("ModulePanel/Margin/VBox/SocketScroll/SocketList") as VBoxContainer
	var weight_input := ui.get_node("ModulePanel/Margin/VBox/WeightRow/Weight") as SpinBox
	var retained_torch_node := torch_renderer.torch_instances.get(retained_torch) as Node3D
	_expect(not module_panel.visible and module_tools_hint.visible, "Level Module runtime did not start in build mode")
	_expect(weight_input.value == 3.25, "Level Module runtime quantized an imported weight")
	_expect(overlay.get_child_count() == 0, "empty Level Module created metadata geometry")
	_expect(torch_renderer.has_torch(carved_torch) and retained_torch_node != null, "Level Module runtime omitted seeded torches")
	_aim_at(controller, Vector3(1.5, 3.0, 2.5), Vector3(1.5, 0.5, 2.5))
	runtime._process(0.0)
	_aim_at(controller, Vector3(2.5, 3.0, 2.5), Vector3(2.5, 0.5, 2.5))
	_toggle_module_tools(runtime)
	_expect(ui.is_module_panel_open() and module_panel.visible and not module_tools_hint.visible, "M did not open Level Module tools")
	_expect(not controller._input_enabled and not controller._mouse_capture_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Level Module tools did not release first-person input and cursor")
	var blocked_cells := draft.snapshot_cells()
	_click(runtime, MOUSE_BUTTON_RIGHT)
	_expect(draft.snapshot_cells() == blocked_cells, "open Level Module tools allowed a world click")
	(ui.get_node("ModulePanel/Margin/VBox/SetVoid") as Button).pressed.emit()
	_expect(draft.get_cell(Vector3i(2, 0, 2)) == StructureCell.VOID, "Level Module tools used a stale target instead of the centered target captured on open")
	_expect(draft.get_cell(Vector3i(1, 0, 2)) == BlockId.Type.STONE, "Level Module VOID action changed the stale target")
	weight_input.value = 0.0
	_expect(draft.get_weight() == 3.25 and weight_input.value == 3.25, "rejected weight input diverged from draft truth")
	_expect(runtime.cancel_active_ui(), "Esc cancellation hook did not consume Level Module tools")
	_expect(not ui.is_module_panel_open() and controller._input_enabled and controller._mouse_capture_enabled, "Esc cancellation did not restore first-person build mode")
	var distant_chunk_before := _chunk_mesh_id(runtime, Vector3i(1, 0, 0))
	_toggle_module_tools(runtime)
	(ui.get_node("ModulePanel/Margin/VBox/ConnectionHeader/PlaceConnections") as Button).pressed.emit()
	var connection_hint := ui.get_node("ConnectionModeHint") as Label
	_expect(not module_panel.visible and connection_hint.visible, "connection action did not enter first-person targeting mode")
	_expect(controller._input_enabled and controller._mouse_capture_enabled, "connection targeting did not restore first-person controls")

	_aim_at(controller, Vector3(3.5, 0.0, 3.5), Vector3(1.5, 1.5, 4.5))
	runtime._process(0.0)
	var connection_preview := runtime.get_node("StructureDesignerGuideView/ConnectionPreview") as MultiMeshInstance3D
	_expect(connection_preview.visible and connection_preview.multimesh.instance_count == 2, "invalid connection target did not show a two-block preview")
	_click(runtime, MOUSE_BUTTON_LEFT)
	_expect(draft.get_sockets().is_empty() and draft.get_cell(Vector3i(1, 1, 4)) == BlockId.Type.STONE, "invalid connection click mutated the module")
	_expect(connection_hint.visible, "invalid connection click exited targeting mode")

	_aim_at(controller, Vector3(3.5, 0.0, 3.5), Vector3(3.5, 1.5, 0.5))
	runtime._process(0.0)
	var north_hit := controller.get_centered_raycast()
	_expect(north_hit != null and north_hit.target_cell == Vector3i(3, 1, 0) and north_hit.face_normal == Vector3i.BACK, "inside north-wall targeting fixture is invalid")
	_expect(connection_hint.text.contains("North 1×2 opening ready"), "inside north wall did not derive an outward north connection")
	_click(runtime, MOUSE_BUTTON_LEFT)
	var sockets := draft.get_sockets()
	_expect(sockets.size() == 1 and sockets[0].socket_id == &"north" and sockets[0].direction == LevelSocketDefinition.Direction.NORTH, "connection intent did not commit its boundary direction")
	_expect(draft.get_cell(Vector3i(3, 1, 0)) == StructureCell.AIR and draft.get_cell(Vector3i(3, 2, 0)) == StructureCell.AIR, "connection intent did not carve its two-block aperture")
	_expect(not torch_renderer.has_torch(carved_torch), "connection carving retained a torch whose support was removed")
	_expect(torch_renderer.torch_instances.get(retained_torch) == retained_torch_node, "connection carving rebuilt an unrelated torch node")
	_expect(_chunk_mesh_id(runtime, Vector3i(1, 0, 0)) == distant_chunk_before, "connection carving rebuilt an unrelated chunk")
	_expect(socket_list.get_child_count() == 1 and overlay.get_child_count() == 1 and overlay.has_node("Socket_north"), "connection metadata presentation did not refresh exactly once")
	_expect(not runtime._can_preview_placement(Vector3i(3, 1, 0), BlockId.Type.DIRT, Vector3i.FORWARD), "connection aperture presented an invalid block placement")
	var north_overlay := overlay.get_node("Socket_north/Aperture") as MultiMeshInstance3D
	_expect(north_overlay.multimesh.instance_count == 2, "north connection overlay did not present its complete aperture")
	_expect_overlay_color(overlay.get_node("Socket_north") as Node3D, StructureMetadataOverlay.SOCKET_COLOR, "connection")
	var socket_root := overlay.get_node("Socket_north") as Node3D
	weight_input.value = 0.0
	_expect(overlay.get_node("Socket_north") == socket_root and overlay.get_child_count() == 1, "rejected weight rebuilt or duplicated metadata geometry")
	_expect(connection_hint.visible, "first hallway end exited connection targeting")

	_aim_at(controller, Vector3(3.5, 0.0, 3.5), Vector3(3.5, 1.0, 6.5))
	runtime._process(0.0)
	var south_hit := controller.get_centered_raycast()
	_expect(south_hit != null and south_hit.target_cell == Vector3i(3, 0, 6) and south_hit.face_normal == Vector3i.UP, "open south-doorway floor targeting fixture is invalid")
	_expect(connection_hint.text.contains("South 3×6 opening ready"), "boundary floor did not recover the large south opening")
	_expect(connection_preview.visible and connection_preview.multimesh.instance_count == 18, "large south opening did not preview all aperture cells")
	var before_south_connection := draft.snapshot_cells()
	_click(runtime, MOUSE_BUTTON_LEFT)
	sockets = draft.get_sockets()
	_expect(sockets.size() == 2 and sockets[1].socket_id == &"south" and sockets[1].direction == LevelSocketDefinition.Direction.SOUTH, "second hallway end did not commit the south connection")
	_expect(draft.snapshot_cells() == before_south_connection and draft.get_socket_aperture_cells(&"south").size() == 18, "south connection changed or truncated its prebuilt opening")
	var south_overlay := overlay.get_node("Socket_south/Aperture") as MultiMeshInstance3D
	_expect(socket_list.get_child_count() == 2 and south_overlay.multimesh.instance_count == 18, "large south connection presentation did not refresh")
	_expect((socket_list.get_child(1).get_child(0) as Label).text.contains("3×6"), "large south connection size was absent from the panel")
	_expect(runtime.cancel_active_ui(), "Esc did not finish connection targeting")
	_expect(not connection_hint.visible and controller._input_enabled and controller._mouse_capture_enabled, "finishing connection targeting did not restore build mode")
	_expect(not runtime.cancel_active_ui(), "connection targeting cancellation left another UI layer open")

	_toggle_module_tools(runtime)
	weight_input.value = 2.7
	_expect(draft.get_weight() == 2.7 and weight_input.value == 2.7, "valid weight intent did not update exact draft and UI truth")
	_expect(overlay.get_child_count() == 2 and overlay.get_node("Socket_north") != socket_root, "metadata change did not refresh its overlays exactly once")
	socket_root = overlay.get_node("Socket_north") as Node3D
	var void_change := draft.try_set_void(Vector3i(6, 3, 6))
	runtime._apply_change(void_change)
	_expect(void_change.succeeded and overlay.get_node("Socket_north") == socket_root, "ordinary VOID edit rebuilt metadata presentation")
	(socket_list.get_child(0).get_child(1) as Button).pressed.emit()
	_expect(draft.get_sockets().size() == 1 and socket_list.get_child_count() == 1 and overlay.get_child_count() == 1, "connection removal changed unrelated domain or presentation state")
	_expect(draft.get_cell(Vector3i(3, 1, 0)) == StructureCell.AIR and draft.get_cell(Vector3i(3, 2, 0)) == StructureCell.AIR, "connection removal refilled its aperture")
	(socket_list.get_child(0).get_child(1) as Button).pressed.emit()
	_expect(draft.get_sockets().is_empty() and socket_list.get_child_count() == 0 and overlay.get_child_count() == 0, "final connection removal retained domain or presentation state")
	_toggle_module_tools(runtime)
	_expect(not ui.is_module_panel_open() and controller._input_enabled, "M did not close Level Module tools")
	_aim_at(controller, Vector3(1.5, 3.0, 2.5), Vector3(1.5, 0.5, 2.5))
	_toggle_module_tools(runtime)
	var spawn_facing := ui.get_node("ModulePanel/Margin/VBox/Markers/Spawn/Controls/Facing") as OptionButton
	spawn_facing.select(LevelSocketDefinition.Direction.EAST)
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Spawn/Controls/Set") as Button).pressed.emit()
	_toggle_module_tools(runtime)
	_aim_at(controller, Vector3(5.5, 3.0, 4.5), Vector3(5.5, 0.5, 4.5))
	_toggle_module_tools(runtime)
	var return_facing := ui.get_node("ModulePanel/Margin/VBox/Markers/Return/Controls/Facing") as OptionButton
	return_facing.select(LevelSocketDefinition.Direction.WEST)
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Return/Controls/Set") as Button).pressed.emit()
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Actions/Commit") as Button).pressed.emit()
	var spawn_marker := draft.get_spawn_marker()
	var return_marker := draft.get_return_door_marker()
	_expect(spawn_marker != null and spawn_marker.cell == Vector3i(1, 1, 2) and spawn_marker.facing == LevelSocketDefinition.Direction.EAST, "spawn marker target did not commit")
	_expect(return_marker != null and return_marker.cell == Vector3i(5, 1, 4) and return_marker.facing == LevelSocketDefinition.Direction.WEST, "return marker target did not commit")
	_expect(overlay.get_child_count() == 2 and overlay.has_node("SpawnMarker") and overlay.has_node("ReturnMarker"), "paired marker overlays did not refresh without duplicates")
	_expect_overlay_color(overlay.get_node("SpawnMarker") as Node3D, StructureMetadataOverlay.SPAWN_COLOR, "spawn marker")
	_expect_overlay_color(overlay.get_node("ReturnMarker") as Node3D, StructureMetadataOverlay.RETURN_COLOR, "return marker")
	(ui.get_node("ModulePanel/Margin/VBox/Markers/Actions/Clear") as Button).pressed.emit()
	_expect(draft.get_spawn_marker() == null and draft.get_return_door_marker() == null and overlay.get_child_count() == 0, "marker clear retained paired domain or overlay state")
	(ui.get_node("ModulePanel/Margin/VBox/Header/Close") as Button).pressed.emit()
	_expect(not ui.is_module_panel_open() and controller._input_enabled and controller._mouse_capture_enabled, "module close button did not restore first-person input")
	_expect(torch_renderer.torch_instances.get(retained_torch) == retained_torch_node, "metadata authoring rebuilt an unrelated torch node")
	_aim_at(controller, Vector3(1.5, 0.0, 6.5), Vector3(1.5, 1.5, 4.5))
	_click(runtime, MOUSE_BUTTON_LEFT)
	_expect(not draft.has_torch(retained_torch) and not torch_renderer.has_torch(retained_torch), "Level Module first-person removal did not remove its torch")
	_assign_torch_to_selected_slot(ui)
	_click(runtime, MOUSE_BUTTON_RIGHT)
	_expect(draft.has_torch(retained_torch) and torch_renderer.has_torch(retained_torch), "Level Module first-person placement did not restore its torch")
	await _free_runtime(runtime)

func _expect_overlay_color(root_node: Node3D, expected: Color, label: String) -> void:
	var meshes := root_node.find_children("*", "MeshInstance3D", true, false)
	_expect(not meshes.is_empty(), "%s overlay contained no geometry" % label)
	for node in meshes:
		var mesh := node as MeshInstance3D
		var material := mesh.material_override as StandardMaterial3D
		_expect(mesh.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s overlay geometry cast shadows" % label)
		_expect(material != null and material.emission_enabled and material.albedo_color.is_equal_approx(expected), "%s overlay color or emission changed" % label)

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

func _toggle_module_tools(runtime: StructureDesignerRuntime) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_M
	runtime._input(event)

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

func _build_boundary_wall(draft: StructureDraft, direction: LevelSocketDefinition.Direction) -> void:
	var size := draft.get_size()
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var cell := Vector3i(x, y, z)
				if not LevelSocketAperture.is_boundary(cell, size, direction) or StructureCell.is_structure_solid(draft.get_cell(cell)):
					continue
				_expect(draft.try_place_block(cell, BlockId.Type.STONE).succeeded, "runtime boundary wall setup failed at %s" % cell)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
