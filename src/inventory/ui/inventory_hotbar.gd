extends HotbarView
class_name InventoryHotbar

var _inventory_model: InventoryModel = null
var _inventory_loadout_coordinator: InventoryLoadoutCoordinator = null
var _backpack_open: bool = false
var _gameplay_selection_enabled: bool = true

func _ready() -> void:
	super._ready()
	slot_selection_requested.connect(_on_inventory_slot_selection_requested)

func setup(inventory: InventoryModel, inventory_loadout_coordinator: InventoryLoadoutCoordinator, item_proficiency: ItemProficiency) -> void:
	_inventory_model = inventory
	_inventory_loadout_coordinator = inventory_loadout_coordinator
	_inventory_model.inventory_changed.connect(refresh)
	for slot_view in slot_nodes:
		var slot := slot_view as InventoryHotbarSlot
		slot.set_inventory(_inventory_model)
		slot.set_inventory_loadout_coordinator(inventory_loadout_coordinator)
		slot.set_item_proficiency(item_proficiency)
	refresh()

func setup_consumption(consumption: ItemConsumptionCoordinator) -> void:
	assert(consumption != null)
	for slot_view in slot_nodes:
		(slot_view as InventoryHotbarSlot).set_item_consumption(consumption)

func refresh() -> void:
	if _inventory_model == null or slot_nodes.is_empty():
		return
	for index in range(slot_nodes.size()):
		var stack := _inventory_model.get_slot(index)
		var slot := slot_nodes[index] as InventoryHotbarSlot
		if stack == null:
			slot.set_item(null, 0)
		else:
			slot.set_item(stack.item_id, stack.count)
	set_selected_slot(_inventory_model.get_selected_slot())

func set_backpack_open(open: bool) -> void:
	if _backpack_open == open:
		return
	_backpack_open = open
	_sync_selection_input_enabled()
	for slot_view in slot_nodes:
		(slot_view as InventoryHotbarSlot).set_backpack_open(open)

func set_gameplay_selection_enabled(enabled: bool) -> void:
	_gameplay_selection_enabled = enabled
	_sync_selection_input_enabled()

func set_inventory_transfer_context(coordinator: InventoryTransferCoordinator) -> void:
	for slot_view in slot_nodes:
		var slot := slot_view as InventoryHotbarSlot
		slot.set_inventory_transfer_context(coordinator, InventoryTransferCoordinator.PLAYER_SCOPE if coordinator != null else &"")

func _on_inventory_slot_selection_requested(slot_index: int) -> void:
	if _inventory_loadout_coordinator != null:
		_inventory_loadout_coordinator.select_slot(slot_index)

func _sync_selection_input_enabled() -> void:
	set_selection_input_enabled(_gameplay_selection_enabled and not _backpack_open)
