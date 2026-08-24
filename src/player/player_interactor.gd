extends Node3D
class_name PlayerInteractor

const BOW_AIM_RAY_DISTANCE: float = 256.0

signal block_placed
signal block_mined(position: Vector3i, block_id: int)
signal mining_tool_requirement_failed(position: Vector3i, block_id: int, action: MiningActionDefinition)
signal crafting_station_open_requested(position: Vector3i, definition: CraftingStationBlockDefinition)
signal container_open_requested(position: Vector3i, definition: ContainerBlockDefinition)
signal melee_attack_started(action: MeleeAttackActionDefinition, direction: int)
signal melee_attack_impacted(action: MeleeAttackActionDefinition, position: Vector3)
signal melee_terrain_hit(position: Vector3i)
signal soil_tilled

@export var reach: float = 6.0
@export var place_cooldown: float = 0.18
@export var unarmed_primary_action: MiningActionDefinition

var voxel_space: VoxelSpace = null
var editable_voxel_world: VoxelWorld = null
var camera: Camera3D = null
var motor: PlayerMotor = null
var inventory_model: InventoryModel = null
var inventory_loadout: InventoryLoadoutCoordinator = null
var action_executors: PlayerActionExecutors = null
var combat: MeleeCombatCoordinator = null
var projectile_runtime: ArrowProjectileRuntime = null
var entity_runtime: EntityRuntime = null
var harvest: HarvestCoordinator = null
var item_consumption: ItemConsumptionCoordinator = null
var apple_planting: ApplePlantingCoordinator = null
var _input_buffer: InputBuffer = null
var _block_interaction_handler: Callable
var _block_break_validator: Callable
var _is_setup: bool = false

var target_block: Vector3i = Vector3i(-999, -999, -999)
var target_has: bool = false
var placement_block: Vector3i = Vector3i(-999, -999, -999)
var placement_has: bool = false
var last_ray_normal: Vector3i = Vector3i.UP
var can_primary_target: bool = false
var can_place_target: bool = false
var target_crafting_station: CraftingStationBlockDefinition = null
var target_container: ContainerBlockDefinition = null
var can_interact_target: bool = false
var pointer_over_ui: bool = false

var is_mining: bool = false
var mine_timer: float = 0.0
var mine_target: Vector3i = Vector3i(-999, -999, -999)
var mine_target_rev: int = -1
var mine_action: MiningActionDefinition
var mine_source: SelectedItemSource
var melee_attack_timer: float = 0.0
var melee_attack_queue: int = 0
var melee_attack_action: MeleeAttackActionDefinition
var melee_attack_elapsed: float = 0.0
var melee_chain_input_timer: float = 0.0
var next_melee_attack_direction: int = -1
var bow_draw_action: BowDrawActionDefinition
var bow_draw_elapsed: float = 0.0
var bow_draw_ammunition: ArrowItemDefinition
var _bow_source: SelectedItemSource
var _bow_aim_target: Vector3
var _bow_aim_target_valid: bool = false
var _bow_draw_requires_primary_release: bool = false
var secondary_use_timer: float = 0.0
var _secondary_use_consumed_until_release: bool = false
var _melee_contact_pending: bool = false
var _melee_impact_pending: bool = false
var _melee_attack_command: PreparedPlayerMeleeAttack
var _primary_consumption_latched: bool = false
var _primary_world_loot_latched: bool = false
var _primary_interaction_latched: bool = false
var _handle_hovered_world_loot_pickup: Callable
var _melee_locked_facing_direction: Vector3 = Vector3.ZERO
var _target_block_id: int = BlockId.Type.AIR
var _target_block_bounds := AABB()
var _target_cache_position := Vector3i(-999, -999, -999)
var _target_cache_revision: int = -1

func setup(
	p_camera: Camera3D,
	p_motor: PlayerMotor,
	p_inventory: InventoryModel,
	p_inventory_loadout: InventoryLoadoutCoordinator,
	p_action_executors: PlayerActionExecutors,
	p_input_buffer: InputBuffer,
	p_combat: MeleeCombatCoordinator,
	p_entity_runtime: EntityRuntime,
	p_block_interaction_handler: Callable = Callable(),
	p_block_break_validator: Callable = Callable(),
):
	assert(p_camera != null)
	assert(p_motor != null)
	assert(p_inventory != null)
	assert(p_inventory_loadout != null and p_inventory_loadout.inventory_model == p_inventory)
	assert(p_action_executors != null)
	assert(p_input_buffer != null)
	assert(p_combat != null)
	assert(p_entity_runtime != null)
	if _is_setup:
		assert(camera == p_camera)
		assert(motor == p_motor)
		assert(inventory_model == p_inventory)
		assert(inventory_loadout == p_inventory_loadout)
		assert(action_executors == p_action_executors)
		assert(_input_buffer == p_input_buffer)
		assert(combat == p_combat)
		assert(entity_runtime == p_entity_runtime)
		assert(_block_interaction_handler == p_block_interaction_handler)
		assert(_block_break_validator == p_block_break_validator)
		return
	camera = p_camera
	motor = p_motor
	inventory_model = p_inventory
	inventory_loadout = p_inventory_loadout
	action_executors = p_action_executors
	_input_buffer = p_input_buffer
	combat = p_combat
	entity_runtime = p_entity_runtime
	_block_interaction_handler = p_block_interaction_handler
	_block_break_validator = p_block_break_validator
	_is_setup = true

