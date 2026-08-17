extends Node3D
class_name Game

const LEVEL_FADE_SECONDS: float = 0.18

signal loading_progress(stage: String, percent: float, details: String)
signal session_ready
signal main_menu_requested

@export var pause_menu_scene: PackedScene
@export var animation_tuning_panel_scene: PackedScene
@export var player_stats_debug_panel_scene: PackedScene
@export var player_death_screen_scene: PackedScene
@export var block_catalog: BlockCatalog
@export var item_catalog: ItemCatalog
@export var crafting_recipe_catalog: CraftingRecipeCatalog
@export var entity_catalog: EntityCatalog
@export var combat_hit_particle_catalog: CombatHitParticleCatalog
@export var player_stats_definition: CombatStatsDefinition
@export var level_catalog: LevelCatalog
@export var level_entrance_definition: LevelEntranceDefinition
@export var level_runtime_scene: PackedScene
@export var structure_designer_runtime_scene: PackedScene
@export var structure_terrain_shader: Shader

@onready var world: WorldController = $World as WorldController
@onready var player: PlayerMotor = $Player as PlayerMotor
@onready var camera_rig: CameraRig = $CameraRig as CameraRig
@onready var game_environment: GameEnvironment = $Environment as GameEnvironment
@onready var entity_coordinator: EntityCoordinator = $Entities as EntityCoordinator
@onready var melee_combat: MeleeCombatCoordinator = $MeleeCombat as MeleeCombatCoordinator
@onready var combat_hit_particles: CombatHitParticles = $CombatHitParticles as CombatHitParticles
@onready var hud: HUD = $HUD as HUD
@onready var dev_console: DevConsole = $DevConsole as DevConsole
@onready var game_session: GameSession = $GameSession as GameSession
@onready var mining_break_particles: MiningBreakParticles = $MiningBreakParticles as MiningBreakParticles
@onready var mining_hit_particles: MiningHitParticles = $MiningHitParticles as MiningHitParticles
@onready var level_interaction: LevelInteractionCoordinator = $LevelInteractionCoordinator as LevelInteractionCoordinator
@onready var structure_designer_workflow: StructureDesignerWorkflow = $StructureDesignerWorkflow as StructureDesignerWorkflow
@onready var structure_designer_dialogs: StructureDesignerDialogs = $StructureDesignerDialogs as StructureDesignerDialogs
@onready var _save_canvas: CanvasLayer = $SaveStatusLayer as CanvasLayer
@onready var _save_label: Label = $SaveStatusLayer/SaveStatusLabel as Label
@onready var _fade: ColorRect = $TransitionLayer/Fade as ColorRect

var inventory_model: InventoryModel
var player_stats: ActorStats
var item_proficiency: ItemProficiency
var inventory_stat_coordinator: InventoryStatCoordinator
var crafting_coordinator: CraftingCoordinator
var combat_progression_coordinator: CombatProgressionCoordinator
var rune_socketing_coordinator: RuneSocketingCoordinator
var rune_effect_coordinator: RuneEffectCoordinator
var input_buffer: InputBuffer = InputBuffer.new()
var settings: GameSettings

var _slot_id: int = -1
var _save_data: Dictionary = {}
var _world_state: WorldState
var _location_state: GameplayLocationState
var _pause_menu: PauseMenu
var _death_screen: PlayerDeathScreen
var _level_entrance: LevelEntrance
var _level_runtime: LevelRuntime
var _entrance_coordinate: Vector3i
var animation_tuning_panel: AnimationTuningPanel = null
var player_stats_debug_panel: PlayerStatsDebugPanel = null
var _save_status_timer: float = 0.0
var _session_active: bool = false
var _recovered_defeated_save: bool = false
var _level_transitioning: bool = false
var _structure_transitioning: bool = false
var _structure_designer_runtime: StructureDesignerRuntime
var _structure_lifecycle_snapshot: StructureDesignerLifecycleSnapshot

func configure_session(slot_id: int, save_data: Dictionary, p_settings: GameSettings):
	_slot_id = slot_id
	_save_data = save_data
	settings = p_settings
	_world_state = SaveManager.decode_world_state(save_data)

