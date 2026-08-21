extends Node3D
class_name Game

const EnemyCombatFeedbackType := preload("res://combat/presentation/enemy_combat_feedback.gd")
const LEVEL_FADE_SECONDS: float = 0.18

signal loading_progress(stage: String, percent: float, details: String)
signal session_ready
signal session_start_failed(message: String)
signal main_menu_requested

@export var pause_menu_scene: PackedScene
@export var animation_tuning_panel_scene: PackedScene
@export var player_stats_debug_panel_scene: PackedScene
@export var player_death_screen_scene: PackedScene
@export var block_catalog: BlockCatalog
@export var foliage_catalog: FoliageCatalog
@export var item_catalog: ItemCatalog
@export var crafting_recipe_catalog: CraftingRecipeCatalog
@export var anvil_recipe_catalog: CraftingRecipeCatalog
@export var cauldron_recipe_catalog: CraftingRecipeCatalog
@export var entity_catalog: EntityCatalog
@export var damage_type_catalog: DamageTypeCatalog
@export var combat_hit_particle_catalog: CombatHitParticleCatalog
@export var player_stats_definition: CombatStatsDefinition
@export var player_perk_rules: PlayerPerkRules
@export var level_catalog: LevelCatalog
@export var level_entrance_definition: LevelEntranceDefinition
@export var level_runtime_scene: PackedScene
@export var structure_designer_runtime_scene: PackedScene
@export var structure_terrain_shader: Shader
@export var loot_drop_scene: PackedScene

@onready var overworld: Node3D = $Overworld as Node3D
@onready var world: WorldController = $Overworld/World as WorldController
@onready var player: PlayerMotor = $Player as PlayerMotor
@onready var camera_rig: CameraRig = $CameraRig as CameraRig
@onready var game_environment: GameEnvironment = $Environment as GameEnvironment
@onready var world_entity_coordinator: WorldEntityCoordinator = $Overworld/WorldEntities as WorldEntityCoordinator
@onready var slime_attachment_coordinator: SlimeAttachmentCoordinator = $SlimeAttachments as SlimeAttachmentCoordinator
@onready var watcher_encounter: WatcherEncounterCoordinator = $WatcherEncounter as WatcherEncounterCoordinator
@onready var watcher_screen_effect: WatcherScreenEffect = $WatcherScreenEffect as WatcherScreenEffect
@onready var overworld_loot: OverworldLootCoordinator = $OverworldLoot as OverworldLootCoordinator
@onready var melee_combat: MeleeCombatCoordinator = $MeleeCombat as MeleeCombatCoordinator
@onready var arrow_projectiles: ArrowProjectileRuntime = $ArrowProjectiles as ArrowProjectileRuntime
@onready var arrow_trajectory: ArrowTrajectoryView = $ArrowTrajectory as ArrowTrajectoryView
@onready var combat_hit_particles: CombatHitParticles = $CombatHitParticles as CombatHitParticles
@onready var enemy_combat_feedback: EnemyCombatFeedbackType = $EnemyCombatFeedback as EnemyCombatFeedbackType
@onready var hud: HUD = $HUD as HUD
@onready var dev_console: DevConsole = $DevConsole as DevConsole
@onready var game_session: GameSession = $GameSession as GameSession
@onready var mining_break_particles: MiningBreakParticles = $MiningBreakParticles as MiningBreakParticles
@onready var mining_hit_particles: MiningHitParticles = $MiningHitParticles as MiningHitParticles
@onready var mining_tutorial: MiningTutorialCoordinator = $MiningTutorial as MiningTutorialCoordinator
@onready var mining_tutorial_view: MiningTutorialView = $MiningTutorialView as MiningTutorialView
@onready var food_tutorial: FoodTutorialCoordinator = $FoodTutorial as FoodTutorialCoordinator
@onready var food_tutorial_view: FoodTutorialView = $FoodTutorialView as FoodTutorialView
@onready var crafting_tutorial: CraftingTutorialCoordinator = $CraftingTutorial as CraftingTutorialCoordinator
@onready var crafting_tutorial_view: CraftingTutorialView = $CraftingTutorialView as CraftingTutorialView
@onready var crafting_ingredients_tutorial: CraftingIngredientsTutorialCoordinator = $CraftingIngredientsTutorial as CraftingIngredientsTutorialCoordinator
@onready var crafting_ingredients_tutorial_view: CraftingIngredientsTutorialView = $CraftingIngredientsTutorialView as CraftingIngredientsTutorialView
@onready var copper_mining_tutorial: CopperMiningTutorialCoordinator = $CopperMiningTutorial as CopperMiningTutorialCoordinator
@onready var copper_mining_tutorial_view: CopperMiningTutorialView = $CopperMiningTutorialView as CopperMiningTutorialView
@onready var placement_prompt: PlacementPromptCoordinator = $PlacementPrompt as PlacementPromptCoordinator
@onready var level_interaction: LevelInteractionCoordinator = $LevelInteractionCoordinator as LevelInteractionCoordinator
@onready var structure_designer_workflow: StructureDesignerWorkflow = $StructureDesignerWorkflow as StructureDesignerWorkflow
@onready var structure_designer_dialogs: StructureDesignerDialogs = $StructureDesignerDialogs as StructureDesignerDialogs
@onready var pumpkin_patch: PumpkinPatchCoordinator = $Overworld/PumpkinPatch as PumpkinPatchCoordinator
@onready var apple_trees: AppleTreeCoordinator = $Overworld/AppleTrees as AppleTreeCoordinator
@onready var _save_canvas: CanvasLayer = $SaveStatusLayer as CanvasLayer
@onready var _save_label: Label = $SaveStatusLayer/SaveStatusLabel as Label
@onready var _fade: ColorRect = $TransitionLayer/Fade as ColorRect

