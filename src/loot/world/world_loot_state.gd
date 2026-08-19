extends RefCounted
class_name WorldLootState

const MAXIMUM_ENTRY_COUNT: int = WorldLootSpatialIndex.MAXIMUM_ENTRY_COUNT
const MAXIMUM_ENTRY_ID: int = 2147483646
const MAXIMUM_NEXT_ENTRY_ID: int = MAXIMUM_ENTRY_ID + 1
const SPATIAL_CELL_SIZE: float = 4.0

var item_catalog: ItemCatalog
var equipment_instance_factory: EquipmentInstanceFactory
var _entries: Dictionary = {}
var _entry_ids: Array[int] = []
var _next_entry_id: int = 1
var _revision: int = 0
var _spatial_index: WorldLootSpatialIndex = WorldLootSpatialIndex.new(SPATIAL_CELL_SIZE)

func _init(
	p_item_catalog: ItemCatalog,
	p_equipment_instance_factory: EquipmentInstanceFactory,
) -> void:
	assert(p_item_catalog != null)
	assert(p_equipment_instance_factory != null)
	assert(p_equipment_instance_factory.item_catalog == p_item_catalog)
	item_catalog = p_item_catalog
	equipment_instance_factory = p_equipment_instance_factory

func get_entry_count() -> int:
	return _entry_ids.size()

func get_entries() -> Array[WorldLootEntry]:
	var result: Array[WorldLootEntry] = []
	for entry_id in _entry_ids:
		result.append((_entries[entry_id] as WorldLootEntry).copy())
	return result

func _get_equipment_instance_ids() -> Array[int]:
	var result: Array[int] = []
	for entry_id in _entry_ids:
		var entry := _entries[entry_id] as WorldLootEntry
		if entry.stack.equipment_instance != null:
			result.append(entry.stack.equipment_instance.instance_id)
	return result

func _prepare_add_batch(
	stacks: Array,
	world_position: Vector3,
	validation_next_equipment_instance_id: int,
) -> PreparedWorldLootChange:
	if (
		stacks.is_empty()
		or not _spatial_index.can_index_position(world_position)
		or validation_next_equipment_instance_id < equipment_instance_factory.get_next_instance_id()
		or validation_next_equipment_instance_id > EquipmentInstanceFactory.MAXIMUM_NEXT_INSTANCE_ID
		or stacks.size() > MAXIMUM_ENTRY_COUNT - _entry_ids.size()
		or _next_entry_id > MAXIMUM_NEXT_ENTRY_ID - stacks.size()
	):
		return null
	var validation_factory := EquipmentInstanceFactory.new(
		item_catalog,
		validation_next_equipment_instance_id,
	)
	var used_equipment_instance_ids: Dictionary = {}
	for instance_id in _get_equipment_instance_ids():
		used_equipment_instance_ids[instance_id] = true
	for raw_stack in stacks:
		if not raw_stack is InventoryStack:
			return null
		var stack := raw_stack as InventoryStack
		if not _is_valid_stack_with_factory(stack, validation_factory):
			return null
		if stack.equipment_instance == null:
			continue
		var instance_id := stack.equipment_instance.instance_id
		if used_equipment_instance_ids.has(instance_id):
			return null
		used_equipment_instance_ids[instance_id] = true
	var simulated_entries := _copy_entries()
	var simulated_ids: Array[int] = _entry_ids.duplicate()
	var simulated_next_id := _next_entry_id
	for raw_stack in stacks:
		var stack := raw_stack as InventoryStack
		simulated_entries[simulated_next_id] = WorldLootEntry.new(
			simulated_next_id,
			stack,
			world_position,
		)
		simulated_ids.append(simulated_next_id)
		simulated_next_id += 1
	return PreparedWorldLootChange.new(
		self,
		_revision,
		simulated_entries,
		simulated_ids,
		simulated_next_id,
		validation_next_equipment_instance_id,
	)

func _can_commit_after_equipment_advance(
	prepared: PreparedWorldLootChange,
	pending_next_equipment_instance_id: int,
) -> bool:
	return (
		_is_current_prepared_change(prepared)
		and prepared._get_minimum_next_equipment_instance_id()
			== pending_next_equipment_instance_id
	)

func _commit_prepared_change(prepared: PreparedWorldLootChange) -> void:
	assert(
		_is_current_prepared_change(prepared)
		and equipment_instance_factory.get_next_instance_id()
			>= prepared._get_minimum_next_equipment_instance_id()
	)
	var consumed := prepared._consume(self)
	assert(consumed)
	_entries = prepared._copy_committed_entries()
	_entry_ids = prepared._copy_committed_entry_ids()
	_next_entry_id = prepared._get_next_entry_id()
	_revision += 1
	_spatial_index.rebuild(_entries, _entry_ids)
	assert(_spatial_index.get_entry_count() == _entry_ids.size())

func _is_current_prepared_change(prepared: PreparedWorldLootChange) -> bool:
	return (
		prepared != null
		and prepared._is_for(self)
		and prepared._is_available()
		and prepared.get_expected_revision() == _revision
	)

func _is_valid_stack_with_factory(
	stack: InventoryStack,
	validation_factory: EquipmentInstanceFactory,
) -> bool:
	if stack == null or not item_catalog.has_definition(stack.item_id):
		return false
	var definition := item_catalog.get_definition(stack.item_id)
	if stack.count < 1 or stack.count > definition.max_stack:
		return false
	if definition.equipment_type == null:
		return stack.equipment_instance == null
	return (
		stack.count == 1
		and validation_factory.is_valid_instance(stack.item_id, stack.equipment_instance)
	)

func _copy_entries() -> Dictionary:
	var copied: Dictionary = {}
	for entry_id in _entry_ids:
		copied[entry_id] = (_entries[entry_id] as WorldLootEntry).copy()
	return copied