func _ready():
	set_physics_process(false)
	set_process_unhandled_input(false)
	var block_catalog_valid := block_catalog.validate()
	var item_catalog_valid := item_catalog.validate(block_catalog)
	var crafting_catalog_valid := crafting_recipe_catalog.validate(item_catalog)
	var entity_catalog_valid := entity_catalog.validate()
	var combat_particle_catalog_valid := combat_hit_particle_catalog.validate(entity_catalog)
	var player_stats_valid := player_stats_definition.validate()
	var level_catalog_valid := level_catalog.validate()
	var level_entrance_valid := level_catalog_valid and level_entrance_definition != null and level_entrance_definition.validate(level_catalog)
	if not block_catalog_valid or not item_catalog_valid or not crafting_catalog_valid or not entity_catalog_valid or not combat_particle_catalog_valid or not player_stats_valid or not level_catalog_valid or not level_entrance_valid:
		push_error("[Game] Catalog validation failed")
		return
	structure_designer_workflow.setup(structure_designer_dialogs)
	structure_designer_workflow.designer_entry_requested.connect(_on_structure_designer_entry_requested)
	structure_designer_workflow.designer_exit_requested.connect(_on_structure_designer_exit_requested)
	structure_designer_dialogs.open_state_changed.connect(_on_structure_dialog_open_state_changed)
	dev_console.open_state_changed.connect(_on_dev_console_open_state_changed)
	settings.apply_display(get_viewport())
	game_environment.setup(float(_save_data.get("time_of_day", 6.0)), settings.get_shadow_distance())
	game_environment.apply_settings(settings)
	world.block_catalog = block_catalog
	world.configure_settings(settings)
	inventory_model = InventoryModel.new(item_catalog)
	dev_console.setup(
		inventory_model,
		Callable(self, "_request_new_structure"),
		Callable(self, "_request_exit_structure")
	)
	player_stats = ActorStats.new(player_stats_definition)
	item_proficiency = ItemProficiency.new(item_catalog)
	_restore_inventory()
	_restore_item_proficiency()
	rune_socketing_coordinator = RuneSocketingCoordinator.new()
	if not rune_socketing_coordinator.setup(inventory_model, item_proficiency):
		push_error("[Game] Saved rune socket state is invalid")
		return
	inventory_stat_coordinator = InventoryStatCoordinator.new()
	if not inventory_stat_coordinator.setup(inventory_model, player_stats):
		push_error("[Game] Equipment modifiers are invalid")
		return
	rune_effect_coordinator = RuneEffectCoordinator.new()
	if not rune_effect_coordinator.setup(inventory_model, player_stats):
		push_error("[Game] Socketed rune modifiers are invalid")
		return
	crafting_coordinator = CraftingCoordinator.new()
	crafting_coordinator.setup(inventory_model, crafting_recipe_catalog)
	_restore_player_stats()
	combat_progression_coordinator = CombatProgressionCoordinator.new()
	combat_progression_coordinator.setup(player_stats, inventory_model, entity_catalog, item_proficiency)
	world.configure_start_state(_world_state)
	world.generation_progress.connect(_on_generation_progress)
	await world.initialize_world_async()
	world.generation_progress.disconnect(_on_generation_progress)
	_setup_gameplay()
	level_interaction.setup(player, hud, Callable(self, "_is_gameplay_ui_blocked"))
	level_interaction.interaction_requested.connect(_on_level_interaction_requested)
	_setup_level_entrance()
	game_session.save_status_changed.connect(_show_save_status)
	game_session.setup(_slot_id, _save_data, world, player_stats, inventory_model, item_proficiency, game_environment, _get_persisted_position)
	if _recovered_defeated_save and _slot_id != -1 and not game_session.save("defeated_save_recovery"):
		push_error("[Game] Failed to persist recovered player state")
	_recovered_defeated_save = false
	_session_active = true
	_refresh_save_label()
	if _level_entrance == null:
		_show_save_status("Dungeon unavailable")
	set_physics_process(true)
	set_process_unhandled_input(true)
	session_ready.emit()

