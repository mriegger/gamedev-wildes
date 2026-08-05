extends Node3D
class_name PlayerInteractor

@export var reach: float = 6.0
@export var mine_hold_time: float = 0.35
@export var place_cooldown: float = 0.18

var voxel_world: VoxelWorld = null
var camera: Camera3D = null
var motor: PlayerMotor = null
var inventory_model: InventoryModel = null
var _input_buffer: InputBuffer = null

var target_block: Vector3i = Vector3i(-999, -999, -999)
var target_has: bool = false
var placement_block: Vector3i = Vector3i(-999, -999, -999)
var placement_has: bool = false
var last_ray_normal: Vector3i = Vector3i.UP
var can_mine_target: bool = false
var can_place_target: bool = false
var pointer_over_ui: bool = false

var is_mining: bool = false
var mine_timer: float = 0.0
var mine_target: Vector3i = Vector3i(-999, -999, -999)
var mine_target_rev: int = -1
var place_timer: float = 0.0
var _ray_hit_pos: Vector3i
var _ray_place_pos: Vector3i
var _ray_face_normal: Vector3i

func setup(p_voxel_world: VoxelWorld, p_camera: Camera3D, p_motor: PlayerMotor, p_inventory: InventoryModel, p_input_buffer: InputBuffer):
	voxel_world = p_voxel_world
	camera = p_camera
	motor = p_motor
	inventory_model = p_inventory
	_input_buffer = p_input_buffer

func _physics_process(delta):
	if voxel_world == null or motor == null or camera == null or inventory_model == null or _input_buffer == null:
		return
	pointer_over_ui = UiUtils.is_pointer_over_ui(get_viewport())
	if pointer_over_ui:
		target_has = false
		placement_has = false
		can_mine_target = false
		can_place_target = false
		if is_mining:
			_reset_mining()
		_input_buffer.place_just = false
		return
	_handle_raycast()
	_handle_mining_placing(delta)

func _handle_raycast():
	target_has = false
	placement_has = false
	can_mine_target = false
	can_place_target = false

	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)

	var max_dist = ray_origin.distance_to(motor.global_position) + reach + 1.0
	if not _voxel_raycast(ray_origin, ray_dir, max_dist):
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
	can_mine_target = motor_pos.distance_squared_to(Vector3(best_hit.x + 0.5, best_hit.y + 0.5, best_hit.z + 0.5)) <= reach_squared

	if voxel_world.get_block_at(best_place) == null:
		if not _placement_collides_player(best_place):
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

	if voxel_world.is_raycast_solid(current):
		origin = origin + dir * 0.6
		current = Vector3i(floor(origin.x), floor(origin.y), floor(origin.z))

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
		if voxel_world.is_raycast_solid(current):
			var face_normal: Vector3i
			if last_pos.x != current.x:
				face_normal = Vector3i(-step_x, 0, 0)
			elif last_pos.y != current.y:
				face_normal = Vector3i(0, -step_y, 0)
			else:
				face_normal = Vector3i(0, 0, -step_z)
			var place_pos = last_pos
			if voxel_world.is_raycast_solid(place_pos):
				place_pos = current + face_normal
			_ray_hit_pos = current
			_ray_place_pos = place_pos
			_ray_face_normal = face_normal
			return true

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

func _handle_mining_placing(delta):
	place_timer -= delta
	var ib = _input_buffer
	var left_pressed = ib.mine_pressed
	if left_pressed and target_has and can_mine_target:
		if not is_mining:
			mine_target = target_block
			mine_target_rev = voxel_world.get_revision(mine_target)
			mine_timer = 0.0
			is_mining = true
		else:
			if mine_target != target_block:
				mine_target = target_block
				mine_target_rev = voxel_world.get_revision(mine_target)
				mine_timer = 0.0
			else:
				var cur_rev = voxel_world.get_revision(mine_target)
				if cur_rev != mine_target_rev:
					_reset_mining()
				else:
					mine_timer += delta
					if mine_timer >= mine_hold_time:
						_commit_mine(mine_target)
	else:
		if is_mining:
			_reset_mining()

	if (ib.place_just or ib.place_pressed) and place_timer <= 0.0:
		ib.place_just = false
		if _can_place():
			_commit_place(placement_block)
			place_timer = place_cooldown

func _reset_mining():
	is_mining = false
	mine_timer = 0.0
	mine_target = Vector3i(-999, -999, -999)
	mine_target_rev = -1

func _can_place() -> bool:
	if not placement_has or not can_place_target:
		return false
	if inventory_model == null:
		return false
	return inventory_model.can_consume_selected()

func _commit_mine(pos: Vector3i):
	_reset_mining()
	if voxel_world == null or inventory_model == null:
		return

	var preview_id = voxel_world.get_block_id_at(pos)
	if preview_id == BlockId.Type.AIR:
		return

	var ids_to_collect: Array[int] = [preview_id]
	for torch_pos in voxel_world.get_attached_torches(pos):
		var tid = voxel_world.get_block_id_at(torch_pos)
		if tid != BlockId.Type.AIR:
			ids_to_collect.append(tid)

	if not inventory_model.can_add_batch(ids_to_collect):
		return

	var batch = voxel_world.try_mine_block(pos)
	if batch is Array and batch.size() > 0 and batch[0] is BlockEdit:
		if not (batch[0] as BlockEdit).is_success():
			return
		var collected_ids: Array[int] = []
		for edit in batch:
			var be = edit as BlockEdit
			if be.is_success() and be.is_mine():
				collected_ids.append(be.old_id)
		inventory_model.add_batch(collected_ids)
	_handle_raycast()

func _commit_place(pos: Vector3i):
	if voxel_world == null or inventory_model == null:
		return

	var sel_data = inventory_model.get_selected_data()
	if sel_data == null:
		return
	var type_to_place = sel_data["type"]

	var attach_dir = -last_ray_normal if type_to_place == BlockId.Type.TORCH else Vector3i.ZERO
	var edit: BlockEdit = voxel_world.try_place_block(pos, type_to_place, attach_dir)

	if edit.is_success():
		inventory_model.consume_selected()
		_handle_raycast()

func get_selected_block_type():
	if inventory_model == null:
		return null
	return inventory_model.get_selected_block_type()

func _unhandled_input(event):
	if event is InputEventKey and event.pressed:
		if event.keycode >= KEY_1 and event.keycode < KEY_1 + InventoryModel.HOTBAR_SIZE:
			var idx = event.keycode - KEY_1
			if inventory_model:
				inventory_model.select_slot(idx)