var inventory_model: InventoryModel
var equipment_instance_factory: EquipmentInstanceFactory
var world_loot_state: WorldLootState
var dungeon_progress: DungeonProgressState
var player_stats: ActorStats
var player_perks: PlayerPerks
var player_perk_coordinator: PlayerPerkCoordinator
var item_proficiency: ItemProficiency
var tutorial_progress: TutorialProgress
var inventory_loadout_coordinator: InventoryLoadoutCoordinator
var player_action_executors: PlayerActionExecutors
var crafting_coordinator: CraftingCoordinator
var anvil_crafting_coordinator: CraftingCoordinator
var cauldron_crafting_coordinator: CraftingCoordinator
var combat_progression_coordinator: CombatProgressionCoordinator
var rune_socketing_coordinator: RuneSocketingCoordinator
var interaction_prompt_coordinator: InteractionPromptCoordinator
var anvil_coordinator: AnvilCoordinator
var cauldron_coordinator: CauldronCoordinator
var harvest_coordinator: HarvestCoordinator
var item_consumption_coordinator: ItemConsumptionCoordinator
var chest_storage: ChestStorage
var chest_coordinator: ChestCoordinator
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
var _active_entity_runtime: EntityRuntime
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
	_save_data = save_data.duplicate(true)
	settings = p_settings
	_world_state = SaveManager.decode_world_state(_save_data) as WorldState