func bind_entity_runtime(p_entity_runtime: EntityRuntime) -> void:
	assert(_is_setup)
	assert(p_entity_runtime != null)
	_clear_active_state()
	entity_runtime = p_entity_runtime

func setup_harvesting(harvest_coordinator: HarvestCoordinator) -> void:
	assert(_is_setup)
	assert(harvest_coordinator != null)
	assert(harvest == null)
	harvest = harvest_coordinator

func setup_consumption(consumption_coordinator: ItemConsumptionCoordinator) -> void:
	assert(_is_setup)
	assert(consumption_coordinator != null)
	assert(item_consumption == null)
	item_consumption = consumption_coordinator

func setup_apple_planting(planting_coordinator: ApplePlantingCoordinator) -> void:
	assert(_is_setup)
	assert(planting_coordinator != null)
	assert(apple_planting == null)
	apple_planting = planting_coordinator

func setup_projectiles(p_projectile_runtime: ArrowProjectileRuntime) -> void:
	assert(_is_setup)
	assert(p_projectile_runtime != null)
	assert(projectile_runtime == null)
	projectile_runtime = p_projectile_runtime

func setup_world_loot_pickup(handle_hovered_world_loot_pickup: Callable) -> void:
	assert(handle_hovered_world_loot_pickup.is_valid())
	assert(not _handle_hovered_world_loot_pickup.is_valid())
	_handle_hovered_world_loot_pickup = handle_hovered_world_loot_pickup

func bind_space(p_space: VoxelSpace, p_editable_voxel_world: VoxelWorld = null):
	assert(_is_setup)
	assert(p_space != null)
	assert(p_editable_voxel_world == null or p_editable_voxel_world == p_space)
	_clear_active_state()
	voxel_space = p_space
	editable_voxel_world = p_editable_voxel_world
	if editable_voxel_world == null:
		action_executors.unbind_world()
	else:
		action_executors.bind_world(editable_voxel_world)

func unbind_space():
	_clear_active_state()
	action_executors.unbind_world()
	voxel_space = null
	editable_voxel_world = null

func is_editing_enabled() -> bool:
	return editable_voxel_world != null

func _clear_active_state():
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false
	target_crafting_station = null
	target_container = null
	can_interact_target = false
	_primary_consumption_latched = false
	_primary_world_loot_latched = false
	_primary_interaction_latched = false
	_target_cache_position = Vector3i(-999, -999, -999)
	_target_cache_revision = -1
	_bow_draw_requires_primary_release = false
	if harvest != null:
		harvest.clear_target()
	_reset_mining()
	_reset_melee_chain()
	_reset_bow_draw()
	secondary_use_timer = 0.0

func cancel_actions():
	_reset_mining()
	_reset_melee_chain()
	_reset_bow_draw()
	secondary_use_timer = 0.0
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false
	target_crafting_station = null
	target_container = null
	can_interact_target = false
	_primary_consumption_latched = false
	_primary_interaction_latched = false
	_bow_draw_requires_primary_release = false
	_primary_world_loot_latched = false
	if harvest != null:
		harvest.clear_target()

func _physics_process(delta):
	if voxel_space == null or motor == null or camera == null or inventory_model == null or _input_buffer == null:
		return
	if motor.is_defeated():
		return
	pointer_over_ui = UiUtils.is_pointer_over_ui(get_viewport())
	if pointer_over_ui:
		_clear_pointer_blocked_state()
		return
	_handle_raycast()
	_handle_item_actions(delta)
	_update_action_facing(delta)

func _handle_raycast():
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	var max_dist = ray_origin.distance_to(motor.global_position) + reach + 1.0
	_update_raycast(ray_origin, ray_dir, max_dist)

