extends Node3D
class_name PlayerInteractor

signal block_placed
signal melee_attack_started(action: MeleeAttackActionDefinition, direction: int)
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
var combat: MeleeCombatCoordinator = null
var entity_coordinator: EntityCoordinator = null
var pumpkin_harvest: PumpkinHarvestCoordinator = null
var _input_buffer: InputBuffer = null
var _is_setup: bool = false

var target_block: Vector3i = Vector3i(-999, -999, -999)
var target_has: bool = false
var placement_block: Vector3i = Vector3i(-999, -999, -999)
var placement_has: bool = false
var last_ray_normal: Vector3i = Vector3i.UP
var can_primary_target: bool = false
var can_place_target: bool = false
var pointer_over_ui: bool = false

var is_mining: bool = false
var mine_timer: float = 0.0
var mine_target: Vector3i = Vector3i(-999, -999, -999)
var mine_target_rev: int = -1
var mine_action: MiningActionDefinition
var melee_attack_timer: float = 0.0
var melee_attack_queue: int = 0
var melee_attack_action: MeleeAttackActionDefinition
var melee_attack_elapsed: float = 0.0
var melee_chain_input_timer: float = 0.0
var next_melee_attack_direction: int = -1
var secondary_use_timer: float = 0.0
var _ray_hit_pos: Vector3i
var _ray_place_pos: Vector3i
var _ray_face_normal: Vector3i
var _ray_hit_distance: float = INF
var _melee_target_runtime_ids: Array[int] = []
var _melee_contact_pending: bool = false
var _melee_ray_origin: Vector3
var _melee_ray_direction: Vector3
var _melee_source_item_id: StringName = &""
var _primary_harvest_latched: bool = false

func setup(p_camera: Camera3D, p_motor: PlayerMotor, p_inventory: InventoryModel, p_input_buffer: InputBuffer, p_combat: MeleeCombatCoordinator, p_entity_coordinator: EntityCoordinator):
	assert(p_camera != null)
	assert(p_motor != null)
	assert(p_inventory != null)
	assert(p_input_buffer != null)
	assert(p_combat != null)
	assert(p_entity_coordinator != null)
	if _is_setup:
		assert(camera == p_camera)
		assert(motor == p_motor)
		assert(inventory_model == p_inventory)
		assert(_input_buffer == p_input_buffer)
		assert(combat == p_combat)
		assert(entity_coordinator == p_entity_coordinator)
		return
	camera = p_camera
	motor = p_motor
	inventory_model = p_inventory
	_input_buffer = p_input_buffer
	combat = p_combat
	entity_coordinator = p_entity_coordinator
	_is_setup = true

func setup_harvesting(pumpkin_harvest_coordinator: PumpkinHarvestCoordinator) -> void:
	assert(_is_setup)
	assert(pumpkin_harvest_coordinator != null)
	assert(pumpkin_harvest == null)
	pumpkin_harvest = pumpkin_harvest_coordinator

func bind_space(p_space: VoxelSpace, p_editable_voxel_world: VoxelWorld = null):
	assert(_is_setup)
	assert(p_space != null)
	assert(p_editable_voxel_world == null or p_editable_voxel_world == p_space)
	_clear_active_state()
	voxel_space = p_space
	editable_voxel_world = p_editable_voxel_world

func unbind_space():
	_clear_active_state()
	voxel_space = null
	editable_voxel_world = null

func is_editing_enabled() -> bool:
	return editable_voxel_world != null

func _clear_active_state():
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false
	_primary_harvest_latched = false
	if pumpkin_harvest != null:
		pumpkin_harvest.clear_target()
	_reset_mining()
	_reset_melee_chain()
	secondary_use_timer = 0.0

func cancel_actions():
	_reset_mining()
	_reset_melee_chain()
	secondary_use_timer = 0.0
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false
	_primary_harvest_latched = false
	if pumpkin_harvest != null:
		pumpkin_harvest.clear_target()