func _restore_inventory():
	var saved_inventory = _save_data.get("inventory", null)
	if saved_inventory is Dictionary and not saved_inventory.is_empty():
		if not inventory_model.from_dict(saved_inventory):
			push_error("[Game] Saved inventory is invalid; using an empty inventory")
			inventory_model.setup_empty()
			return
		if not inventory_model.migrate_starter_items():
			push_warning("[Game] Starter item migration deferred because inventory is full")
	else:
		inventory_model.setup_empty()

func _restore_player_stats():
	var saved_stats = _save_data.get("player_stats", null)
	if not saved_stats is Dictionary:
		return
	if not player_stats.restore_progression(saved_stats):
		push_error("[Game] Saved player stats are invalid; using base progression")
		return
	if not player_stats.is_dead():
		return
	var health_restored := player_stats.set_current_hp(player_stats.get_value(&"hp"))
	assert(health_restored)
	_recovered_defeated_save = true
	_world_state.player_position = Vector3.ZERO
	_save_data["player_position"] = null
	_save_data["player_stats"] = player_stats.snapshot_progression()

func _restore_item_proficiency():
	var saved_proficiency = _save_data.get("item_proficiency", null)
	if saved_proficiency is Dictionary and not item_proficiency.restore(saved_proficiency):
		push_error("[Game] Saved item proficiency is invalid; using base proficiency")

func _setup_gameplay():
	camera_rig.setup(player, input_buffer)
	entity_coordinator.setup(entity_catalog, world.voxel_model, world.config.seed_value, world.is_position_streamed)
	melee_combat.setup(world.voxel_model, player, player_stats, entity_coordinator)
	entity_coordinator.entity_melee_contact_reached.connect(melee_combat.try_commit_entity_contact)
	melee_combat.melee_outcome_committed.connect(entity_coordinator.record_melee_outcome)
	melee_combat.melee_outcome_committed.connect(combat_progression_coordinator.record_melee_outcome)
	melee_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)
	combat_hit_particles.setup(melee_combat, combat_hit_particle_catalog)
	player.setup(camera_rig, inventory_model, input_buffer, player_stats, melee_combat, entity_coordinator)
	player_stats.health_depleted.connect(_on_player_defeated)
	var mining_particle_tints := MiningParticleTintPalette.new(block_catalog)
	mining_break_particles.setup(world.voxel_model, mining_particle_tints)
	mining_hit_particles.setup(player.animation_driver, player.interactor, mining_particle_tints)
	camera_rig.reset_panel_obstruction()

	game_environment.sky_color_changed.connect(world.update_water_tint)
	game_environment.start_clock()
	hud.setup_with_camera(inventory_model, inventory_stat_coordinator, crafting_coordinator, crafting_recipe_catalog, camera_rig, player_stats, item_proficiency)
	hud.setup_socketing(inventory_model, rune_socketing_coordinator, item_proficiency)

	var world_spawn := world.voxel_model.get_spawn_position()
	var saved_position = _world_state.player_position
	if saved_position != Vector3.ZERO:
		player.global_position = saved_position + Vector3(0, 0.2, 0)
	else:
		player.global_position = world_spawn + Vector3(0, 0.1, 0)
	player.bind_space(world.voxel_model, world, world_spawn, world.voxel_model)
	_location_state = GameplayLocationState.new(player.global_position)
	world.set_player_ref(player)
	camera_rig.snap_to_follow_target()
	camera_rig.current_yaw_deg = camera_rig.target_yaw_deg
	camera_rig.camera.current = true

func _on_player_defeated():
	if _death_screen != null and is_instance_valid(_death_screen):
		return
	game_session.suspend_saving()
	player.enter_defeated_state()
	camera_rig.set_gameplay_input_enabled(false)
	hud.close_side_panel_immediate()
	hud.hotbar.set_gameplay_selection_enabled(false)
	dev_console.close()
	game_environment.close_debug_panel()
	if animation_tuning_panel != null and animation_tuning_panel.is_open():
		animation_tuning_panel.hide_panel()
	if player_stats_debug_panel != null and player_stats_debug_panel.is_open():
		player_stats_debug_panel.hide_panel()
	_death_screen = player_death_screen_scene.instantiate() as PlayerDeathScreen
	assert(_death_screen != null)
	_death_screen.respawn_requested.connect(_on_respawn_requested)
	_death_screen.main_menu_requested.connect(_save_and_request_main_menu)
	add_child(_death_screen)