func _ready():
	set_physics_process(false)
	set_process_unhandled_input(false)
	if _world_state == null:
		_fail_session_start("This world could not be loaded because its saved world state is invalid or references unavailable blocks. The save was not changed.")
		return
	var block_catalog_valid := block_catalog.validate()
	var foliage_catalog_valid := foliage_catalog.validate(block_catalog)
	var item_catalog_valid := item_catalog.validate(block_catalog)
	var chest_block: BlockDefinition = null
	if block_catalog_valid:
		chest_block = block_catalog.get_definition(BlockId.Type.CHEST)
	var chest_content_valid := (
		chest_block != null
		and chest_block.container != null
		and chest_block.container.get_slot_count() == SaveManager.PERSISTED_CHEST_SLOT_COUNT
	)
	var crafting_catalog_valid := crafting_recipe_catalog.validate(item_catalog)
	var anvil_catalog_valid := anvil_recipe_catalog != null and anvil_recipe_catalog.validate(item_catalog)
	var cauldron_catalog_valid := cauldron_recipe_catalog != null and cauldron_recipe_catalog.validate(item_catalog)
	var entity_catalog_valid := entity_catalog.validate()
	var loot_catalog_valid := entity_catalog_valid and item_catalog_valid and LootCatalogValidator.validate_entity_catalog(entity_catalog, item_catalog)
	var damage_type_catalog_valid := damage_type_catalog != null and damage_type_catalog.validate()
	var combat_particle_catalog_valid := combat_hit_particle_catalog.validate(entity_catalog)
	var player_stats_valid := player_stats_definition.validate()
	var player_perks_valid := player_perk_rules != null and player_perk_rules.validate(player_stats_definition)
	var level_catalog_valid := level_catalog.validate()
	var level_loot_catalog_valid := (
		level_catalog_valid
		and item_catalog_valid
		and chest_content_valid
		and LevelLootCatalogValidator.validate(
			level_catalog,
			item_catalog,
			chest_block.container.get_slot_count(),
		)
	)
	var level_encounter_catalog_valid := level_catalog_valid and entity_catalog_valid and LevelEncounterCatalogValidator.validate(level_catalog, entity_catalog)
	var level_entrance_valid := level_catalog_valid and level_entrance_definition != null and level_entrance_definition.validate(level_catalog)
	if not block_catalog_valid or not foliage_catalog_valid or not item_catalog_valid or not chest_content_valid or not crafting_catalog_valid or not anvil_catalog_valid or not cauldron_catalog_valid or not entity_catalog_valid or not loot_catalog_valid or not damage_type_catalog_valid or not combat_particle_catalog_valid or not player_stats_valid or not player_perks_valid or not level_catalog_valid or not level_loot_catalog_valid or not level_encounter_catalog_valid or not level_entrance_valid:
		_fail_session_start("Game content validation failed. The save was not changed.")
		return
	var structure_file_store := StructureFileStore.new(ProjectSettings.globalize_path("res://../").simplify_path())
	structure_designer_workflow.setup(structure_designer_dialogs, structure_file_store)
	structure_designer_workflow.designer_entry_requested.connect(_on_structure_designer_entry_requested)
	structure_designer_workflow.designer_exit_requested.connect(_on_structure_designer_exit_requested)
	structure_designer_dialogs.open_state_changed.connect(_on_structure_dialog_open_state_changed)
	dev_console.open_state_changed.connect(_on_dev_console_open_state_changed)
	settings.apply_display(get_viewport())
	game_environment.setup(float(_save_data.get("time_of_day", 6.0)), settings.get_shadow_distance(), _world_state.seed)
	game_environment.apply_settings(settings)
	world.block_catalog = block_catalog
	world.foliage_catalog = foliage_catalog
	world.configure_settings(settings)
	var encoded_next_instance_id = _save_data.get("next_equipment_instance_id", null)
	if typeof(encoded_next_instance_id) != TYPE_INT or int(encoded_next_instance_id) < 1:
		_fail_session_start("This world could not be loaded because its saved equipment identity state is invalid. The save was not changed.")
		return
	equipment_instance_factory = EquipmentInstanceFactory.new(item_catalog, int(encoded_next_instance_id))
	inventory_model = InventoryModel.new(item_catalog, equipment_instance_factory)
	player_stats = ActorStats.new(player_stats_definition)
	item_proficiency = ItemProficiency.new(item_catalog)
	if not _restore_inventory():
		_fail_session_start("This world could not be loaded because its saved inventory is invalid or references unavailable content. The save was not changed.")
		return
	if not _restore_item_proficiency():
		_fail_session_start("This world could not be loaded because its saved item proficiency is invalid or references unavailable content. The save was not changed.")
		return
	tutorial_progress = TutorialProgress.new()
	if not tutorial_progress.restore(_save_data.get("tutorial_progress", null)):
		_fail_session_start("This world could not be loaded because its tutorial progress is invalid. The save was not changed.")
		return
	inventory_loadout_coordinator = InventoryLoadoutCoordinator.new()
	if not inventory_loadout_coordinator.setup(inventory_model, player_stats, item_proficiency):
		_fail_session_start("This world could not be loaded because its saved equipment or rune modifiers are invalid. The save was not changed.")
		return
	if not inventory_loadout_coordinator.migrate_starter_items():
		push_warning("[Game] Starter item migration deferred because inventory is full")
	rune_socketing_coordinator = RuneSocketingCoordinator.new()
	if not rune_socketing_coordinator.setup(inventory_model, inventory_loadout_coordinator, item_proficiency):
		_fail_session_start("This world could not be loaded because its saved rune socket state is invalid. The save was not changed.")
		return
	crafting_coordinator = CraftingCoordinator.new()
	crafting_coordinator.setup(inventory_model, inventory_loadout_coordinator, crafting_recipe_catalog)
	anvil_crafting_coordinator = CraftingCoordinator.new()
	anvil_crafting_coordinator.setup(inventory_model, inventory_loadout_coordinator, anvil_recipe_catalog)
	cauldron_crafting_coordinator = CraftingCoordinator.new()
	cauldron_crafting_coordinator.setup(inventory_model, inventory_loadout_coordinator, cauldron_recipe_catalog)
	player_perks = PlayerPerks.new(player_perk_rules)
	if not _restore_player_progression():
		_fail_session_start("This world could not be loaded because its saved player progression is invalid. The save was not changed.")
		return
	dev_console.setup(
		inventory_model,
		inventory_loadout_coordinator,
		player_stats,
		pumpkin_patch,
		Callable(self, "_request_new_structure"),
		Callable(self, "_request_import_structure"),
		Callable(self, "_request_export_structure"),
		Callable(self, "_request_exit_structure"),
		Callable(world, "try_set_water_ripple_strength"),
		Callable(self, "_spawn_debug_birds"),
		Callable(self, "_request_clear_current_dungeon_room"),
	)
	if not _restore_chest_state(chest_block):
		_fail_session_start("This world could not be loaded because its saved chest state is invalid or references unavailable content. The save was not changed.")
		return
	if not _restore_world_loot_state():
		_fail_session_start("This world could not be loaded because its saved world loot is invalid or its equipment IDs conflict with other storage. The save was not changed.")
		return
	if not _restore_dungeon_progress():
		_fail_session_start("This world could not be loaded because its saved dungeon progress is invalid. The save was not changed.")
		return
	var restored_instance_ids := inventory_model.get_equipment_instance_ids()
	restored_instance_ids.append_array(chest_storage.get_equipment_instance_ids())
	restored_instance_ids.append_array(world_loot_state.get_equipment_instance_ids())
	if not equipment_instance_factory.can_restore_state(
		equipment_instance_factory.get_next_instance_id(),
		restored_instance_ids,
	):
		_fail_session_start("This world could not be loaded because its saved equipment IDs are duplicated or collide with the next ID. The save was not changed.")
		return
	combat_progression_coordinator = CombatProgressionCoordinator.new()
	combat_progression_coordinator.setup(player_stats, inventory_model, entity_catalog, item_proficiency)
	world.configure_start_state(_world_state)
	world.generation_progress.connect(_on_generation_progress)
	await world.initialize_world_async()
	world.generation_progress.disconnect(_on_generation_progress)
	interaction_prompt_coordinator = InteractionPromptCoordinator.new()
	interaction_prompt_coordinator.setup(hud, Callable(self, "_is_gameplay_ui_blocked"))
	if not _setup_chest_runtime(chest_block):
		_fail_session_start("This world could not be loaded because its saved chest blocks and storage do not match. The save was not changed.")
		return
	if not _setup_gameplay():
		return
	placement_prompt.setup(player.interactor, interaction_prompt_coordinator)
	level_interaction.setup(player, interaction_prompt_coordinator)
	level_interaction.interaction_requested.connect(_on_level_interaction_requested)
	_setup_level_entrance()
	game_session.save_status_changed.connect(_show_save_status)
	game_session.setup(
		_slot_id,
		_save_data,
		world,
		player_stats,
		inventory_model,
		equipment_instance_factory,
		player_perks,
		item_proficiency,
		tutorial_progress,
		chest_storage,
		world_loot_state,
		dungeon_progress,
		chest_coordinator,
		overworld_loot,
		game_environment,
		pumpkin_patch,
		apple_trees,
		_get_persisted_position,
	)
	var tutorial_callout_arbiter := TutorialCalloutArbiter.new()
	mining_tutorial.setup(
		world.voxel_model,
		player,
		func() -> bool: return player.voxel_space == world.voxel_model,
		camera_rig.camera,
		player.interactor,
		mining_tutorial_view,
		tutorial_progress,
		tutorial_callout_arbiter,
		world.config.seed_value,
	)
	food_tutorial.setup(
		player,
		func() -> bool: return player.voxel_space == world.voxel_model,
		camera_rig.camera,
		harvest_coordinator,
		food_tutorial_view,
		tutorial_progress,
		tutorial_callout_arbiter,
	)
	var removed_blocks = _save_data.get("removed_blocks", {})
	crafting_tutorial.setup(
		player.interactor,
		hud.crafting_panel,
		crafting_tutorial_view,
		tutorial_progress,
		tutorial_callout_arbiter,
		removed_blocks is Dictionary and not (removed_blocks as Dictionary).is_empty(),
	)
	crafting_ingredients_tutorial.setup(
		hud.crafting_panel,
		crafting_ingredients_tutorial_view,
		tutorial_progress,
		tutorial_callout_arbiter,
	)
	copper_mining_tutorial.setup(
		world.voxel_model,
		player,
		func() -> bool: return player.voxel_space == world.voxel_model,
		camera_rig.camera,
		player.interactor,
		copper_mining_tutorial_view,
		tutorial_progress,
		tutorial_callout_arbiter,
	)
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