func _update_raycast(ray_origin: Vector3, ray_dir: Vector3, max_dist: float) -> void:
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false
	target_crafting_station = null
	target_container = null
	can_interact_target = false

	var selected_primary := get_selected_primary_action()
	var ignored_block := Callable(self, "_should_ignore_primary_target_block").bind(selected_primary)
	var hit := VoxelRaycast.cast(voxel_space, ray_origin, ray_dir, max_dist, ignored_block)
	if harvest != null and is_editing_enabled():
		harvest.update_target(ray_origin, ray_dir, max_dist, motor.global_position, reach)
		if harvest.has_target() and (hit == null or harvest.get_target_ray_distance() < hit.ray_distance):
			return
		harvest.clear_target()
	elif harvest != null:
		harvest.clear_target()
	if hit == null:
		return

	var best_hit := hit.target_cell
	var best_place := hit.placement_cell
	var best_normal := hit.face_normal
	var targeted_block_id := voxel_space.get_block_id_at(best_hit)
	if BlockId.is_foliage(targeted_block_id) and voxel_space.block_catalog.get_definition(targeted_block_id).is_replaceable:
		best_place = best_hit

	target_block = best_hit
	target_has = true
	_set_target_cache(best_hit, targeted_block_id, hit.interaction_bounds)
	last_ray_normal = best_normal
	placement_block = best_place

	var motor_pos = motor.global_position
	var reach_squared = reach * reach
	target_crafting_station = _get_target_crafting_station(targeted_block_id)
	target_container = _get_target_container(best_hit)
	can_interact_target = (target_crafting_station != null or target_container != null) and motor_pos.distance_squared_to(Vector3(best_hit) + Vector3(0.5, 0.5, 0.5)) <= reach_squared
	if selected_primary is MiningActionDefinition:
		can_primary_target = _can_mine_position(best_hit, selected_primary as MiningActionDefinition)
	elif selected_primary is TillingActionDefinition:
		can_primary_target = _can_till_position(best_hit, best_normal, selected_primary as TillingActionDefinition)

	var placement_action := get_selected_placement_action()
	if editable_voxel_world != null and placement_action != null:
		if placement_action.block.emplacement != null:
			var existing_id := voxel_space.get_block_id_at(best_place)
			if not editable_voxel_world.is_edit_protected(best_place) and (existing_id == BlockId.Type.AIR or voxel_space.block_catalog.get_definition(existing_id).is_replaceable):
				placement_has = true
				can_place_target = motor_pos.distance_squared_to(Vector3(best_place.x + 0.5, best_place.y + 0.5, best_place.z + 0.5)) <= reach_squared and _can_place_emplacement_geometry(best_place, placement_action.block)
		else:
			var placement_block_id := int(placement_action.block.id)
			var placement_attach_dir := _get_placement_attach_dir(placement_block_id)
			if editable_voxel_world.can_place_block(best_place, placement_block_id, placement_attach_dir) and not _placement_collides_player(best_place) and not _placement_collides_entity(best_place):
				placement_has = true
				can_place_target = motor_pos.distance_squared_to(Vector3(best_place.x + 0.5, best_place.y + 0.5, best_place.z + 0.5)) <= reach_squared

func _placement_collides_player(p: Vector3i) -> bool:
	if motor == null:
		return false
	return motor.get_world_bounds().intersects(AABB(Vector3(p), Vector3.ONE))

func _placement_collides_entity(position: Vector3i) -> bool:
	var block_bounds := AABB(Vector3(position), Vector3.ONE)
	return entity_runtime.has_entity_overlap(block_bounds)

func _can_place_emplacement_geometry(anchor: Vector3i, block: BlockDefinition) -> bool:
	if block.emplacement == null or not editable_voxel_world.can_place_emplacement(anchor, block.id):
		return false
	for offset in block.emplacement.occupied_offsets:
		var cell := anchor + offset
		if _placement_collides_player(cell) or _placement_collides_entity(cell):
			return false
	return true