func _physics_process(delta):
	if voxel_space == null or motor == null or camera == null or inventory_model == null or _input_buffer == null:
		return
	if motor.is_defeated():
		return
	pointer_over_ui = UiUtils.is_pointer_over_ui(get_viewport())
	if pointer_over_ui:
		target_has = false
		placement_has = false
		can_primary_target = false
		can_place_target = false
		if pumpkin_harvest != null:
			pumpkin_harvest.clear_target()
		if is_mining:
			_reset_mining()
		_reset_melee_chain()
		_input_buffer.primary_use_just = false
		_input_buffer.secondary_use_just = false
		return
	_handle_raycast()
	_handle_item_actions(delta)

func _handle_raycast():
	target_has = false
	placement_has = false
	can_primary_target = false
	can_place_target = false

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var max_dist = ray_origin.distance_to(motor.global_position) + reach + 1.0
	var has_voxel_hit := _voxel_raycast(ray_origin, ray_dir, max_dist)
	if pumpkin_harvest != null and is_editing_enabled():
		pumpkin_harvest.update_target(ray_origin, ray_dir, max_dist, motor.global_position, reach)
		if pumpkin_harvest.has_target() and (not has_voxel_hit or pumpkin_harvest.get_target_ray_distance() < _ray_hit_distance):
			return
		pumpkin_harvest.clear_target()
	elif pumpkin_harvest != null:
		pumpkin_harvest.clear_target()
	if not has_voxel_hit:
		return

	var best_hit = _ray_hit_pos
	var best_place = _ray_place_pos
	var best_normal = _ray_face_normal

	target_block = best_hit
	target_has = true
	last_ray_normal = best_normal
	placement_block = best_place

	var motor_pos = motor.global_position
	var reach_squared = reach * reach
	var selected_primary := get_selected_primary_action()
	if selected_primary is MiningActionDefinition:
		can_primary_target = _can_mine_position(best_hit, selected_primary as MiningActionDefinition)
	elif selected_primary is TillingActionDefinition:
		can_primary_target = _can_till_position(best_hit, best_normal, selected_primary as TillingActionDefinition)

	if editable_voxel_world != null and not editable_voxel_world.is_edit_protected(best_place) and voxel_space.get_block_at(best_place) == null:
		if not _placement_collides_player(best_place) and not _placement_collides_entity(best_place):
			placement_has = true
			can_place_target = motor_pos.distance_squared_to(Vector3(best_place.x + 0.5, best_place.y + 0.5, best_place.z + 0.5)) <= reach_squared
	else:
		placement_has = false
		can_place_target = false

func _voxel_raycast(origin: Vector3, dir: Vector3, max_dist: float) -> bool:
	dir = dir.normalized()
	if dir.length_squared() < 0.0001:
		return false
	var current = Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))
	var can_hit := not voxel_space.is_raycast_solid(current)

	var step_x = 1 if dir.x >= 0 else -1
	var step_y = 1 if dir.y >= 0 else -1
	var step_z = 1 if dir.z >= 0 else -1

	var t_max_x: float
	var t_max_y: float
	var t_max_z: float
	var t_delta_x: float
	var t_delta_y: float
	var t_delta_z: float

	var frac_x = origin.x - floor(origin.x)
	var frac_y = origin.y - floor(origin.y)
	var frac_z = origin.z - floor(origin.z)

	if dir.x != 0:
		t_delta_x = abs(1.0 / dir.x)
		t_max_x = (1.0 - frac_x) * t_delta_x if step_x > 0 else frac_x * t_delta_x
	else:
		t_max_x = 999999.0
		t_delta_x = 999999.0

	if dir.y != 0:
		t_delta_y = abs(1.0 / dir.y)
		t_max_y = (1.0 - frac_y) * t_delta_y if step_y > 0 else frac_y * t_delta_y
	else:
		t_max_y = 999999.0
		t_delta_y = 999999.0

	if dir.z != 0:
		t_delta_z = abs(1.0 / dir.z)
		t_max_z = (1.0 - frac_z) * t_delta_z if step_z > 0 else frac_z * t_delta_z
	else:
		t_max_z = 999999.0
		t_delta_z = 999999.0

	var traveled = 0.0
	var last_pos = current

	for _i in range(int(max_dist * 2 + 10)):
		var current_is_solid := voxel_space.is_raycast_solid(current)
		if current_is_solid and can_hit:
			var face_normal: Vector3i
			if last_pos.x != current.x:
				face_normal = Vector3i(-step_x, 0, 0)
			elif last_pos.y != current.y:
				face_normal = Vector3i(0, -step_y, 0)
			else:
				face_normal = Vector3i(0, 0, -step_z)
			if voxel_space.is_face_targetable(current, face_normal):
				var place_pos = last_pos
				if voxel_space.is_raycast_solid(place_pos):
					place_pos = current + face_normal
				_ray_hit_pos = current
				_ray_place_pos = place_pos
				_ray_face_normal = face_normal
				_ray_hit_distance = traveled
				return true
		elif not current_is_solid:
			can_hit = true

		if t_max_x < t_max_y:
			if t_max_x < t_max_z:
				last_pos = current
				current.x += step_x
				traveled = t_max_x
				t_max_x += t_delta_x
			else:
				last_pos = current
				current.z += step_z
				traveled = t_max_z
				t_max_z += t_delta_z
		else:
			if t_max_y < t_max_z:
				last_pos = current
				current.y += step_y
				traveled = t_max_y
				t_max_y += t_delta_y
			else:
				last_pos = current
				current.z += step_z
				traveled = t_max_z
				t_max_z += t_delta_z

		if traveled > max_dist:
			break
	return false

