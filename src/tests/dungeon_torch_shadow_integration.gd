extends SceneTree

const BLOCK_CATALOG_PATH: String = "res://blocks/block_catalog.tres"
const LEVEL_CATALOG_PATH: String = "res://levels/content/dungeons/stone/level_catalog.tres"
const LEVEL_RUNTIME_SCENE_PATH: String = "res://levels/runtime/level_runtime.tscn"
const SETTINGS_SCREEN_SCENE_PATH: String = "res://ui/screens/settings/settings_screen.tscn"
const SHADOW_LIMIT: int = 6
const SHADOW_TRANSITION_SECONDS: float = 0.45
const SHADOW_OPACITY: float = 0.5
const STEP_SECONDS: float = 0.01

var _failures: int = 0
var _assertions: int = 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load(BLOCK_CATALOG_PATH) as BlockCatalog
	_expect(block_catalog != null and block_catalog.validate(), "block catalog did not load or validate")
	if block_catalog == null:
		_finish()
		return
	await _test_settings()
	await _test_fading_shadow_pool(block_catalog)
	await _test_immediate_shadow_pool(block_catalog)
	await _test_torch_reveal_strength(block_catalog)
	await _test_level_runtime_setting(block_catalog)
	_finish()

func _test_settings() -> void:
	var settings := GameSettings.new()
	_expect(settings.torch_shadow_count == 1, "overworld torch shadow default changed")
	_expect(settings.dungeon_torch_shadow_count == SHADOW_LIMIT, "dungeon torch shadows do not default to six")
	var encoded := settings.to_dict()
	_expect(int(encoded.get("torch_shadow_count", -1)) == 1, "overworld torch shadow setting was not encoded")
	_expect(int(encoded.get("dungeon_torch_shadow_count", -1)) == SHADOW_LIMIT, "dungeon torch shadow setting was not encoded")
	var legacy_settings := GameSettings.new()
	legacy_settings._apply_dict({"torch_shadow_count": 2})
	_expect(legacy_settings.dungeon_torch_shadow_count == SHADOW_LIMIT, "settings without a dungeon value did not retain the six-shadow default")
	settings.dungeon_torch_shadow_count = 0
	var restored := GameSettings.new()
	restored._apply_dict(settings.to_dict())
	_expect(restored.dungeon_torch_shadow_count == 0, "dungeon torch shadow setting did not round-trip")
	_expect(restored.torch_shadow_count == 1, "dungeon setting round-trip changed the overworld setting")
	var settings_scene := load(SETTINGS_SCREEN_SCENE_PATH) as PackedScene
	_expect(settings_scene != null, "settings screen scene did not load")
	if settings_scene == null:
		return
	var settings_screen := settings_scene.instantiate() as SettingsScreen
	root.add_child(settings_screen)
	await process_frame
	var defaults := GameSettings.new()
	settings_screen.setup(defaults)
	var label := settings_screen.get_node_or_null("VBox/SettingsGrid/DungeonTorchShadowsLabel") as Label
	var option := settings_screen.get_node_or_null("VBox/SettingsGrid/DungeonTorchShadows") as OptionButton
	_expect(label != null and label.text.to_lower() == "dungeon torch shadows", "settings screen omitted the Dungeon Torch Shadows label")
	_expect(option != null, "settings screen omitted the dungeon torch shadow control")
	if option != null:
		var six_index := _find_option_value(option, SHADOW_LIMIT)
		var off_index := _find_option_value(option, 0)
		_expect(six_index >= 0, "dungeon torch shadow control omitted the six-shadow option")
		_expect(off_index >= 0, "dungeon torch shadow control omitted the off option")
		_expect(option.get_selected_id() >= 0 and int(option.get_item_metadata(option.selected)) == SHADOW_LIMIT, "dungeon torch shadow control did not sync the default")
		if off_index >= 0:
			option.select(off_index)
			option.item_selected.emit(off_index)
			_expect(defaults.dungeon_torch_shadow_count == 0, "dungeon torch shadow control did not update settings")
			_expect(defaults.torch_shadow_count == 1, "dungeon torch shadow control changed the overworld setting")
	settings_screen.queue_free()
	await process_frame
	await process_frame