func _handle_item_actions(delta):
	melee_chain_input_timer = max(0.0, melee_chain_input_timer - delta)
	secondary_use_timer -= delta
	var primary_use_just := _input_buffer.primary_use_just
	var primary_use_pressed := _input_buffer.primary_use_pressed
	_input_buffer.primary_use_just = false
	if _primary_world_loot_latched:
		if primary_use_pressed:
			primary_use_just = false
			primary_use_pressed = false
		else:
			_primary_world_loot_latched = false
	if primary_use_just and _handle_hovered_world_loot_pickup.is_valid() and bool(_handle_hovered_world_loot_pickup.call(reach)):
		_primary_world_loot_latched = primary_use_pressed
		primary_use_just = false
		primary_use_pressed = false
		_reset_mining()
		_reset_melee_chain()
	if _primary_consumption_latched:
		if primary_use_pressed:
			primary_use_just = false
			primary_use_pressed = false
		else:
			_primary_consumption_latched = false
	if _primary_interaction_latched:
		if primary_use_pressed:
			primary_use_just = false
			primary_use_pressed = false
		else:
			_primary_interaction_latched = false
	var selected_primary := get_selected_primary_action()
	var selected_mining := selected_primary as MiningActionDefinition
	var selected_melee := selected_primary as MeleeAttackActionDefinition
	var selected_tilling := selected_primary as TillingActionDefinition
	var selected_bow := selected_primary as BowDrawActionDefinition
	if primary_use_just and _try_activate_primary_interactable():
		_primary_interaction_latched = primary_use_pressed
		primary_use_just = false
		primary_use_pressed = false
		_reset_mining()
		_reset_melee_chain()
		_reset_bow_draw()
	if primary_use_just and item_consumption != null and item_consumption.has_consumable_at(inventory_model.get_equipped_slot()):
		item_consumption.try_consume_selected()
		_primary_consumption_latched = primary_use_pressed
		primary_use_just = false
		primary_use_pressed = false
		_reset_mining()
		_reset_melee_chain()
		_reset_bow_draw()
	if _bow_draw_requires_primary_release:
		if primary_use_pressed:
			primary_use_just = false
			primary_use_pressed = false
		else:
			_bow_draw_requires_primary_release = false
	if (
		selected_bow == null
		or bow_draw_action != null and bow_draw_action != selected_bow
		or _bow_source != null and not inventory_model.is_selected_item_source_current(_bow_source)
	):
		_reset_bow_draw()
	if primary_use_just and selected_bow != null:
		_start_bow_draw(selected_bow)
	if bow_draw_action != null and _input_buffer.secondary_use_just:
		_input_buffer.secondary_use_just = false
		_input_buffer.secondary_use_pressed = false
		_bow_draw_requires_primary_release = true
		_reset_bow_draw()
		primary_use_just = false
		primary_use_pressed = false
	if bow_draw_action != null:
		_update_bow_aim_target()
		if primary_use_pressed:
			bow_draw_elapsed = minf(bow_draw_elapsed + delta, bow_draw_action.raise_seconds + bow_draw_action.draw_seconds)
		else:
			_release_bow_shot()
			_reset_bow_draw()
		primary_use_just = false
		primary_use_pressed = false
		_reset_mining()
		_reset_melee_chain()
	if primary_use_just and target_has and selected_mining != null and _is_mining_blocked_by_tool(target_block, selected_mining):
		mining_tool_requirement_failed.emit(
			target_block,
			voxel_space.get_block_id_at(target_block),
			selected_mining,
		)
	if primary_use_pressed and target_has and can_primary_target and selected_mining != null:
		var selected_source := inventory_model.create_selected_item_source()
		if not is_mining:
			mine_target = target_block
			mine_target_rev = editable_voxel_world.get_revision(mine_target)
			mine_timer = 0.0
			mine_action = selected_mining
			mine_source = selected_source
			is_mining = true
		else:
			if mine_target != target_block or mine_action != selected_mining or not inventory_model.is_selected_item_source_current(mine_source):
				mine_target = target_block
				mine_target_rev = editable_voxel_world.get_revision(mine_target)
				mine_timer = 0.0
				mine_action = selected_mining
				mine_source = selected_source
			else:
				var cur_rev = editable_voxel_world.get_revision(mine_target)
				if cur_rev != mine_target_rev:
					_reset_mining()
				else:
					mine_timer += delta
					if mine_timer >= get_mine_duration():
						_commit_mine(mine_target, mine_source)
	else:
		if is_mining:
			_reset_mining()
	if selected_melee == null:
		_reset_melee_chain()
	elif melee_attack_action != null and melee_attack_action != selected_melee:
		_reset_melee_chain()
	elif _melee_attack_command != null and not combat.is_player_attack_source_current(_melee_attack_command):
		_reset_melee_chain()
	else:
		_advance_melee_attack(delta)
	if primary_use_just and selected_melee != null:
		melee_attack_action = selected_melee
		melee_attack_queue = 1
		melee_chain_input_timer = selected_melee.chain_input_window
	if melee_attack_queue > 0 and melee_chain_input_timer <= 0.0:
		melee_attack_queue = 0
	if melee_attack_timer <= 0.0:
		if melee_attack_queue > 0 and melee_attack_action == selected_melee:
			melee_attack_queue -= 1
			_start_melee_attack()
		else:
			_reset_melee_chain()
	if primary_use_just and target_has and selected_tilling != null:
		_commit_till(
			target_block,
			last_ray_normal,
			selected_tilling,
			inventory_model.create_selected_item_source(),
		)

	if _secondary_use_consumed_until_release:
		_input_buffer.secondary_use_just = false
		if _input_buffer.secondary_use_physical_pressed:
			return
		_secondary_use_consumed_until_release = false
	if _input_buffer.secondary_use_just and item_consumption != null and item_consumption.has_consumable_at(inventory_model.get_equipped_slot()):
		_input_buffer.secondary_use_just = false
		item_consumption.try_consume_selected()
		_secondary_use_consumed_until_release = _input_buffer.secondary_use_physical_pressed
		return
	var selected_planting := get_selected_planting_action()
	if _input_buffer.secondary_use_just and secondary_use_timer <= 0.0 and selected_planting != null:
		var soil_position := _get_planting_soil_position()
		if apple_planting != null and soil_position.y >= 0 and apple_planting.try_plant(editable_voxel_world, soil_position, inventory_model.create_selected_item_source()):
			_input_buffer.secondary_use_just = false
			secondary_use_timer = place_cooldown
			return
	if (
		_input_buffer.secondary_use_just
		and secondary_use_timer <= 0.0
		and target_has
		and _block_interaction_handler.is_valid()
		and bool(_block_interaction_handler.call(target_block))
	):
		_input_buffer.secondary_use_just = false
		_secondary_use_consumed_until_release = true
		secondary_use_timer = place_cooldown
		return
	var selected_placement := get_selected_placement_action()
	if (_input_buffer.secondary_use_just or _input_buffer.secondary_use_pressed) and secondary_use_timer <= 0.0:
		_input_buffer.secondary_use_just = false
		if _can_place(selected_placement):
			_commit_place(placement_block, selected_placement)
			secondary_use_timer = place_cooldown

func _reset_mining():
	is_mining = false
	mine_timer = 0.0
	mine_target = Vector3i(-999, -999, -999)
	mine_target_rev = -1
	mine_action = null
	mine_source = null