func _on_respawn_requested():
	if _death_screen == null or not is_instance_valid(_death_screen):
		return
	var completed_screen := _death_screen
	_death_screen = null
	_restore_player_from_defeat()
	completed_screen.queue_free()

func _restore_player_from_defeat():
	if player.is_defeated() or player.stats.is_dead():
		player.respawn_at(world.voxel_model.get_spawn_position() + Vector3(0.0, 0.1, 0.0))
		camera_rig.snap_to_follow_target()
	camera_rig.set_gameplay_input_enabled(true)
	hud.hotbar.set_gameplay_selection_enabled(true)
	game_environment.restore_debug_panel_input()
	game_session.resume_saving()

func _on_melee_outcome_committed(outcome: MeleeOutcome):
	if outcome.contact.target_runtime_id == MeleeCombatCoordinator.PLAYER_RUNTIME_ID:
		hud.play_player_hit()

func _setup_level_entrance():
	var world_spawn := world.voxel_model.get_spawn_position()
	var entrance_position = LevelEntrancePlacement.find_position(world.voxel_model, world_spawn, world.config.seed_value)
	if entrance_position == null:
		return
	var position := entrance_position as Vector3
	if LevelEntrancePlacement.has_edit_conflict(world.voxel_model, position):
		return
	_entrance_coordinate = Vector3i(floori(position.x), floori(position.y), floori(position.z))
	world.voxel_model.protect_edit_cells(LevelEntrancePlacement.get_protected_cells(position))
	_level_entrance = LevelEntrance.new()
	add_child(_level_entrance)
	_level_entrance.setup(position, world_spawn, block_catalog, level_entrance_definition)
	_show_world_level_interaction()

func _on_generation_progress(stage: String, percent: float, details: String):
	loading_progress.emit(stage, percent, details)

func _show_save_status(text: String):
	_save_label.text = text
	_save_status_timer = 2.5
	_save_canvas.visible = true

func _refresh_save_label():
	_save_label.text = game_session.get_summary()

func _process(delta):
	if _save_status_timer <= 0.0:
		return
	_save_status_timer -= delta
	if _save_status_timer <= 0.0:
		_save_canvas.visible = false

func _physics_process(delta):
	if _level_transitioning or _structure_transitioning or _structure_designer_runtime != null:
		input_buffer.clear_gameplay()
		return
	if player.is_defeated():
		input_buffer.clear_gameplay()
	else:
		if OS.is_debug_build() and Input.is_action_just_pressed("toggle_animation_tuner"):
			_toggle_animation_tuning_panel()
		input_buffer.poll()
		if dev_console.is_open() or structure_designer_workflow.is_dialog_open() or (animation_tuning_panel != null and animation_tuning_panel.is_open()):
			input_buffer.clear_gameplay()
	if _location_state != null:
		_location_state.update_world_position(player.global_position)
	if _location_state == null or not _location_state.is_in_level():
		entity_coordinator.tick(delta, player.global_position, game_environment.get_time_of_day())

func _on_level_interaction_requested():
	if _level_transitioning or _structure_transitioning or _structure_designer_runtime != null or _location_state == null:
		return
	if _location_state.is_in_level():
		_exit_level()
	else:
		_enter_level()

func _enter_level():
	_level_transitioning = true
	level_interaction.clear_target()
	var result := LevelGenerator.new().generate(level_catalog, level_entrance_definition.level_id, world.config.seed_value, level_entrance_definition.entrance_id, _entrance_coordinate)
	if not result.succeeded:
		_show_save_status("Dungeon unavailable")
		_show_world_level_interaction()
		_level_transitioning = false
		return
	var next_runtime := level_runtime_scene.instantiate() as LevelRuntime
	add_child(next_runtime)
	var definition := level_catalog.get_level(level_entrance_definition.level_id)
	next_runtime.setup(result.layout, definition, block_catalog, world.block_texture_set, settings)
	next_runtime.set_player_ref(player)
	var return_position := player.global_position
	player.set_physics_process(false)
	input_buffer.clear_gameplay()
	await _fade_to(1.0)
	player.unbind_space()
	_location_state.enter_level(return_position)
	world.suspend()
	entity_coordinator.suspend()
	_level_entrance.visible = false
	game_environment.set_outdoor_presentation_enabled(false)
	_level_runtime = next_runtime
	_level_runtime.activate()
	var level_spawn := _level_runtime.get_spawn_position()
	player.global_position = level_spawn
	player.bind_space(_level_runtime.get_voxel_space(), _level_runtime, level_spawn)
	_reset_camera_position()
	level_interaction.set_target(_level_runtime.get_return_door_position(), level_entrance_definition.return_prompt)
	await _fade_to(0.0)
	player.set_physics_process(true)
	_level_transitioning = false

