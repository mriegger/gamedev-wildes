extends VBoxContainer
class_name RuneSocketingPanel

const VISIBLE_SLOT_COUNT: int = ProficiencyDefinition.MAXIMUM_SLOT_COUNT

@onready var _gear_slot: RuneSocketingSlot = $GearSection/GearSlot as RuneSocketingSlot
@onready var _rune_slots: Array[RuneSocketingSlot] = [
	$RuneSection/RuneSlots/RuneSlot1 as RuneSocketingSlot,
	$RuneSection/RuneSlots/RuneSlot2 as RuneSocketingSlot,
	$RuneSection/RuneSlots/RuneSlot3 as RuneSocketingSlot,
]
@onready var _status_label: Label = $Status as Label

var _inventory: InventoryModel
var _socketing_coordinator: RuneSocketingCoordinator
var _item_proficiency: ItemProficiency
var _selected_gear_index: int = -1
var _selected_gear_item_id: StringName = &""

func _ready() -> void:
	assert(_rune_slots.size() == VISIBLE_SLOT_COUNT)
	_gear_slot.set_drop_validator(Callable(self, "_can_select_gear"))
	_gear_slot.inventory_stack_dropped.connect(_select_gear)
	for slot_index in range(_rune_slots.size()):
		var slot := _rune_slots[slot_index]
		slot.set_drop_validator(Callable(self, "_can_socket_rune").bind(slot_index))
		slot.inventory_stack_dropped.connect(_socket_rune.bind(slot_index))
		slot.unsocket_requested.connect(_unsocket_rune.bind(slot_index))
	_refresh()

func setup(
	inventory: InventoryModel,
	socketing_coordinator: RuneSocketingCoordinator,
	item_proficiency: ItemProficiency,
) -> void:
	assert(inventory != null)
	assert(socketing_coordinator != null)
	assert(item_proficiency != null)
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
	if _item_proficiency != null and _item_proficiency.progress_changed.is_connected(_on_proficiency_changed):
		_item_proficiency.progress_changed.disconnect(_on_proficiency_changed)
	_inventory = inventory
	_socketing_coordinator = socketing_coordinator
	_item_proficiency = item_proficiency
	_inventory.inventory_changed.connect(_on_inventory_changed)
	_item_proficiency.progress_changed.connect(_on_proficiency_changed)
	clear_gear_reference()

func clear_gear_reference() -> void:
	_selected_gear_index = -1
	_selected_gear_item_id = &""
	_refresh()

func get_selected_gear_index() -> int:
	return _selected_gear_index

func get_gear_slot() -> RuneSocketingSlot:
	return _gear_slot

func get_rune_slots() -> Array[RuneSocketingSlot]:
	var slots: Array[RuneSocketingSlot] = []
	slots.assign(_rune_slots)
	return slots

func _can_select_gear(source_index: int) -> bool:
	return _socketing_coordinator != null and _socketing_coordinator.is_socketable_gear_index(source_index)

func _select_gear(source_index: int) -> void:
	if not _can_select_gear(source_index):
		return
	var stack := _inventory.get_slot(source_index)
	_selected_gear_index = source_index
	_selected_gear_item_id = stack.item_id
	_refresh()

func _can_socket_rune(source_index: int, slot_index: int) -> bool:
	return (
		_selected_gear_index >= 0
		and _socketing_coordinator != null
		and _socketing_coordinator.can_socket(_selected_gear_index, slot_index, source_index)
	)

func _socket_rune(source_index: int, slot_index: int) -> void:
	if _selected_gear_index < 0 or _socketing_coordinator == null:
		return
	_socketing_coordinator.try_socket(_selected_gear_index, slot_index, source_index)
	_refresh()

func _unsocket_rune(slot_index: int) -> void:
	if _selected_gear_index < 0 or _socketing_coordinator == null:
		return
	_socketing_coordinator.try_unsocket(_selected_gear_index, slot_index)
	_refresh()

func _on_inventory_changed() -> void:
	if _selected_gear_index >= 0:
		var stack := _inventory.get_slot(_selected_gear_index)
		if (
			stack == null
			or stack.item_id != _selected_gear_item_id
			or not _socketing_coordinator.is_socketable_gear_index(_selected_gear_index)
		):
			_selected_gear_index = -1
			_selected_gear_item_id = &""
	_refresh()

func _on_proficiency_changed(item_id: StringName) -> void:
	if item_id == _selected_gear_item_id:
		_refresh()

func _refresh() -> void:
	if not is_node_ready():
		return
	_refresh_gear_slot()
	_refresh_rune_slots()

func _refresh_gear_slot() -> void:
	if _selected_gear_index < 0 or _inventory == null:
		_gear_slot.present(
			RuneSocketingSlot.State.GEAR_EMPTY,
			null,
			"GEAR",
			"Drop weapon or armor"
		)
		_status_label.text = "Choose a gear item from your inventory."
		return
	var stack := _inventory.get_slot(_selected_gear_index)
	var definition := _inventory.item_catalog.get_definition(stack.item_id)
	var rarity_text := definition.rarity.display_name if definition.rarity != null else ""
	var rarity_color := definition.rarity.display_color if definition.rarity != null else Color.WHITE
	_gear_slot.present(
		RuneSocketingSlot.State.GEAR_SELECTED,
		definition.icon,
		definition.display_name,
		rarity_text,
		rarity_color
	)
	_gear_slot.set_item_tooltip(
		definition,
		_item_proficiency,
		_inventory.item_catalog,
		_inventory.get_socketed_rune_ids(_selected_gear_index),
	)
	_status_label.text = "Drop a rune into an unlocked slot. Click a filled slot to remove it."

func _refresh_rune_slots() -> void:
	var total_slots := 0
	var unlocked_slots := 0
	if _selected_gear_index >= 0 and _socketing_coordinator != null:
		total_slots = _socketing_coordinator.get_total_slot_count(_selected_gear_index)
		unlocked_slots = _socketing_coordinator.get_unlocked_slot_count(_selected_gear_index)
	for slot_index in range(_rune_slots.size()):
		var slot := _rune_slots[slot_index]
		if slot_index >= total_slots:
			slot.present(RuneSocketingSlot.State.UNAVAILABLE, null, "SLOT %d" % (slot_index + 1), "Unavailable")
			continue
		if slot_index >= unlocked_slots:
			slot.present(RuneSocketingSlot.State.LOCKED, null, "SLOT %d" % (slot_index + 1), "Locked")
			continue
		var rune_id := _socketing_coordinator.get_socketed_rune_id(_selected_gear_index, slot_index)
		if rune_id.is_empty():
			slot.present(RuneSocketingSlot.State.EMPTY, null, "SLOT %d" % (slot_index + 1), "Drop rune")
			continue
		var definition := _inventory.item_catalog.get_definition(rune_id) as RuneDefinition
		var rarity_text := definition.rarity.display_name if definition.rarity != null else "Socketed"
		var rarity_color := definition.rarity.display_color if definition.rarity != null else Color.WHITE
		slot.present(RuneSocketingSlot.State.FILLED, definition.icon, definition.display_name, rarity_text, rarity_color)
		slot.set_item_tooltip(definition, _item_proficiency, _inventory.item_catalog)