func _placement_collides_player(p: Vector3i) -> bool:
	if motor == null:
		return false
	var pw = motor.player_width
	var ph = motor.player_height
	var min_a = Vector3(motor.global_position.x - pw * 0.5, motor.global_position.y, motor.global_position.z - pw * 0.5)
	var max_a = Vector3(motor.global_position.x + pw * 0.5, motor.global_position.y + ph, motor.global_position.z + pw * 0.5)
	var bmin = Vector3(float(p.x), float(p.y), float(p.z))
	var bmax = bmin + Vector3(1, 1, 1)
	if max_a.x <= bmin.x or min_a.x >= bmax.x:
		return false
	if max_a.y <= bmin.y or min_a.y >= bmax.y:
		return false
	if max_a.z <= bmin.z or min_a.z >= bmax.z:
		return false
	return true

func _placement_collides_entity(position: Vector3i) -> bool:
	var block_bounds := AABB(Vector3(position), Vector3.ONE)
	return entity_coordinator.has_entity_overlap(block_bounds)

func _handle_item_actions(delta):
	melee_chain_input_timer = max(0.0, melee_chain_input_timer - delta)
	secondary_use_timer -= delta
	var primary_use_just := _input_buffer.primary_use_just
	var primary_use_pressed := _input_buffer.primary_use_pressed
	_input_buffer.primary_use_just = false
	if _primary_harvest_latched:
		if primary_use_pressed:
			primary_use_just = false
			primary_use_pressed = false
		else:
			_primary_harvest_latched = false
	if primary_use_just and pumpkin_harvest != null and pumpkin_harvest.has_target():
		pumpkin_harvest.try_harvest_target()
		_primary_harvest_latched = primary_use_pressed
		primary_use_just = false
		primary_use_pressed = false
		_reset_mining()
		_reset_melee_chain()
	var selected_primary := get_selected_primary_action()
	var selected_mining := selected_primary as MiningActionDefinition
	var selected_melee := selected_primary as MeleeAttackActionDefinition
	var selected_tilling := selected_primary as TillingActionDefinition
	if primary_use_pressed and target_has and can_primary_target and selected_mining != null:
		if not is_mining:
			mine_target = target_block
			mine_target_rev = editable_voxel_world.get_revision(mine_target)
			mine_timer = 0.0
			mine_action = selected_mining
			is_mining = true
		else:
			if mine_target != target_block or mine_action != selected_mining:
				mine_target = target_block
				mine_target_rev = editable_voxel_world.get_revision(mine_target)
				mine_timer = 0.0
				mine_action = selected_mining
			else:
				var cur_rev = editable_voxel_world.get_revision(mine_target)
				if cur_rev != mine_target_rev:
					_reset_mining()
				else:
					mine_timer += delta
					if mine_timer >= get_mine_duration():
						_commit_mine(mine_target, mine_action)
	else:
		if is_mining:
			_reset_mining()
	if selected_melee == null:
		_reset_melee_chain()
	elif melee_attack_action != null and melee_attack_action != selected_melee:
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
		_commit_till(target_block, last_ray_normal, selected_tilling)

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