func _exit_level():
	_level_transitioning = true
	level_interaction.clear_target()
	player.set_physics_process(false)
	input_buffer.clear_gameplay()
	await _fade_to(1.0)
	player.unbind_space()
	_level_runtime.deactivate()
	player.global_position = _location_state.get_persisted_position()
	var world_spawn := world.voxel_model.get_spawn_position()
	player.bind_space(world.voxel_model, world, world_spawn, world.voxel_model)
	_location_state.return_to_world()
	game_environment.set_outdoor_presentation_enabled(true)
	world.resume()
	entity_coordinator.resume()
	_level_entrance.visible = true
	_reset_camera_position()
	_level_runtime.queue_free()
	_level_runtime = null
	_show_world_level_interaction()
	await _fade_to(0.0)
	player.set_physics_process(true)
	_level_transitioning = false

func _show_world_level_interaction():
	if _level_entrance != null:
		level_interaction.set_target(_level_entrance.interaction_position, level_entrance_definition.enter_prompt)

func _reset_camera_position():
	camera_rig.snap_to_follow_target()

func _fade_to(alpha: float):
	_fade.visible = true
	var target_color := Color(0, 0, 0, alpha)
	var tween := create_tween()
	tween.tween_property(_fade, "color", target_color, LEVEL_FADE_SECONDS)
	await tween.finished
	if is_zero_approx(alpha):
		_fade.visible = false

func _get_persisted_position() -> Vector3:
	if not _location_state.is_in_level():
		_location_state.update_world_position(player.global_position)
	return _location_state.get_persisted_position()

func _unhandled_input(event):
	if _structure_transitioning:
		get_viewport().set_input_as_handled()
		return
	if _structure_designer_runtime != null:
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)):
			_handle_structure_designer_cancel()
			get_viewport().set_input_as_handled()
		return
	if structure_designer_workflow.is_dialog_open():
		if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)):
			structure_designer_workflow.cancel_active_dialog()
		get_viewport().set_input_as_handled()
		return
	if _level_transitioning or (_death_screen != null and is_instance_valid(_death_screen)):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event = event as InputEventKey
		if OS.is_debug_build() and (key_event.keycode == KEY_F9 or key_event.physical_keycode == KEY_F9):
			_toggle_player_stats_debug_panel()
			get_viewport().set_input_as_handled()
			return
		if player_stats_debug_panel != null and player_stats_debug_panel.is_open():
			if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
				player_stats_debug_panel.hide_panel()
				get_viewport().set_input_as_handled()
				return
		if animation_tuning_panel != null and animation_tuning_panel.is_open():
			if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
				animation_tuning_panel.hide_panel()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("toggle_backpack"):
		hud.toggle_backpack()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("toggle_crafting"):
		hud.toggle_crafting()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_cancel()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_handle_cancel()
		get_viewport().set_input_as_handled()

func _toggle_animation_tuning_panel():
	if animation_tuning_panel == null:
		animation_tuning_panel = animation_tuning_panel_scene.instantiate() as AnimationTuningPanel
		add_child(animation_tuning_panel)
		animation_tuning_panel.setup(player)
	animation_tuning_panel.toggle_panel()

func _toggle_player_stats_debug_panel():
	if player_stats_debug_panel == null:
		player_stats_debug_panel = player_stats_debug_panel_scene.instantiate() as PlayerStatsDebugPanel
		add_child(player_stats_debug_panel)
		player_stats_debug_panel.setup(player_stats)
	player_stats_debug_panel.toggle_panel()