func _test_fading_shadow_pool(block_catalog: BlockCatalog) -> void:
	var fixture := _make_renderer_fixture(block_catalog, SHADOW_LIMIT, SHADOW_TRANSITION_SECONDS)
	var renderer := fixture["renderer"] as TorchRenderer
	var player := fixture["player"] as Node3D
	player.global_position = Vector3(-20.0, 0.0, 0.0)
	renderer.set_player_ref(player)
	_advance(renderer, 2.0)
	var initial_enabled := _enabled_positions(renderer)
	var expected_initial := _position_set(range(0, SHADOW_LIMIT))
	_expect(initial_enabled == expected_initial, "settled dungeon pool did not select the nearest six torches")
	_expect(_enabled_count(renderer) == SHADOW_LIMIT, "settled dungeon pool did not contain exactly six casters")
	_expect(_enabled_opacities_match(renderer, SHADOW_OPACITY), "initial dungeon shadows did not settle at full opacity")
	_expect(not renderer._shadow_transition_active, "settled dungeon pool retained per-frame transition work")
	player.global_position = Vector3(110.0, 0.0, 0.0)
	var expected_final := _position_set(range(10 - SHADOW_LIMIT, 10))
	var outgoing := _difference(initial_enabled, expected_final)
	var incoming := _difference(expected_final, initial_enabled)
	var outgoing_fade_observed := false
	var incoming_fade_observed := false
	var incoming_before_outgoing_disabled := false
	var peak_enabled := 0
	for step in range(220):
		renderer.update_shadow_culling(STEP_SECONDS)
		peak_enabled = maxi(peak_enabled, _enabled_count(renderer))
		var outgoing_enabled := false
		for position in outgoing:
			var light := renderer.torch_light_nodes.get(position) as OmniLight3D
			if light == null:
				continue
			if light.shadow_enabled:
				outgoing_enabled = true
				if light.shadow_opacity > 0.0 and light.shadow_opacity < SHADOW_OPACITY:
					outgoing_fade_observed = true
		for position in incoming:
			var light := renderer.torch_light_nodes.get(position) as OmniLight3D
			if light == null or not light.shadow_enabled:
				continue
			if outgoing_enabled:
				incoming_before_outgoing_disabled = true
			if light.shadow_opacity > 0.0 and light.shadow_opacity < SHADOW_OPACITY:
				incoming_fade_observed = true
	_expect(peak_enabled <= SHADOW_LIMIT, "dungeon handoff exceeded the six-caster budget")
	_expect(outgoing_fade_observed, "outgoing dungeon shadows did not fade out")
	_expect(incoming_fade_observed, "incoming dungeon shadows did not fade in")
	_expect(not incoming_before_outgoing_disabled, "incoming dungeon shadows activated before outgoing slots were released")
	_expect(_enabled_positions(renderer) == expected_final, "dungeon handoff did not settle on the nearest six torches")
	_expect(_enabled_opacities_match(renderer, SHADOW_OPACITY), "dungeon handoff did not settle at full opacity")
	_expect(not renderer._shadow_transition_active, "completed dungeon handoff retained per-frame transition work")
	renderer.set_max_shadow_torches(4)
	_advance(renderer, 1.5)
	_expect(_enabled_positions(renderer) == _position_set(range(6, 10)), "live four-shadow setting did not select the nearest four torches")
	renderer.set_max_shadow_torches(0)
	_advance(renderer, 1.0)
	_expect(_enabled_count(renderer) == 0, "live off setting retained dungeon shadow casters")
	await _free_renderer_fixture(fixture)

func _test_immediate_shadow_pool(block_catalog: BlockCatalog) -> void:
	var fixture := _make_renderer_fixture(block_catalog, 2, 0.0)
	var renderer := fixture["renderer"] as TorchRenderer
	var player := fixture["player"] as Node3D
	player.global_position = Vector3(-20.0, 0.0, 0.0)
	renderer.set_player_ref(player)
	_expect(_enabled_positions(renderer) == _position_set(range(0, 2)), "immediate pool did not select the nearest two torches")
	player.global_position = Vector3(110.0, 0.0, 0.0)
	_advance(renderer, TorchRenderer.TORCH_SHADOW_UPDATE_INTERVAL + STEP_SECONDS)
	_expect(_enabled_positions(renderer) == _position_set(range(8, 10)), "immediate pool did not switch directly to the nearest two torches")
	_expect(_enabled_opacities_match(renderer, SHADOW_OPACITY), "immediate pool introduced a dungeon fade")
	await _free_renderer_fixture(fixture)

