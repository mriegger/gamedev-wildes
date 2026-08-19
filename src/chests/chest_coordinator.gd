extends InventoryTransferCoordinator
class_name ChestCoordinator

signal opened(position: Vector3i, definition: ContainerBlockDefinition)
signal closed

const CHEST_SCOPE: StringName = &"chest"
const CHEST_ITEM_ID: StringName = &"chest"

var voxel_world: VoxelWorld
var player_inventory: InventoryModel
var storage: ChestInventoryStore
var active_position: Vector3i
var active_inventory: InventoryModel

func setup(p_voxel_world: VoxelWorld, p_player_inventory: InventoryModel, p_storage: ChestInventoryStore):
	assert(p_voxel_world != null and p_player_inventory != null and p_storage != null)
	voxel_world = p_voxel_world
	player_inventory = p_player_inventory
	storage = p_storage

func try_open(position: Vector3i, definition: ContainerBlockDefinition) -> bool:
	if voxel_world == null or definition == null:
		return false
	var block_id := voxel_world.get_block_id_at(position)
	if block_id == BlockId.Type.AIR:
		return false
	var current_definition := voxel_world.block_catalog.get_definition(block_id).container
	if current_definition != definition:
		return false
	var inventory := storage.get_or_create(position, definition.get_slot_count())
	if inventory == null:
		return false
	active_position = position
	active_inventory = inventory
	opened.emit(position, definition)
	return true

func close():
	if active_inventory == null:
		return
	active_inventory = null
	closed.emit()

func is_open() -> bool:
	return active_inventory != null

func get_inventory_stack(scope: StringName, index: int) -> InventoryStack:
	var inventory := _get_inventory(scope)
	if inventory == null or not _is_valid_index(scope, index):
		return null
	return inventory.get_slot(index)

func get_socketed_rune_ids(scope: StringName, index: int) -> Array[StringName]:
	var stack := get_inventory_stack(scope, index)
	return [] if stack == null or stack.equipment_instance == null else stack.equipment_instance.socketed_rune_ids.duplicate()

func can_handle_drop(source_scope: StringName, source_index: int, destination_scope: StringName, destination_index: int, drag_count: int) -> bool:
	var source := _get_inventory(source_scope)
	var destination := _get_inventory(destination_scope)
	if source == null or destination == null:
		return false
	if not _is_valid_index(source_scope, source_index) or not _is_valid_index(destination_scope, destination_index):
		return false
	return source.can_transfer_stack_to(destination, source_index, destination_index, drag_count)

func handle_drop(source_scope: StringName, source_index: int, destination_scope: StringName, destination_index: int, drag_count: int) -> bool:
	if not can_handle_drop(source_scope, source_index, destination_scope, destination_index, drag_count):
		return false
	var source := _get_inventory(source_scope)
	var destination := _get_inventory(destination_scope)
	return source.transfer_stack_to(destination, source_index, destination_index, drag_count)

func quick_transfer(source_scope: StringName, source_index: int) -> bool:
	var destination_scope := _get_opposite_scope(source_scope)
	if destination_scope.is_empty() or not _is_quick_transfer_source(source_scope, source_index):
		return false
	var source := _get_inventory(source_scope)
	var destination := _get_inventory(destination_scope)
	if source == null or destination == null:
		return false
	return source.transfer_stack_to_indices(destination, source_index, _get_quick_transfer_destination_indices(destination_scope))

func can_quick_transfer(source_scope: StringName, source_index: int) -> bool:
	var destination_scope := _get_opposite_scope(source_scope)
	if destination_scope.is_empty() or not _is_quick_transfer_source(source_scope, source_index):
		return false
	var source := _get_inventory(source_scope)
	var destination := _get_inventory(destination_scope)
	if source == null or destination == null:
		return false
	return source.can_transfer_stack_to_indices(destination, source_index, _get_quick_transfer_destination_indices(destination_scope))

func move_all_to_backpack() -> bool:
	if active_inventory == null:
		return false
	var changed := false
	for index in range(active_inventory.size):
		if quick_transfer(CHEST_SCOPE, index):
			changed = true
	return changed

func can_move_all_to_backpack() -> bool:
	if active_inventory == null:
		return false
	for index in range(active_inventory.size):
		if can_quick_transfer(CHEST_SCOPE, index):
			return true
	return false

func can_pick_up_chest(position: Vector3i, action: MiningActionDefinition) -> bool:
	if action == null or action.get_tool_stat(&"pickaxe") == null:
		return false
	if voxel_world.get_block_id_at(position) != BlockId.Type.CHEST:
		return false
	var inventory := storage.get_inventory(position)
	if inventory != null and inventory.slots.any(func(stack): return stack != null):
		return false
	return player_inventory.can_exchange_inventory_items(
		{},
		_get_pickup_grants(position),
		player_inventory.equipment_instance_factory,
	)

func pick_up_chest(position: Vector3i, action: MiningActionDefinition) -> bool:
	if not can_pick_up_chest(position, action):
		return false
	var grants := _get_pickup_grants(position)
	var edits := voxel_world.try_pick_up_placed_block(position, BlockId.Type.CHEST)
	if edits.is_empty() or not edits[0].is_success():
		return false
	storage.remove(position)
	if active_inventory != null and active_position == position:
		active_inventory = null
		closed.emit()
	var added := player_inventory.exchange_inventory_items(
		{},
		grants,
		player_inventory.equipment_instance_factory,
	)
	assert(added)
	return true

func _get_pickup_grants(position: Vector3i) -> Dictionary[StringName, int]:
	var grants: Dictionary[StringName, int] = {CHEST_ITEM_ID: 1}
	for torch_position in voxel_world.get_attached_torches(position):
		var block_id := voxel_world.get_block_id_at(torch_position)
		var item_id := voxel_world.block_catalog.get_definition(block_id).drop_item_id
		if not item_id.is_empty():
			grants[item_id] = grants.get(item_id, 0) + 1
	return grants

func _get_inventory(scope: StringName) -> InventoryModel:
	if scope == PLAYER_SCOPE:
		return player_inventory
	if scope == CHEST_SCOPE:
		return active_inventory
	return null

func _is_valid_index(scope: StringName, index: int) -> bool:
	if scope == PLAYER_SCOPE:
		return index >= 0 and index < mini(player_inventory.size, InventoryModel.FILLABLE_SIZE)
	if scope == CHEST_SCOPE:
		return active_inventory != null and index >= 0 and index < active_inventory.size
	return false

func _is_quick_transfer_source(scope: StringName, index: int) -> bool:
	if not _is_valid_index(scope, index):
		return false
	if scope == PLAYER_SCOPE:
		return index >= InventoryModel.HOTBAR_SIZE
	return scope == CHEST_SCOPE

func _get_opposite_scope(scope: StringName) -> StringName:
	if scope == PLAYER_SCOPE:
		return CHEST_SCOPE
	if scope == CHEST_SCOPE:
		return PLAYER_SCOPE
	return &""

func _get_quick_transfer_destination_indices(scope: StringName) -> Array[int]:
	var indices: Array[int] = []
	if scope == PLAYER_SCOPE:
		for index in range(InventoryModel.HOTBAR_SIZE, mini(player_inventory.size, InventoryModel.FILLABLE_SIZE)):
			indices.append(index)
	elif scope == CHEST_SCOPE and active_inventory != null:
		for index in range(active_inventory.size):
			indices.append(index)
	return indices