func _handle_cancel():
	if dev_console.is_open():
		dev_console.close()
		return
	if structure_designer_workflow.cancel_active_dialog():
		return
	if player_stats_debug_panel != null and player_stats_debug_panel.is_open():
		player_stats_debug_panel.hide_panel()
		return
	if animation_tuning_panel != null and animation_tuning_panel.is_open():
		animation_tuning_panel.hide_panel()
		return
	if hud.is_side_panel_open():
		hud.close_side_panel()
		return
	_show_pause_menu()

func _is_gameplay_ui_blocked() -> bool:
	return hud.is_side_panel_open() or dev_console.is_open() or structure_designer_workflow.is_dialog_open() or _structure_transitioning or _structure_designer_runtime != null

func _request_new_structure() -> bool:
	if not _session_active or _level_transitioning or _structure_transitioning or player.is_defeated():
		return false
	return structure_designer_workflow.request_new()

func _request_exit_structure() -> bool:
	if _structure_transitioning or _structure_designer_runtime == null:
		return false
	return structure_designer_workflow.request_exit()

func _on_structure_designer_entry_requested(draft: StructureDraft) -> void:
	assert(_structure_designer_runtime == null)
	assert(_structure_lifecycle_snapshot == null)
	_enter_structure_designer(draft)

func _enter_structure_designer(draft: StructureDraft) -> void:
	_structure_transitioning = true
	var in_level := _location_state.is_in_level()
	_structure_lifecycle_snapshot = StructureDesignerLifecycleSnapshot.new(
		in_level,
		game_session.is_saving_suspended(),
		world.is_suspended(),
		entity_coordinator.is_suspended(),
		player,
		camera_rig,
		camera_rig.camera,
		hud,
		level_interaction,
		_level_entrance != null and _level_entrance.visible
	)
	game_session.suspend_saving()
	input_buffer.clear_gameplay()
	hud.close_side_panel_immediate()
	game_environment.close_debug_panel()
	if animation_tuning_panel != null and animation_tuning_panel.is_open():
		animation_tuning_panel.hide_panel()
	if player_stats_debug_panel != null and player_stats_debug_panel.is_open():
		player_stats_debug_panel.hide_panel()
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.visible = false
	camera_rig.process_mode = Node.PROCESS_MODE_DISABLED
	camera_rig.visible = false
	camera_rig.camera.current = false
	hud.process_mode = Node.PROCESS_MODE_DISABLED
	hud.visible = false
	level_interaction.process_mode = Node.PROCESS_MODE_DISABLED
	await _fade_to(1.0)
	if in_level:
		_level_runtime.deactivate()
	else:
		world.suspend()
		entity_coordinator.suspend()
		game_environment.set_outdoor_presentation_enabled(false)
		if _level_entrance != null:
			_level_entrance.visible = false
	_structure_designer_runtime = structure_designer_runtime_scene.instantiate() as StructureDesignerRuntime
	assert(_structure_designer_runtime != null)
	add_child(_structure_designer_runtime)
	_structure_designer_runtime.setup(draft, block_catalog, item_catalog, world.block_texture_set, structure_terrain_shader)
	_structure_designer_runtime.set_external_ui_blocked(dev_console.is_open() or structure_designer_workflow.is_dialog_open())
	_structure_designer_runtime.activate()
	await _fade_to(0.0)
	_structure_transitioning = false

func _on_structure_designer_exit_requested() -> void:
	if _structure_designer_runtime == null or _structure_transitioning:
		return
	_exit_structure_designer()

func _exit_structure_designer() -> void:
	_structure_transitioning = true
	dev_console.close()
	_structure_designer_runtime.set_external_ui_blocked(true)
	await _fade_to(1.0)
	var completed_runtime := _structure_designer_runtime
	_structure_designer_runtime = null
	completed_runtime.queue_free()
	await get_tree().process_frame
	_restore_structure_lifecycle()
	structure_designer_workflow.complete_exit()
	await _fade_to(0.0)
	_structure_transitioning = false