func _test_torch_reveal_strength(block_catalog: BlockCatalog) -> void:
	var fixture := _make_renderer_fixture(block_catalog, 2, 0.0)
	var renderer := fixture["renderer"] as TorchRenderer
	var player := fixture["player"] as Node3D
	player.global_position = Vector3(-20.0, 0.0, 0.0)
	renderer.set_player_ref(player)
	var position := Vector3i.ZERO
	var torch_root := renderer.torch_instances.get(position) as Node3D
	var stem := torch_root.get_node("Stem") as MeshInstance3D
	var flame := torch_root.get_node("Flame") as MeshInstance3D
	var light := renderer.torch_light_nodes.get(position) as OmniLight3D
	var full_energy := light.light_energy
	_expect(stem.visible and flame.visible and light.visible, "fully revealed torch presentation was hidden")
	_expect(is_zero_approx(stem.transparency) and is_zero_approx(flame.transparency), "new torch did not default to fully revealed")
	_expect(renderer.set_torch_reveal_strength(position, 0.4), "existing torch rejected reveal strength")
	var flame_material := flame.material_override as StandardMaterial3D
	_expect(flame_material != renderer.torch_flame_material, "faded torch mutated the shared flame material")
	_expect(stem.visible and flame.visible and light.visible, "partially revealed torch presentation was hidden")
	_expect(is_equal_approx(stem.transparency, 0.6) and is_equal_approx(flame.transparency, 0.6), "partial reveal did not fade torch mesh alpha")
	_expect(is_equal_approx(flame_material.emission_energy_multiplier, full_energy * 0.4), "partial reveal did not fade torch emission")
	_expect(is_equal_approx(light.light_energy, full_energy * 0.4), "partial reveal did not fade torch light energy")
	_expect(renderer.set_torch_reveal_strength(position, 0.0), "existing torch rejected hidden strength")
	_expect(not stem.visible and not flame.visible and not light.visible, "zero-strength torch presentation remained visible")
	_expect(is_zero_approx(stem.transparency - 1.0) and is_zero_approx(flame.transparency - 1.0), "zero-strength torch mesh retained alpha")
	_expect(is_zero_approx(flame_material.emission_energy_multiplier) and is_zero_approx(light.light_energy), "zero-strength torch retained emission or light")
	_expect(not light.shadow_enabled and is_zero_approx(light.shadow_opacity), "zero-strength torch retained a shadow caster")
	renderer.update_shadow_culling(STEP_SECONDS)
	_expect(_enabled_positions(renderer) == _position_set(range(1, 3)), "hidden torch consumed a bounded shadow slot")
	_expect(renderer.set_torch_reveal_strength(position, 1.0), "hidden torch rejected full reveal")
	renderer.update_shadow_culling(STEP_SECONDS)
	_expect(stem.visible and flame.visible and light.visible, "restored torch presentation remained hidden")
	_expect(is_zero_approx(stem.transparency) and is_zero_approx(flame.transparency), "restored torch mesh retained transparency")
	_expect(is_equal_approx(flame_material.emission_energy_multiplier, full_energy) and is_equal_approx(light.light_energy, full_energy), "restored torch did not recover full energy")
	_expect(_enabled_positions(renderer) == _position_set(range(0, 2)), "restored torch did not reenter nearest shadow selection")
	_expect(not renderer.set_torch_reveal_strength(Vector3i(999, 999, 999), 0.5), "missing torch accepted reveal strength")
	await _free_renderer_fixture(fixture)