func _clear_pointer_blocked_state() -> void:
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false
	target_crafting_station = null
	target_container = null
	can_interact_target = false
	if harvest != null:
		harvest.clear_target()
	_reset_mining()
	_reset_melee_chain()
	_reset_bow_draw()
	_input_buffer.primary_use_just = false
	_input_buffer.secondary_use_just = false

func _try_activate_primary_interactable() -> bool:
	if harvest != null and harvest.has_target():
		harvest.try_harvest_target()
		return true
	var should_mine_target := is_attempting_container_mining() or is_attempting_crafting_station_mining()
	if not should_mine_target and _try_open_target_container():
		return true
	return not should_mine_target and _try_open_target_crafting_station()

func _reset_melee_chain():
	_melee_contact_pending = false
	_melee_impact_pending = false
	_melee_attack_command = null
	_melee_locked_facing_direction = Vector3.ZERO
	melee_attack_timer = 0.0
	melee_attack_elapsed = 0.0
	melee_attack_queue = 0
	melee_attack_action = null
	melee_chain_input_timer = 0.0
	next_melee_attack_direction = -1

func _start_bow_draw(action: BowDrawActionDefinition) -> void:
	assert(action != null)
	if projectile_runtime == null:
		return
	var ammunition := projectile_runtime.get_available_ammunition(action)
	if ammunition == null:
		return
	bow_draw_action = action
	bow_draw_elapsed = 0.0
	bow_draw_ammunition = ammunition
	_bow_source = inventory_model.create_selected_item_source()
	_bow_aim_target = motor.global_position + motor.get_facing_direction() * 10.0
	_bow_aim_target_valid = true
	_reset_mining()
	_reset_melee_chain()

func _reset_bow_draw() -> void:
	bow_draw_action = null
	bow_draw_elapsed = 0.0
	bow_draw_ammunition = null
	_bow_source = null
	_bow_aim_target_valid = false

func _release_bow_shot() -> void:
	if bow_draw_action == null or bow_draw_ammunition == null or projectile_runtime == null:
		return
	projectile_runtime.try_fire(
		_bow_source,
		bow_draw_action,
		bow_draw_ammunition,
		get_bow_draw_progress(),
		get_bow_release_transform(),
	)

func is_drawing_bow() -> bool:
	return bow_draw_action != null

func get_bow_raise_progress() -> float:
	if bow_draw_action == null:
		return 0.0
	return clampf(bow_draw_elapsed / bow_draw_action.raise_seconds, 0.0, 1.0)

func get_bow_draw_progress() -> float:
	if bow_draw_action == null:
		return 0.0
	return clampf((bow_draw_elapsed - bow_draw_action.raise_seconds) / bow_draw_action.draw_seconds, 0.0, 1.0)

func get_bow_ammunition_scene() -> PackedScene:
	return null if bow_draw_ammunition == null else bow_draw_ammunition.held_scene

func get_bow_release_transform() -> Transform3D:
	assert(bow_draw_action != null and bow_draw_ammunition != null and _bow_aim_target_valid)
	return bow_draw_action.get_projectile_release_transform(
		motor.global_position,
		motor.get_facing_direction(),
		_bow_aim_target,
		get_bow_draw_progress(),
		bow_draw_ammunition.projectile_profile.gravity,
	)

func get_bow_launch_direction() -> Vector3:
	return get_bow_release_transform().basis.y.normalized()

func _update_bow_aim_target() -> void:
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position).normalized()
	var cursor_target: Variant = _get_bow_cursor_target(ray_origin, ray_direction)
	if not cursor_target is Vector3:
		return
	var target := cursor_target as Vector3
	if not target.is_finite():
		return
	_bow_aim_target = target
	_bow_aim_target_valid = true
	var cursor_direction := Vector3(target.x - motor.global_position.x, 0.0, target.z - motor.global_position.z).normalized()
	if not cursor_direction.is_zero_approx():
		motor.face_direction(cursor_direction)