func _restore_inventory() -> bool:
	var saved_inventory = _save_data.get("inventory", null)
	if saved_inventory == null:
		inventory_model.setup_empty()
		return true
	if not saved_inventory is Dictionary or not inventory_model.from_dict(saved_inventory):
		return false
	return true

func _restore_player_progression() -> bool:
	var saved_stats = _save_data.get("player_stats", null)
	if saved_stats != null and not saved_stats is Dictionary:
		return false
	var saved_perks = _save_data.get("player_perks", null)
	if not saved_perks is Dictionary:
		return false
	player_perk_coordinator = PlayerPerkCoordinator.new()
	if not player_perk_coordinator.setup(player_perks, player_stats):
		return false
	if saved_stats == null:
		if not player_perk_coordinator.restore(saved_perks):
			return false
	elif not player_perk_coordinator.restore_progression(saved_stats, saved_perks):
		return false
	if not player_stats.is_dead():
		return true
	var health_restored := player_stats.set_current_hp(player_stats.get_value(&"hp"))
	assert(health_restored)
	_recovered_defeated_save = true
	_world_state.player_position = Vector3.ZERO
	_save_data["player_position"] = null
	_save_data["player_stats"] = player_stats.snapshot_progression()
	return true

func _restore_item_proficiency() -> bool:
	var saved_proficiency = _save_data.get("item_proficiency", null)
	return saved_proficiency is Dictionary and item_proficiency.restore(saved_proficiency)

func _restore_chest_state(chest_block: BlockDefinition) -> bool:
	chest_storage = ChestStorage.new(
		item_catalog,
		equipment_instance_factory,
		chest_block.container.get_slot_count(),
	)
	var decoded_chests = SaveManager.decode_chest_state(_save_data)
	return decoded_chests is Dictionary and chest_storage.restore(decoded_chests)

func _restore_world_loot_state() -> bool:
	var reserved_instance_ids: Dictionary = {}
	var instance_ids := inventory_model.get_equipment_instance_ids()
	instance_ids.append_array(chest_storage.get_equipment_instance_ids())
	for instance_id in instance_ids:
		if reserved_instance_ids.has(instance_id):
			return false
		reserved_instance_ids[instance_id] = true
	var encoded_world_loot = _save_data.get("world_loot", null)
	if not encoded_world_loot is Dictionary:
		return false
	world_loot_state = WorldLootState.new(item_catalog, equipment_instance_factory)
	return world_loot_state.restore(encoded_world_loot, reserved_instance_ids)

func _restore_dungeon_progress() -> bool:
	dungeon_progress = DungeonProgressState.new()
	return dungeon_progress.restore(_save_data.get("dungeon_progress", null))

func _setup_chest_runtime(chest_block: BlockDefinition) -> bool:
	var chest_state_error := _get_chest_state_error(
		world.voxel_model,
		chest_storage,
		int(chest_block.id),
	)
	if not chest_state_error.is_empty():
		return false
	chest_coordinator = ChestCoordinator.new()
	if not chest_coordinator.setup(chest_storage, inventory_model, inventory_loadout_coordinator, world.voxel_model, chest_block):
		return false
	world.voxel_model.block_edit_committed.connect(chest_coordinator.handle_block_edit)
	return true

static func _get_chest_state_error(
	voxel_world: VoxelWorld,
	storage: ChestStorage,
	chest_block_id: int,
) -> String:
	var placed_blocks := voxel_world.snapshot_block_edits()["placed"] as Dictionary
	var saved_chests := storage.snapshot()
	for position in saved_chests:
		if int(placed_blocks.get(position, BlockId.Type.AIR)) != chest_block_id:
			return "Saved chest state has no placed chest block at %s" % position
	for position in placed_blocks:
		if int(placed_blocks[position]) == chest_block_id and not saved_chests.has(position):
			return "Placed chest block has no saved chest state at %s" % position
	return ""