func _reset_melee_chain():
	_melee_contact_pending = false
	_melee_target_runtime_ids.clear()
	_melee_source_item_id = &""
	melee_attack_timer = 0.0
	melee_attack_elapsed = 0.0
	melee_attack_queue = 0
	melee_attack_action = null
	melee_chain_input_timer = 0.0
	next_melee_attack_direction = -1

func _start_melee_attack():
	var profile := melee_attack_action.attack_profile
	var selected_item_id = inventory_model.get_selected_item_id()
	assert(selected_item_id is StringName)
	_melee_source_item_id = selected_item_id
	melee_attack_timer = profile.cooldown
	melee_attack_elapsed = 0.0
	melee_chain_input_timer = 0.0
	var mouse_position := get_viewport().get_mouse_position()
	_melee_ray_origin = camera.project_ray_origin(mouse_position)
	_melee_ray_direction = camera.project_ray_normal(mouse_position).normalized()
	_melee_target_runtime_ids = combat.acquire_player_targets(_melee_ray_origin, _melee_ray_direction, profile)
	_melee_contact_pending = not _melee_target_runtime_ids.is_empty()
	var attack_direction := next_melee_attack_direction
	next_melee_attack_direction = -next_melee_attack_direction
	melee_attack_started.emit(melee_attack_action, attack_direction)
	if target_has and voxel_space != null and voxel_space.is_solid(target_block):
		melee_terrain_hit.emit(target_block)
	if _melee_contact_pending and is_zero_approx(profile.contact_time):
		_commit_melee_contacts()

func _advance_melee_attack(delta: float):
	if melee_attack_action == null or melee_attack_timer <= 0.0:
		return
	var profile := melee_attack_action.attack_profile
	var previous_elapsed := melee_attack_elapsed
	melee_attack_elapsed = minf(melee_attack_elapsed + delta, profile.duration)
	melee_attack_timer = maxf(melee_attack_timer - delta, 0.0)
	if _melee_contact_pending and previous_elapsed < profile.contact_time and melee_attack_elapsed >= profile.contact_time:
		_commit_melee_contacts()

func _commit_melee_contacts():
	var target_runtime_ids := _melee_target_runtime_ids
	_melee_contact_pending = false
	_melee_target_runtime_ids = []
	combat.try_commit_player_contacts(target_runtime_ids, _melee_ray_origin, _melee_ray_direction, melee_attack_action.attack_profile, _melee_source_item_id)

func _can_mine_position(pos: Vector3i, action: MiningActionDefinition) -> bool:
	if action == null or voxel_space == null or editable_voxel_world == null or motor == null:
		return false
	if editable_voxel_world.is_edit_protected(pos):
		return false
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if motor.global_position.distance_squared_to(center) > reach * reach:
		return false
	var block_id := voxel_space.get_block_id_at(pos)
	if block_id == BlockId.Type.AIR:
		return false
	return action.can_mine(voxel_space.block_catalog.get_definition(block_id))

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

func _commit_till(pos: Vector3i, face_normal: Vector3i, action: TillingActionDefinition) -> void:
	if not _can_till_position(pos, face_normal, action):
		return
	var old_id := voxel_space.get_block_id_at(pos)
	var edit := editable_voxel_world.try_replace_block(pos, old_id, action.result_block.id)
	if edit.is_success():
		soil_tilled.emit()
		_handle_raycast()

func get_mine_duration() -> float:
	assert(is_mining and mine_action != null)
	var block_id := voxel_space.get_block_id_at(mine_target)
	return mine_action.get_mine_duration(voxel_space.block_catalog.get_definition(block_id))

func has_mining_impact_target() -> bool:
	return is_mining and target_has and can_primary_target and mine_target == target_block