func _get_bow_cursor_target(ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	var voxel_hit := VoxelRaycast.cast(voxel_space, ray_origin, ray_direction, BOW_AIM_RAY_DISTANCE, _is_foliage)
	var ground_hit: Variant = Plane(Vector3.UP, motor.global_position.y).intersects_ray(ray_origin, ray_direction)
	var nearest_surface_distance := BOW_AIM_RAY_DISTANCE
	if voxel_hit != null:
		nearest_surface_distance = minf(nearest_surface_distance, voxel_hit.ray_distance)
	if ground_hit is Vector3:
		nearest_surface_distance = minf(nearest_surface_distance, ray_origin.distance_to(ground_hit as Vector3))
	var entity_hit: Variant = null
	if entity_runtime != null:
		entity_hit = entity_runtime.get_nearest_combat_target_ray_hit(ray_origin, ray_direction, nearest_surface_distance)
	if entity_hit is Vector3 and (voxel_hit == null or ray_origin.distance_to(entity_hit as Vector3) < voxel_hit.ray_distance):
		return entity_hit
	if voxel_hit != null:
		return ray_origin + ray_direction * voxel_hit.ray_distance
	return ground_hit

func _should_ignore_primary_target_block(block_id: int, selected_primary: ItemActionDefinition) -> bool:
	if not BlockId.is_foliage(block_id):
		return false
	var mining_action := selected_primary as MiningActionDefinition
	return mining_action == null or not mining_action.can_mine(voxel_space.block_catalog.get_definition(block_id))

func _is_foliage(block_id: int) -> bool:
	return BlockId.is_foliage(block_id)

func _start_melee_attack():
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position).normalized()
	_melee_attack_command = combat.prepare_player_attack(
		inventory_model.create_selected_item_source(),
		ray_origin,
		ray_direction,
	)
	if _melee_attack_command == null:
		_reset_melee_chain()
		return
	melee_attack_action = _melee_attack_command.get_action()
	var profile := _melee_attack_command.get_profile()
	melee_attack_timer = profile.cooldown
	melee_attack_elapsed = 0.0
	melee_chain_input_timer = 0.0
	var cursor_direction := _get_cursor_planar_direction(ray_origin, ray_direction)
	if not cursor_direction.is_zero_approx():
		motor.face_direction(cursor_direction)
	_melee_locked_facing_direction = Vector3(
		sin(motor.model_root.rotation.y), 0.0, cos(motor.model_root.rotation.y)
	)
	_melee_contact_pending = profile.acquire_targets_on_contact or _melee_attack_command.has_targets()
	_melee_impact_pending = true
	var attack_direction := next_melee_attack_direction
	next_melee_attack_direction = -next_melee_attack_direction
	melee_attack_started.emit(melee_attack_action, attack_direction)
	if melee_attack_action.animation_style == MeleeAttackActionDefinition.AnimationStyle.SWEEP and target_has and voxel_space != null and voxel_space.is_solid(target_block):
		melee_terrain_hit.emit(target_block)
	if is_zero_approx(profile.contact_time):
		_commit_melee_impact()

func _advance_melee_attack(delta: float):
	if melee_attack_action == null or _melee_attack_command == null or melee_attack_timer <= 0.0:
		return
	if not combat.is_player_attack_source_current(_melee_attack_command):
		_reset_melee_chain()
		return
	var profile := _melee_attack_command.get_profile()
	var previous_elapsed := melee_attack_elapsed
	melee_attack_elapsed = minf(melee_attack_elapsed + delta, profile.duration)
	melee_attack_timer = maxf(melee_attack_timer - delta, 0.0)
	if (_melee_impact_pending or _melee_contact_pending) and previous_elapsed < profile.contact_time and melee_attack_elapsed >= profile.contact_time:
		_commit_melee_impact()

func _update_action_facing(delta: float):
	if pointer_over_ui:
		return
	var selected_primary := get_selected_primary_action()
	if selected_primary is BowDrawActionDefinition:
		if is_drawing_bow():
			var bow_cursor_direction := Vector3(_bow_aim_target.x - motor.global_position.x, 0.0, _bow_aim_target.z - motor.global_position.z).normalized()
			if not bow_cursor_direction.is_zero_approx():
				motor.face_direction(bow_cursor_direction)
			return
	elif not selected_primary is MeleeAttackActionDefinition:
		return
	if melee_attack_action != null and melee_attack_timer > 0.0 and melee_attack_elapsed < melee_attack_action.attack_profile.duration:
		motor.face_direction(_melee_locked_facing_direction)
		return
	if motor.is_sprinting:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_position)
	var ray_direction := camera.project_ray_normal(mouse_position).normalized()
	var cursor_direction := _get_cursor_planar_direction(ray_origin, ray_direction)
	if cursor_direction.is_zero_approx():
		return
	motor.turn_toward_direction(cursor_direction, delta)

func _get_cursor_planar_direction(ray_origin: Vector3, ray_direction: Vector3) -> Vector3:
	var player_center := motor.get_world_bounds().get_center()
	var cursor_position: Variant = Plane(Vector3.UP, player_center.y).intersects_ray(ray_origin, ray_direction)
	if not cursor_position is Vector3:
		return Vector3.ZERO
	var cursor_direction := (cursor_position as Vector3) - player_center
	cursor_direction.y = 0.0
	if not cursor_direction.is_finite() or cursor_direction.is_zero_approx():
		return Vector3.ZERO
	return cursor_direction.normalized()

func _commit_melee_impact():
	if _melee_attack_command == null or melee_attack_action == null:
		return
	if not combat.is_player_attack_source_current(_melee_attack_command):
		_reset_melee_chain()
		return
	var action := melee_attack_action
	var command := _melee_attack_command
	var commit_contacts := _melee_contact_pending
	_melee_impact_pending = false
	_melee_contact_pending = false
	var profile := action.attack_profile
	var impact_position := _get_melee_impact_position(profile)
	var combat_origin := impact_position if profile.impact_origin_forward_offset > 0.0 else Vector3.INF
	if commit_contacts:
		combat.try_commit_player_attack(command, combat_origin)
	melee_attack_impacted.emit(action, impact_position)