func _setup_gameplay() -> bool:
	camera_rig.setup(player, input_buffer)
	watcher_screen_effect.setup(player, camera_rig.camera)
	watcher_encounter.setup(player, watcher_screen_effect)
	world_entity_coordinator.setup(entity_catalog, world.voxel_model, world.config.seed_value, world.is_position_streamed)
	var world_entities := world_entity_coordinator.get_runtime()
	melee_combat.setup(world.voxel_model, player, player_stats, inventory_model, world_entities, damage_type_catalog)
	melee_combat.melee_outcome_committed.connect(combat_progression_coordinator.record_melee_outcome)
	melee_combat.projectile_outcome_committed.connect(combat_progression_coordinator.record_projectile_outcome)
	melee_combat.melee_outcome_committed.connect(_on_melee_outcome_committed)
	combat_hit_particles.setup(melee_combat, combat_hit_particle_catalog)
	enemy_combat_feedback.setup(melee_combat, camera_rig.camera)
	var mining_executor := MiningActionExecutor.new()
	var tilling_executor := TillingActionExecutor.new()
	var placement_executor := BlockPlacementActionExecutor.new()
	var mining_ready: bool = mining_executor.setup(
		inventory_model,
		inventory_loadout_coordinator,
		player.interactor.unarmed_primary_action,
		_can_break_block,
	)
	var tilling_ready: bool = tilling_executor.setup(inventory_model)
	var placement_ready: bool = placement_executor.setup(inventory_model, inventory_loadout_coordinator)
	assert(mining_ready and tilling_ready and placement_ready)
	player_action_executors = PlayerActionExecutors.new()
	var actions_ready: bool = player_action_executors.setup(mining_executor, tilling_executor, placement_executor)
	assert(actions_ready)
	player.setup(
		camera_rig,
		inventory_model,
		inventory_loadout_coordinator,
		player_action_executors,
		input_buffer,
		player_stats,
		melee_combat,
		world_entities,
		_try_interact_with_block,
		_can_break_block,
	)
	slime_attachment_coordinator.setup(player, player_stats)
	arrow_projectiles.setup(inventory_model, inventory_loadout_coordinator, melee_combat)
	player.setup_projectiles(arrow_projectiles)
	arrow_trajectory.setup(player.interactor, arrow_projectiles)
	player.water_step_committed.connect(world.play_water_ripple)
	world_entities.water_surface_motion_committed.connect(world.play_water_ripple)
	overworld_loot.setup(
		entity_catalog,
		item_catalog,
		equipment_instance_factory,
		world_loot_state,
		inventory_model,
		inventory_loadout_coordinator,
		player,
		world_entities,
		world.is_position_streamed,
		loot_drop_scene,
	)
	item_consumption_coordinator = ItemConsumptionCoordinator.new()
	item_consumption_coordinator.setup(inventory_model, inventory_loadout_coordinator, player_stats)
	player.setup_consumption(item_consumption_coordinator)
	_bind_entity_context(world.voxel_model, world_entities, world.is_position_streamed)
	anvil_coordinator = AnvilCoordinator.new()
	anvil_coordinator.setup(world.voxel_model)
	cauldron_coordinator = CauldronCoordinator.new()
	cauldron_coordinator.setup(world.voxel_model)
	player.interactor.crafting_station_open_requested.connect(_on_crafting_station_open_requested)
	player.interactor.container_open_requested.connect(_on_container_open_requested)
	player_stats.health_depleted.connect(_on_player_defeated)
	var mining_particle_tints := MiningParticleTintPalette.new(block_catalog)
	mining_break_particles.setup(world.voxel_model, mining_particle_tints)
	mining_hit_particles.setup(player.animation_driver, player.interactor, mining_particle_tints)
	var world_spawn := world.voxel_model.get_spawn_position()
	var saved_position = _world_state.player_position
	if saved_position != Vector3.ZERO:
		player.global_position = saved_position + Vector3(0, 0.2, 0)
	else:
		player.global_position = world_spawn + Vector3(0, 0.1, 0)
	player.bind_space(world.voxel_model, world, world_spawn, world.voxel_model)
	_location_state = GameplayLocationState.new(player.global_position)
	if not pumpkin_patch.setup(world.voxel_model, player, world.config.seed_value, _save_data.get("pumpkin_patch", null)):
		_fail_session_start("This world could not be loaded because its saved pumpkin patch is invalid, or a new patch could not be placed. The save was not changed.")
		return false
	if not apple_trees.setup(world.voxel_model, world.chunk_manager, world.config.seed_value, _save_data.get("apple_trees", null), item_catalog):
		_fail_session_start("This world could not be loaded because its saved apple tree state or harvest content is invalid. The save was not changed.")
		return false
	harvest_coordinator = HarvestCoordinator.new()
	var harvest_sources: Array[HarvestSource] = [pumpkin_patch, apple_trees]
	if not harvest_coordinator.setup(harvest_sources, inventory_model, inventory_loadout_coordinator, interaction_prompt_coordinator):
		_fail_session_start("Harvest content validation failed. The save was not changed.")
		return false
	player.setup_harvesting(harvest_coordinator)
	camera_rig.reset_panel_obstruction()
	game_environment.sky_color_changed.connect(world.update_water_tint)
	game_environment.start_clock()
	hud.setup_with_camera(inventory_model, inventory_loadout_coordinator, crafting_coordinator, crafting_recipe_catalog, camera_rig, player_stats, item_proficiency)
	var anvil_station := block_catalog.get_definition(BlockId.Type.ANVIL).crafting_station
	hud.setup_anvil(anvil_coordinator, anvil_station, anvil_crafting_coordinator, anvil_recipe_catalog, camera_rig)
	var cauldron_station := block_catalog.get_definition(BlockId.Type.CAULDRON).crafting_station
	hud.setup_cauldron(cauldron_coordinator, cauldron_station, cauldron_crafting_coordinator, cauldron_recipe_catalog, camera_rig)
	hud.setup_socketing(inventory_model, rune_socketing_coordinator, item_proficiency)
	hud.setup_progression(player_stats, player_perk_coordinator)
	hud.setup_consumption(item_consumption_coordinator)
	hud.setup_compass(camera_rig.camera, player)
	world.set_player_ref(player)
	camera_rig.snap_to_follow_target()
	camera_rig.current_yaw_deg = camera_rig.target_yaw_deg
	camera_rig.camera.current = true
	return true

func _fail_session_start(message: String) -> void:
	set_physics_process(false)
	set_process_unhandled_input(false)
	session_start_failed.emit(message)

func _on_player_defeated():
	if _death_screen != null and is_instance_valid(_death_screen):
		return
	game_session.suspend_saving()
	slime_attachment_coordinator.clear_attachments()
	var watcher_runtimes: Array[EntityRuntime] = [_active_entity_runtime]
	var overworld_runtime := world_entity_coordinator.get_runtime()
	if overworld_runtime != _active_entity_runtime:
		watcher_runtimes.append(overworld_runtime)
	watcher_encounter.reset_for_player_defeat(watcher_runtimes)
	player.enter_defeated_state()
	if _location_state != null and _location_state.is_in_level() and _level_runtime != null:
		_level_runtime.suspend_simulation()
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
	_sync_compass_external_menu()