func _test_level_runtime_setting(block_catalog: BlockCatalog) -> void:
	var level_catalog := load(LEVEL_CATALOG_PATH) as LevelCatalog
	var runtime_scene := load(LEVEL_RUNTIME_SCENE_PATH) as PackedScene
	_expect(level_catalog != null and level_catalog.validate(), "level catalog did not load or validate")
	_expect(runtime_scene != null, "level runtime scene did not load")
	if level_catalog == null or runtime_scene == null:
		return
	var result := LevelGenerator.new().generate(level_catalog, &"stone_dungeon", 1337, &"shadow_test", Vector3i(7, 0, -9))
	_expect(result.succeeded, "dungeon shadow fixture generation failed: %s" % result.failure_reason)
	if not result.succeeded:
		return
	_expect(result.layout.torches.size() > SHADOW_LIMIT, "dungeon shadow fixture does not have enough authored torches")
	var runtime := runtime_scene.instantiate() as LevelRuntime
	root.add_child(runtime)
	await process_frame
	var settings := GameSettings.new()
	settings.torch_shadow_count = 0
	settings.dungeon_torch_shadow_count = SHADOW_LIMIT
	var item_catalog := load("res://items/item_catalog.tres") as ItemCatalog
	var inventory := InventoryModel.new(item_catalog, EquipmentInstanceFactory.new(item_catalog))
	inventory.setup_empty()
	var inventory_loadout := InventoryLoadoutCoordinator.new()
	assert(inventory_loadout.setup(
		inventory,
		ActorStats.new(load("res://player/player_stats.tres") as CombatStatsDefinition),
		ItemProficiency.new(item_catalog),
	))
	runtime.setup(
		result.layout,
		level_catalog.get_level(&"stone_dungeon"),
		result.layout.seed_value,
		result.layout.seed_value,
		&"shadow_test",
		DungeonProgressState.new(),
		block_catalog,
		BlockTextureSet.new(block_catalog),
		settings,
		load("res://entities/entity_catalog.tres") as EntityCatalog,
		inventory,
		inventory_loadout,
	)
	var player := (load("res://player/player.tscn") as PackedScene).instantiate() as PlayerMotor
	var camera := Camera3D.new()
	root.add_child(player)
	root.add_child(camera)
	player.global_position = runtime.get_spawn_position()
	runtime.set_player_context(player, camera)
	var renderer := runtime.get_node("Torches") as TorchRenderer
	_advance(renderer, 2.0)
	_expect(_enabled_count(renderer) == SHADOW_LIMIT, "LevelRuntime used the overworld torch shadow setting")
	settings.dungeon_torch_shadow_count = 0
	settings.torch_shadow_count = 4
	runtime.apply_settings(settings)
	_advance(renderer, 1.0)
	_expect(_enabled_count(renderer) == 0, "LevelRuntime live settings used the overworld torch shadow setting")
	player.queue_free()
	camera.queue_free()
	runtime.queue_free()
	await process_frame
	await process_frame

func _make_renderer_fixture(block_catalog: BlockCatalog, count: int, transition_seconds: float) -> Dictionary:
	var fixture_root := Node3D.new()
	var renderer := TorchRenderer.new()
	var player := Node3D.new()
	fixture_root.add_child(renderer)
	fixture_root.add_child(player)
	root.add_child(fixture_root)
	renderer.setup(block_catalog, count, transition_seconds)
	var attachments: Dictionary = {}
	for index in range(10):
		attachments[Vector3i(index * 10, 0, 0)] = Vector3i(0, 0, -1)
	_expect(renderer.spawn_torches(attachments) == attachments.size(), "bulk torch creation omitted authored torches")
	return {"root": fixture_root, "renderer": renderer, "player": player}

func _free_renderer_fixture(fixture: Dictionary) -> void:
	var fixture_root := fixture["root"] as Node3D
	fixture_root.queue_free()
	await process_frame
	await process_frame

func _advance(renderer: TorchRenderer, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var delta := minf(STEP_SECONDS, remaining)
		renderer.update_shadow_culling(delta)
		remaining -= delta

func _enabled_positions(renderer: TorchRenderer) -> Dictionary:
	var positions := {}
	for position in renderer.torch_light_nodes:
		var light := renderer.torch_light_nodes.get(position) as OmniLight3D
		if light != null and light.shadow_enabled:
			positions[position] = true
	return positions

func _enabled_count(renderer: TorchRenderer) -> int:
	return _enabled_positions(renderer).size()

func _enabled_opacities_match(renderer: TorchRenderer, expected: float) -> bool:
	for position in renderer.torch_light_nodes:
		var light := renderer.torch_light_nodes.get(position) as OmniLight3D
		if light != null and light.shadow_enabled and not is_equal_approx(light.shadow_opacity, expected):
			return false
	return true

func _position_set(indices: Variant) -> Dictionary:
	var positions := {}
	for index in indices:
		positions[Vector3i(int(index) * 10, 0, 0)] = true
	return positions

func _difference(left: Dictionary, right: Dictionary) -> Array[Vector3i]:
	var positions: Array[Vector3i] = []
	for position in left:
		if not right.has(position):
			positions.append(position as Vector3i)
	return positions

func _find_option_value(option: OptionButton, value: int) -> int:
	for index in range(option.item_count):
		if int(option.get_item_metadata(index)) == value:
			return index
	return -1

func _expect(condition: bool, message: String) -> void:
	_assertions += 1
	if condition:
		return
	_failures += 1
	print("[dungeon_torch_shadows] FAIL: %s" % message)

func _finish() -> void:
	if _failures == 0:
		print("DUNGEON_TORCH_SHADOWS PASS assertions=%d" % _assertions)
		quit(0)
	else:
		print("DUNGEON_TORCH_SHADOWS FAILED failures=%d assertions=%d" % [_failures, _assertions])
		quit(1)