func _get_melee_impact_position(profile: MeleeAttackProfile) -> Vector3:
	var forward := _melee_locked_facing_direction
	if forward.is_zero_approx():
		forward = motor.model_root.global_transform.basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		forward = Vector3.BACK
	else:
		forward = forward.normalized()
	return motor.global_position + forward * profile.impact_origin_forward_offset + Vector3.UP * 0.04

func _can_mine_position(pos: Vector3i, action: MiningActionDefinition) -> bool:
	if action == null or voxel_space == null or editable_voxel_world == null or motor == null:
		return false
	if editable_voxel_world.is_edit_protected(pos):
		return false
	var bounds := get_target_block_bounds() if target_has and target_block == pos else voxel_space.get_interaction_bounds(pos)
	var center := bounds.get_center()
	if motor.global_position.distance_squared_to(center) > reach * reach:
		return false
	if _block_break_validator.is_valid() and not bool(_block_break_validator.call(pos)):
		return false
	var block_id := get_target_block_id() if target_has and target_block == pos else voxel_space.get_block_id_at(pos)
	if block_id == BlockId.Type.AIR:
		return false
	return action.can_mine(voxel_space.block_catalog.get_definition(block_id))

func _is_mining_blocked_by_tool(pos: Vector3i, action: MiningActionDefinition) -> bool:
	if action == null or voxel_space == null or editable_voxel_world == null or motor == null:
		return false
	if editable_voxel_world.is_edit_protected(pos):
		return false
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if motor.global_position.distance_squared_to(center) > reach * reach:
		return false
	if _block_break_validator.is_valid() and not bool(_block_break_validator.call(pos)):
		return false
	var block_id := voxel_space.get_block_id_at(pos)
	if block_id == BlockId.Type.AIR:
		return false
	return not action.can_mine(voxel_space.block_catalog.get_definition(block_id))

func _can_till_position(pos: Vector3i, face_normal: Vector3i, action: TillingActionDefinition) -> bool:
	if action == null or voxel_space == null or editable_voxel_world == null or motor == null:
		return false
	if editable_voxel_world.is_edit_protected(pos):
		return false
	if get_selected_primary_action() != action or face_normal != Vector3i.UP:
		return false
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if motor.global_position.distance_squared_to(center) > reach * reach:
		return false
	if voxel_space.get_block_id_at(pos + Vector3i.UP) != BlockId.Type.AIR:
		return false
	var block_id := voxel_space.get_block_id_at(pos)
	if block_id == BlockId.Type.AIR:
		return false
	return action.can_till(voxel_space.block_catalog.get_definition(block_id))

func _commit_till(
	pos: Vector3i,
	face_normal: Vector3i,
	action: TillingActionDefinition,
	source: SelectedItemSource,
) -> void:
	if not _can_till_position(pos, face_normal, action):
		return
	var edit := action_executors.tilling.try_till(pos, source)
	if edit.is_success():
		soil_tilled.emit()
		_handle_raycast()

func get_mine_duration() -> float:
	assert(is_mining and mine_action != null)
	var block_id := get_target_block_id() if target_has and target_block == mine_target else voxel_space.get_block_id_at(mine_target)
	var block := voxel_space.block_catalog.get_definition(block_id)
	if block.container != null:
		var pickaxe_stat := mine_action.get_tool_stat(&"pickaxe")
		assert(pickaxe_stat != null)
		return block.mine_duration / pickaxe_stat.speed_multiplier
	return mine_action.get_mine_duration(block)

func has_mining_impact_target() -> bool:
	return is_mining and target_has and can_primary_target and mine_target == target_block

func get_mining_impact_position() -> Vector3:
	assert(has_mining_impact_target())
	var bounds := get_target_block_bounds()
	var normal := Vector3(last_ray_normal)
	var face_offset := Vector3(normal.x * bounds.size.x, normal.y * bounds.size.y, normal.z * bounds.size.z) * 0.5
	return bounds.get_center() + face_offset + normal * 0.06

func get_target_block_bounds() -> AABB:
	assert(target_has and voxel_space != null)
	_ensure_target_cache()
	return _target_block_bounds

func get_target_block_id() -> int:
	assert(target_has and voxel_space != null)
	_ensure_target_cache()
	return _target_block_id

func _set_target_cache(position: Vector3i, block_id: int, bounds: AABB) -> void:
	_target_cache_position = position
	_target_block_id = block_id
	_target_block_bounds = bounds
	_target_cache_revision = editable_voxel_world.get_revision(position) if editable_voxel_world != null else -1

func _ensure_target_cache() -> void:
	var revision := editable_voxel_world.get_revision(target_block) if editable_voxel_world != null else -1
	if _target_cache_position == target_block and _target_cache_revision == revision:
		return
	_set_target_cache(target_block, voxel_space.get_block_id_at(target_block), voxel_space.get_interaction_bounds(target_block))

func get_mining_impact_normal() -> Vector3i:
	assert(has_mining_impact_target())
	return last_ray_normal

func get_mining_impact_block_id() -> int:
	assert(has_mining_impact_target())
	return get_target_block_id()

func _can_place(action: BlockPlacementActionDefinition) -> bool:
	if not placement_has or not can_place_target:
		return false
	return _validate_placement(placement_block, action)