func _on_respawn_requested():
	if _death_screen == null or not is_instance_valid(_death_screen):
		return
	var completed_screen := _death_screen
	_death_screen = null
	completed_screen.queue_free()
	_sync_compass_external_menu()
	if _location_state != null and _location_state.is_in_level():
		_exit_level(true)
		return
	_restore_player_from_defeat()

func _restore_player_from_defeat(respawn_position: Variant = null):
	if player.is_defeated() or player.stats.is_dead():
		var target_position := world.voxel_model.get_spawn_position() + Vector3(0.0, 0.1, 0.0)
		if respawn_position is Vector3:
			target_position = respawn_position as Vector3
		player.respawn_at(target_position)
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
	overworld.add_child(_level_entrance)
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
	_sync_compass_external_menu()
	if _level_transitioning or _structure_transitioning or _structure_designer_runtime != null:
		input_buffer.clear_gameplay()
		return
	if player.is_defeated():
		input_buffer.clear_gameplay()
	else:
		if OS.is_debug_build() and Input.is_action_just_pressed("toggle_animation_tuner"):
			_toggle_animation_tuning_panel()
		input_buffer.poll()
		if dev_console.is_open() or structure_designer_workflow.is_dialog_open() or hud.is_chest_open() or (animation_tuning_panel != null and animation_tuning_panel.is_open()):
			input_buffer.clear_gameplay()
	if _location_state != null:
		_location_state.update_world_position(player.global_position)
	if _location_state == null or not _location_state.is_in_level():
		var observation := EntityTargetObservation.from_camera_values(
			player.global_position,
			camera_rig.camera.global_transform,
			camera_rig.camera.h_offset,
			camera_rig.camera.v_offset,
		)
		assert(observation != null)
		world_entity_coordinator.tick(delta, observation, game_environment.get_time_of_day())
	if _active_entity_runtime != null:
		hud.set_compass_enemy_positions(
			_active_entity_runtime.get_hostile_positions_near(
				player.global_position,
				hud.get_compass_enemy_radius(),
			)
		)

func _on_level_interaction_requested():
	if _level_transitioning or _structure_transitioning or _structure_designer_runtime != null or _location_state == null:
		return
	if _location_state.is_in_level():
		_exit_level()
	else:
		_enter_level()

func _on_crafting_station_open_requested(position: Vector3i, definition: CraftingStationBlockDefinition) -> void:
	hud.open_crafting_station(position, definition)

func _try_interact_with_block(position: Vector3i) -> bool:
	if _location_state == null:
		return false
	var center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
	if player.global_position.distance_squared_to(center) > player.interactor.reach * player.interactor.reach:
		return false
	var space := _level_runtime.get_voxel_space() if _location_state.is_in_level() and _level_runtime != null else world.voxel_model
	var block_id := space.get_block_id_at(position)
	return _try_open_container(position, block_catalog.get_definition(block_id).container)

func _can_break_block(position: Vector3i) -> bool:
	return _location_state == null or not _location_state.is_in_level() and (chest_coordinator == null or chest_coordinator.can_break(position))

func _enter_level():
	_level_transitioning = true
	hud.close_chest()
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
	var dungeon_instance_id := level_entrance_definition.entrance_id
	var attempt_index := dungeon_progress.begin_attempt(dungeon_instance_id)
	if attempt_index < 0:
		next_runtime.queue_free()
		_show_save_status("Dungeon unavailable")
		_show_world_level_interaction()
		_level_transitioning = false
		return
	var repeat_loot_seed := LootKeyedRandom.u53(
		result.layout.seed_value,
		definition.level_id,
		[
			&"repeatable_chests",
			dungeon_instance_id,
			StringName(str(attempt_index)),
		],
	)
	var one_time_reward := definition.one_time_chest_reward
	var one_time_loot_seed := 0
	if one_time_reward != null:
		one_time_loot_seed = LootKeyedRandom.u53(
			result.layout.seed_value,
			one_time_reward.reward_id,
			[&"one_time_reward", dungeon_instance_id],
		)
	next_runtime.setup(
		result.layout,
		definition,
		repeat_loot_seed,
		one_time_loot_seed,
		dungeon_instance_id,
		dungeon_progress,
		block_catalog,
		world.block_texture_set,
		settings,
		entity_catalog,
		inventory_model,
		inventory_loadout_coordinator,
	)
	next_runtime.get_chest_coordinator().transfer_rejected.connect(_show_save_status)
	next_runtime.get_chest_coordinator().one_time_reward_claimed.connect(
		_on_dungeon_one_time_reward_claimed,
	)
	next_runtime.set_player_context(player, camera_rig.camera)
	var return_position := player.global_position
	_level_entrance.play_door_open_sound()
	player.set_physics_process(false)
	input_buffer.clear_gameplay()
	await _fade_to(1.0)
	hud.set_compass_available(false)
	hud.clear_compass_target()
	player.unbind_space()
	_unbind_entity_context()
	_location_state.enter_level(return_position)
	world.suspend()
	world_entity_coordinator.suspend()
	overworld.visible = false
	overworld_loot.suspend()
	_level_entrance.visible = false
	game_environment.set_outdoor_presentation_enabled(false)
	game_environment.set_dungeon_music_active(true)
	_level_runtime = next_runtime
	_level_runtime.activate()
	var level_spawn := _level_runtime.get_spawn_position()
	player.global_position = level_spawn
	_bind_entity_context(
		_level_runtime.get_voxel_space(),
		_level_runtime.get_entity_runtime(),
		_is_active_level_position_ready,
	)
	player.bind_space(_level_runtime.get_voxel_space(), _level_runtime, level_spawn)
	_reset_camera_position()
	level_interaction.set_target(_level_runtime.get_return_door_position(), level_entrance_definition.return_prompt)
	await _fade_to(0.0)
	player.set_physics_process(true)
	_level_transitioning = false