func _restore_structure_lifecycle() -> void:
	assert(_structure_lifecycle_snapshot != null)
	var snapshot := _structure_lifecycle_snapshot
	if snapshot.in_level:
		_level_runtime.activate()
	else:
		game_environment.set_outdoor_presentation_enabled(true)
		if not snapshot.world_was_suspended:
			world.resume()
		if not snapshot.entities_were_suspended:
			entity_coordinator.resume()
		if _level_entrance != null:
			_level_entrance.visible = snapshot.entrance_visible
	player.process_mode = snapshot.player_process_mode
	player.visible = snapshot.player_visible
	camera_rig.process_mode = snapshot.camera_process_mode
	camera_rig.visible = snapshot.camera_visible
	camera_rig.camera.current = snapshot.gameplay_camera_current
	hud.process_mode = snapshot.hud_process_mode
	hud.visible = snapshot.hud_visible
	level_interaction.process_mode = snapshot.level_interaction_process_mode
	if not snapshot.saving_was_suspended:
		game_session.resume_saving()
	_structure_lifecycle_snapshot = null

func _restore_structure_designer_for_shutdown() -> void:
	if _structure_lifecycle_snapshot == null:
		return
	if _structure_designer_runtime != null and is_instance_valid(_structure_designer_runtime):
		_structure_designer_runtime.free()
	_structure_designer_runtime = null
	_restore_structure_lifecycle()
	if structure_designer_workflow.has_active_draft():
		structure_designer_workflow.complete_exit()
	_structure_transitioning = false

func _handle_structure_designer_cancel() -> void:
	if dev_console.is_open():
		dev_console.close()
		return
	if structure_designer_workflow.cancel_active_dialog():
		return
	if _structure_designer_runtime.cancel_active_ui():
		return
	structure_designer_workflow.request_exit()

func _on_dev_console_open_state_changed(_open: bool) -> void:
	_sync_structure_designer_ui_blocking()

func _on_structure_dialog_open_state_changed(_open: bool) -> void:
	_sync_structure_designer_ui_blocking()

func _sync_structure_designer_ui_blocking() -> void:
	if _structure_designer_runtime == null:
		return
	_structure_designer_runtime.set_external_ui_blocked(dev_console.is_open() or structure_designer_workflow.is_dialog_open())

func _show_pause_menu():
	_pause_menu = pause_menu_scene.instantiate() as PauseMenu
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.main_menu_requested.connect(_save_and_request_main_menu)
	add_child(_pause_menu)
	_pause_menu.setup(settings)
	_pause_menu.settings_screen.settings_changed.connect(_on_settings_changed)
	_save_canvas.visible = true
	_refresh_save_label()
	get_tree().paused = true

func _on_settings_changed(updated_settings: GameSettings):
	settings = updated_settings
	settings.apply_display(get_viewport())
	game_environment.apply_settings(settings)
	world.apply_settings(settings)
	if _level_runtime != null:
		_level_runtime.apply_settings(settings)
	if settings.persist_changes:
		settings.save_to_disk()

func _resume_from_pause():
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null
	_save_canvas.visible = false
	get_tree().paused = false

func _save_and_request_main_menu():
	_restore_structure_designer_for_shutdown()
	_restore_player_from_defeat()
	_deactivate_session()
	get_tree().paused = false
	if _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null
	hud.close_side_panel_immediate()
	camera_rig.reset_panel_obstruction()
	level_interaction.clear_target()
	game_session.shutdown("quit_to_menu")
	melee_combat.shutdown()
	entity_coordinator.shutdown()
	_teardown_level_runtime()
	world.shutdown()
	main_menu_requested.emit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _session_active:
		_restore_structure_designer_for_shutdown()
		_restore_player_from_defeat()
		_deactivate_session()
		game_session.shutdown("close")
		melee_combat.shutdown()
		entity_coordinator.shutdown()
		_teardown_level_runtime()
		world.shutdown()

func _deactivate_session():
	set_physics_process(false)
	set_process_unhandled_input(false)
	_session_active = false

func _teardown_level_runtime():
	if _level_runtime == null:
		return
	player.unbind_space()
	_level_runtime.deactivate()
	_level_runtime.queue_free()
	_level_runtime = null