func _validate_placement(position: Vector3i, action: BlockPlacementActionDefinition) -> bool:
	if action == null or voxel_space == null or editable_voxel_world == null or inventory_model == null or motor == null:
		return false
	if get_selected_placement_action() != action or not inventory_loadout.can_consume_selected():
		return false
	var block_id := int(action.block.id)
	var attach_dir := _get_placement_attach_dir(block_id)
	if action.block.emplacement == null and not editable_voxel_world.can_place_block(position, block_id, attach_dir):
		return false
	var center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
	if motor.global_position.distance_squared_to(center) > reach * reach:
		return false
	if action.block.emplacement != null:
		return _can_place_emplacement_geometry(position, action.block)
	return not _placement_collides_player(position) and not _placement_collides_entity(position)

func _commit_mine(pos: Vector3i, source: SelectedItemSource):
	if not inventory_model.is_selected_item_source_current(source):
		_reset_mining()
		return
	var action := get_selected_primary_action() as MiningActionDefinition
	if not _can_mine_position(pos, action):
		_reset_mining()
		return
	var mined_block_id := voxel_space.get_block_id_at(pos)
	_reset_mining()
	var batch := action_executors.mining.try_mine(pos, source)
	if batch is Array and batch.size() > 0 and batch[0] is BlockEdit:
		if not (batch[0] as BlockEdit).is_success():
			return
		block_mined.emit(pos, mined_block_id)
	_handle_raycast()

func _commit_place(pos: Vector3i, action: BlockPlacementActionDefinition):
	if not _validate_placement(pos, action):
		return

	var block_id := int(action.block.id)

	var attach_dir := _get_placement_attach_dir(block_id)
	var edit := action_executors.placement.try_place(
		pos,
		attach_dir,
		inventory_model.create_selected_item_source(),
	)

	if edit.is_success():
		_handle_raycast()
		block_placed.emit()

func _get_placement_attach_dir(block_id: int) -> Vector3i:
	return -last_ray_normal if block_id == BlockId.Type.TORCH else Vector3i.ZERO

func get_selected_block_id():
	var action := get_selected_placement_action()
	if action == null:
		return null
	return int(action.block.id)

func has_harvest_target() -> bool:
	return harvest != null and harvest.has_target()

func can_harvest_target() -> bool:
	return has_harvest_target() and harvest.can_harvest_target()

func get_harvest_target_bounds() -> AABB:
	assert(has_harvest_target())
	return harvest.get_target_bounds()

func get_selected_primary_action() -> ItemActionDefinition:
	if inventory_model == null:
		return unarmed_primary_action
	var item_id = inventory_model.get_selected_item_id()
	if item_id == null:
		return unarmed_primary_action
	return inventory_model.item_catalog.get_definition(item_id).primary_action

func get_selected_placement_action() -> BlockPlacementActionDefinition:
	if inventory_model == null:
		return null
	var item_id = inventory_model.get_selected_item_id()
	if item_id == null:
		return null
	var action := inventory_model.item_catalog.get_definition(item_id).secondary_action
	return action as BlockPlacementActionDefinition

func get_selected_planting_action() -> PlantingActionDefinition:
	if inventory_model == null:
		return null
	var item_id = inventory_model.get_selected_item_id()
	if item_id == null:
		return null
	return inventory_model.item_catalog.get_definition(item_id).secondary_action as PlantingActionDefinition

func _get_planting_soil_position() -> Vector3i:
	if not target_has or voxel_space == null or editable_voxel_world == null or motor == null or last_ray_normal != Vector3i.UP:
		return Vector3i(-1, -1, -1)
	var center := Vector3(target_block) + Vector3(0.5, 1.0, 0.5)
	return target_block if motor.global_position.distance_squared_to(center) <= reach * reach else Vector3i(-1, -1, -1)

func has_crafting_station_target() -> bool:
	return target_has and target_crafting_station != null

func is_attempting_crafting_station_mining() -> bool:
	var action := get_selected_primary_action() as MiningActionDefinition
	return has_crafting_station_target() and can_primary_target and action != null and action.get_tool_stat(&"pickaxe") != null

func _get_target_crafting_station(block_id: int) -> CraftingStationBlockDefinition:
	if editable_voxel_world == null:
		return null
	return voxel_space.block_catalog.get_definition(block_id).crafting_station

func _try_open_target_crafting_station() -> bool:
	if not has_crafting_station_target() or not can_interact_target:
		return false
	crafting_station_open_requested.emit(target_block, target_crafting_station)
	return true

func has_container_target() -> bool:
	return target_has and target_container != null

func is_attempting_container_mining() -> bool:
	var action := get_selected_primary_action() as MiningActionDefinition
	return editable_voxel_world != null and has_container_target() and can_primary_target and action != null and action.get_tool_stat(&"pickaxe") != null

func _get_target_container(position: Vector3i) -> ContainerBlockDefinition:
	if voxel_space == null:
		return null
	return voxel_space.block_catalog.get_definition(voxel_space.get_block_id_at(position)).container

func _try_open_target_container() -> bool:
	if not target_has or target_container == null or not can_interact_target:
		return false
	container_open_requested.emit(target_block, target_container)
	return true