func get_mining_impact_position() -> Vector3:
	assert(has_mining_impact_target())
	return Vector3(mine_target) + Vector3(0.5, 0.5, 0.5) + Vector3(last_ray_normal) * 0.56

func get_mining_impact_normal() -> Vector3i:
	assert(has_mining_impact_target())
	return last_ray_normal

func get_mining_impact_block_id() -> int:
	assert(has_mining_impact_target())
	return voxel_space.get_block_id_at(mine_target)

func _can_place(action: BlockPlacementActionDefinition) -> bool:
	if not placement_has or not can_place_target:
		return false
	return _validate_placement(placement_block, action)

func _validate_placement(position: Vector3i, action: BlockPlacementActionDefinition) -> bool:
	if action == null or voxel_space == null or editable_voxel_world == null or inventory_model == null or motor == null:
		return false
	if editable_voxel_world.is_edit_protected(position):
		return false
	if get_selected_placement_action() != action or not inventory_model.can_consume_selected():
		return false
	if voxel_space.get_block_id_at(position) != BlockId.Type.AIR:
		return false
	var center := Vector3(position) + Vector3(0.5, 0.5, 0.5)
	if motor.global_position.distance_squared_to(center) > reach * reach:
		return false
	return not _placement_collides_player(position) and not _placement_collides_entity(position)

func _commit_mine(pos: Vector3i, action: MiningActionDefinition):
	if not _can_mine_position(pos, action):
		_reset_mining()
		return
	_reset_mining()
	if voxel_space == null or editable_voxel_world == null or inventory_model == null:
		return

	var preview_id = voxel_space.get_block_id_at(pos)
	if preview_id == BlockId.Type.AIR:
		return

	var item_ids_to_collect: Array[StringName] = []
	_append_block_drop(item_ids_to_collect, preview_id)
	for torch_pos in editable_voxel_world.get_attached_torches(pos):
		var tid = voxel_space.get_block_id_at(torch_pos)
		if tid != BlockId.Type.AIR:
			_append_block_drop(item_ids_to_collect, tid)

	if not inventory_model.can_add_batch(item_ids_to_collect):
		return

	var batch = editable_voxel_world.try_mine_block(pos)
	if batch is Array and batch.size() > 0 and batch[0] is BlockEdit:
		if not (batch[0] as BlockEdit).is_success():
			return
		var collected_item_ids: Array[StringName] = []
		for edit in batch:
			var be = edit as BlockEdit
			if be.is_success() and be.is_mine():
				_append_block_drop(collected_item_ids, be.old_id)
		inventory_model.add_batch(collected_item_ids)
	_handle_raycast()

func _append_block_drop(item_ids: Array[StringName], block_id: int):
	var drop_item_id := voxel_space.block_catalog.get_definition(block_id).drop_item_id
	if not drop_item_id.is_empty():
		item_ids.append(drop_item_id)

func _commit_place(pos: Vector3i, action: BlockPlacementActionDefinition):
	if not _validate_placement(pos, action):
		return

	var block_id := int(action.block.id)

	var attach_dir = -last_ray_normal if block_id == BlockId.Type.TORCH else Vector3i.ZERO
	var edit: BlockEdit = editable_voxel_world.try_place_block(pos, block_id, attach_dir)

	if edit.is_success():
		var consumed := inventory_model.consume_selected()
		assert(consumed)
		_handle_raycast()
		block_placed.emit()

func get_selected_block_id():
	var action := get_selected_placement_action()
	if action == null:
		return null
	return int(action.block.id)

func has_harvest_target() -> bool:
	return pumpkin_harvest != null and pumpkin_harvest.has_target()

func can_harvest_target() -> bool:
	return has_harvest_target() and pumpkin_harvest.can_harvest_target()

func get_harvest_target_bounds() -> AABB:
	assert(has_harvest_target())
	return pumpkin_harvest.get_target_bounds()

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

func _unhandled_input(event):
	if motor != null and motor.is_defeated():
		return
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + InventoryModel.HOTBAR_SIZE:
			var idx = event.keycode - KEY_1
			if inventory_model:
				inventory_model.select_slot(idx)