func _exit_level(restore_from_defeat: bool = false):
	if not restore_from_defeat and (player.is_defeated() or player.stats.is_dead()):
		return
	var dungeon_completed := false
	if not restore_from_defeat:
		hud.close_chest()
		var completion_outcome := DungeonRunCompletionTransaction.try_complete(
			_level_runtime.get_chest_coordinator(),
			dungeon_progress,
			level_entrance_definition.entrance_id,
		)
		if completion_outcome == DungeonRunCompletionTransaction.Outcome.INVALIDATED:
			_show_save_status("Dungeon rewards changed — try exiting again")
			return
		dungeon_completed = completion_outcome == DungeonRunCompletionTransaction.Outcome.COMPLETED
		if dungeon_completed:
			if _slot_id == -1:
				_show_save_status("Dungeon complete")
			else:
				game_session.save("dungeon_complete")
	_level_transitioning = true
	hud.close_chest()
	level_interaction.clear_target()
	if not restore_from_defeat:
		_level_entrance.play_door_open_sound()
	player.set_physics_process(false)
	input_buffer.clear_gameplay()
	_level_runtime.suspend_simulation()
	await _fade_to(1.0)
	_unbind_entity_context()
	player.unbind_space()
	_level_runtime.deactivate()
	player.global_position = _location_state.get_persisted_position()
	var world_spawn := world.voxel_model.get_spawn_position()
	world.resume()
	world_entity_coordinator.resume()
	overworld_loot.resume()
	_bind_entity_context(world.voxel_model, world_entity_coordinator.get_runtime(), world.is_position_streamed)
	player.bind_space(world.voxel_model, world, world_spawn, world.voxel_model)
	_location_state.return_to_world()
	if restore_from_defeat:
		_restore_player_from_defeat(player.global_position)
	game_environment.set_dungeon_music_active(false)
	game_environment.set_outdoor_presentation_enabled(true)
	overworld.visible = true
	hud.set_compass_available(true)
	_level_entrance.visible = true
	_reset_camera_position()
	_level_runtime.queue_free()
	_level_runtime = null
	_show_world_level_interaction()
	await _fade_to(0.0)
	player.set_physics_process(true)
	_level_transitioning = false

func _on_dungeon_one_time_reward_claimed(reward_id: StringName) -> void:
	if _slot_id != -1:
		game_session.save("dungeon_reward_claimed_%s" % reward_id)

func _show_world_level_interaction():
	if _level_entrance != null:
		level_interaction.set_target(_level_entrance.interaction_position, level_entrance_definition.enter_prompt)
		hud.set_compass_target(_level_entrance.global_position)

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
	if hud.is_chest_open():
		hud.close_chest()
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

func _request_import_structure() -> bool:
	if not _session_active or _level_transitioning or _structure_transitioning or player.is_defeated():
		return false
	return structure_designer_workflow.request_import()

func _request_export_structure() -> bool:
	if _structure_transitioning or _structure_designer_runtime == null:
		return false
	return structure_designer_workflow.request_export()

func _request_exit_structure() -> bool:
	if _structure_transitioning or _structure_designer_runtime == null:
		return false
	return structure_designer_workflow.request_exit()

func _spawn_debug_birds(variant_id: StringName, count: int) -> bool:
	return world_entity_coordinator.try_spawn_debug_birds(player.global_position, variant_id, count)

func _request_clear_current_dungeon_room() -> bool:
	if not _session_active or _level_transitioning or _structure_transitioning or _structure_designer_runtime != null:
		return false
	if player.is_defeated() or player.stats.is_dead():
		return false
	if _location_state == null or not _location_state.is_in_level() or _level_runtime == null:
		return false
	return _level_runtime.try_request_current_encounter_clear()

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
		world_entity_coordinator.is_suspended(),
		overworld.visible,
		game_environment.is_clock_paused(),
		game_environment.is_debug_panel_input_enabled(),
		player,
		camera_rig,
		camera_rig.camera,
		hud,
		level_interaction,
		_level_entrance != null and _level_entrance.visible
	)
	game_session.suspend_saving()
	game_environment.set_clock_paused(true)
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
	if in_level:
		_level_runtime.suspend_simulation()
		game_environment.set_dungeon_music_active(false)
	await _fade_to(1.0)
	watcher_encounter.set_presentation_enabled(false)
	if in_level:
		_level_runtime.deactivate()
	else:
		world.suspend()
		world_entity_coordinator.suspend()
		overworld.visible = false
		overworld_loot.suspend()
		game_environment.set_outdoor_presentation_enabled(false)
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
		game_environment.set_dungeon_music_active(true)
	else:
		game_environment.set_outdoor_presentation_enabled(true)
		if not snapshot.world_was_suspended:
			world.resume()
		if not snapshot.entities_were_suspended:
			world_entity_coordinator.resume()
			overworld_loot.resume()
		if _level_entrance != null:
			_level_entrance.visible = snapshot.entrance_visible
	overworld.visible = snapshot.overworld_visible
	player.process_mode = snapshot.player_process_mode
	player.visible = snapshot.player_visible
	camera_rig.process_mode = snapshot.camera_process_mode
	camera_rig.visible = snapshot.camera_visible
	camera_rig.camera.current = snapshot.gameplay_camera_current
	hud.process_mode = snapshot.hud_process_mode
	hud.visible = snapshot.hud_visible
	level_interaction.process_mode = snapshot.level_interaction_process_mode
	game_environment.set_clock_paused(snapshot.clock_was_paused)
	if snapshot.debug_panel_input_was_enabled:
		game_environment.restore_debug_panel_input()
	if not snapshot.saving_was_suspended:
		game_session.resume_saving()
	watcher_encounter.set_presentation_enabled(true)
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
	_sync_compass_external_menu()
	_sync_structure_designer_ui_blocking()

func _on_structure_dialog_open_state_changed(_open: bool) -> void:
	_sync_compass_external_menu()
	_sync_structure_designer_ui_blocking()

func _sync_compass_external_menu() -> void:
	hud.set_compass_external_menu_open(
		dev_console.is_open()
		or structure_designer_workflow.is_dialog_open()
		or (animation_tuning_panel != null and animation_tuning_panel.is_open())
		or (player_stats_debug_panel != null and player_stats_debug_panel.is_open())
		or game_environment.is_debug_panel_open()
		or (_pause_menu != null and is_instance_valid(_pause_menu))
		or (_death_screen != null and is_instance_valid(_death_screen))
	)

func _sync_structure_designer_ui_blocking() -> void:
	if _structure_designer_runtime == null:
		return
	_structure_designer_runtime.set_external_ui_blocked(dev_console.is_open() or structure_designer_workflow.is_dialog_open())

func _on_container_open_requested(position: Vector3i, definition: ContainerBlockDefinition):
	_try_open_container(position, definition)

func _try_open_container(position: Vector3i, definition: ContainerBlockDefinition) -> bool:
	if definition == null or _location_state == null:
		return false
	var coordinator: ChestTransferCoordinator = chest_coordinator
	if _location_state.is_in_level():
		if _level_runtime == null:
			return false
		coordinator = _level_runtime.get_chest_coordinator()
	if coordinator == null or not hud.open_container(coordinator, position, definition):
		return false
	input_buffer.clear_gameplay()
	return true

func _show_pause_menu():
	_pause_menu = pause_menu_scene.instantiate() as PauseMenu
	_pause_menu.resume_requested.connect(_resume_from_pause)
	_pause_menu.main_menu_requested.connect(_save_and_request_main_menu)
	add_child(_pause_menu)
	_pause_menu.setup(settings)
	_pause_menu.settings_screen.settings_changed.connect(_on_settings_changed)
	_save_canvas.visible = true
	_refresh_save_label()
	_sync_compass_external_menu()
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
	_sync_compass_external_menu()

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
	_unbind_entity_context()
	melee_combat.shutdown()
	overworld_loot.shutdown()
	world_entity_coordinator.shutdown()
	_teardown_level_runtime()
	world.shutdown()
	main_menu_requested.emit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _session_active:
		_restore_structure_designer_for_shutdown()
		_restore_player_from_defeat()
		_deactivate_session()
		game_session.shutdown("close")
		_unbind_entity_context()
		melee_combat.shutdown()
		overworld_loot.shutdown()
		world_entity_coordinator.shutdown()
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

func _bind_entity_context(space: VoxelSpace, runtime: EntityRuntime, position_ready: Callable) -> void:
	assert(space != null and runtime != null and position_ready.is_valid())
	_unbind_entity_context()
	player.bind_entity_runtime(runtime)
	slime_attachment_coordinator.bind_runtime(runtime)
	melee_combat.bind_context(space, runtime)
	arrow_projectiles.bind_context(space, runtime)
	enemy_combat_feedback.bind_runtime(runtime)
	watcher_encounter.bind_context(space, runtime, position_ready)
	runtime.entity_melee_contact_reached.connect(melee_combat.try_commit_entity_contact)
	runtime.entity_radial_contact_reached.connect(melee_combat.try_commit_entity_radial_contact)
	melee_combat.melee_outcome_committed.connect(runtime.record_melee_outcome)
	melee_combat.melee_outcome_committed.connect(watcher_encounter.record_melee_outcome)
	runtime.aggro_changed.connect(game_environment.set_combat_active)
	game_environment.set_combat_active(runtime.is_aggro_active())
	melee_combat.projectile_outcome_committed.connect(runtime.record_projectile_outcome)
	melee_combat.projectile_outcome_committed.connect(watcher_encounter.record_projectile_outcome)
	_active_entity_runtime = runtime

func _unbind_entity_context() -> void:
	if _active_entity_runtime == null:
		return
	if melee_combat.melee_outcome_committed.is_connected(watcher_encounter.record_melee_outcome):
		melee_combat.melee_outcome_committed.disconnect(watcher_encounter.record_melee_outcome)
	if melee_combat.projectile_outcome_committed.is_connected(watcher_encounter.record_projectile_outcome):
		melee_combat.projectile_outcome_committed.disconnect(watcher_encounter.record_projectile_outcome)
	watcher_encounter.unbind_context()
	slime_attachment_coordinator.unbind_runtime()
	if _active_entity_runtime.entity_melee_contact_reached.is_connected(melee_combat.try_commit_entity_contact):
		_active_entity_runtime.entity_melee_contact_reached.disconnect(melee_combat.try_commit_entity_contact)
	if _active_entity_runtime.entity_radial_contact_reached.is_connected(melee_combat.try_commit_entity_radial_contact):
		_active_entity_runtime.entity_radial_contact_reached.disconnect(melee_combat.try_commit_entity_radial_contact)
	if melee_combat.melee_outcome_committed.is_connected(_active_entity_runtime.record_melee_outcome):
		melee_combat.melee_outcome_committed.disconnect(_active_entity_runtime.record_melee_outcome)
	if _active_entity_runtime.aggro_changed.is_connected(game_environment.set_combat_active):
		_active_entity_runtime.aggro_changed.disconnect(game_environment.set_combat_active)
	game_environment.set_combat_active(false)
	if melee_combat.projectile_outcome_committed.is_connected(_active_entity_runtime.record_projectile_outcome):
		melee_combat.projectile_outcome_committed.disconnect(_active_entity_runtime.record_projectile_outcome)
	enemy_combat_feedback.unbind_runtime()
	arrow_projectiles.unbind_context()
	melee_combat.unbind_context()
	_active_entity_runtime = null

func _is_active_level_position_ready(_position: Vector3) -> bool:
	return _level_runtime != null
