extends RefCounted
class_name WorldLootState

const MAXIMUM_ENTRY_COUNT: int = WorldLootSpatialIndex.MAXIMUM_ENTRY_COUNT
const MAXIMUM_ENTRY_ID: int = 2147483646
const MAXIMUM_NEXT_ENTRY_ID: int = MAXIMUM_ENTRY_ID + 1
const MATERIAL_LIFETIME: float = 300.0
const MERGE_RADIUS: float = 1.5
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

func get_revision() -> int:
	return _revision

func get_next_entry_id() -> int:
	return _next_entry_id

func has_entry(entry_id: int) -> bool:
	return _entries.has(entry_id)

func get_entry(entry_id: int) -> WorldLootEntry:
	var entry := _entries.get(entry_id) as WorldLootEntry
	return null if entry == null else entry.copy()

func get_entries() -> Array[WorldLootEntry]:
	var result: Array[WorldLootEntry] = []
	for entry_id in _entry_ids:
		result.append((_entries[entry_id] as WorldLootEntry).copy())
	return result

func query_nearby(position: Vector3, radius: float) -> Array[WorldLootEntry]:
	if not position.is_finite() or not is_finite(radius) or radius < 0.0:
		return []
	var result: Array[WorldLootEntry] = []
	for entry_id in _spatial_index.query_ids(position, radius):
		result.append((_entries[entry_id] as WorldLootEntry).copy())
	return result

func get_equipment_instance_ids() -> Array[int]:
	var result: Array[int] = []
	for entry_id in _entry_ids:
		var entry := _entries[entry_id] as WorldLootEntry
		if entry.stack.equipment_instance != null:
			result.append(entry.stack.equipment_instance.instance_id)
	return result

func _prepare_add_stack(stack: InventoryStack, world_position: Vector3) -> PreparedWorldLootChange:
	var stacks: Array[InventoryStack] = []
	stacks.append(stack)
	return _prepare_add_batch(
		stacks,
		world_position,
		equipment_instance_factory.get_next_instance_id(),
	)

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
	):
		return null
	var validation_factory := EquipmentInstanceFactory.new(
		item_catalog,
		validation_next_equipment_instance_id,
	)
	var used_equipment_instance_ids: Dictionary = {}
	for instance_id in get_equipment_instance_ids():
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
	var protected_entry_ids: Dictionary = {}
	var simulated_index := WorldLootSpatialIndex.new(SPATIAL_CELL_SIZE)
	simulated_index.rebuild(simulated_entries, simulated_ids)
	var changes_entry_set := false
	for raw_stack in stacks:
		var stack := raw_stack as InventoryStack
		var remaining := stack.count
		var candidates: Array[Dictionary] = []
		if stack.equipment_instance == null:
			for entry_id in simulated_index.query_ids(world_position, MERGE_RADIUS):
				var existing := simulated_entries[entry_id] as WorldLootEntry
				if existing.stack.item_id != stack.item_id or existing.stack.equipment_instance != null:
					continue
				var max_stack := item_catalog.get_definition(stack.item_id).max_stack
				if existing.stack.count >= max_stack:
					continue
				candidates.append({
					"entry_id": entry_id,
					"distance_squared": existing.world_position.distance_squared_to(world_position),
				})
			candidates.sort_custom(_merge_candidate_before)
		var merge_capacity := 0
		var max_stack := item_catalog.get_definition(stack.item_id).max_stack
		for candidate in candidates:
			var candidate_entry := simulated_entries[int(candidate["entry_id"])] as WorldLootEntry
			merge_capacity += max_stack - candidate_entry.stack.count
		var needs_new_entry := merge_capacity < remaining
		if needs_new_entry:
			if simulated_next_id > MAXIMUM_ENTRY_ID:
				return null
			if simulated_ids.size() == MAXIMUM_ENTRY_COUNT:
				var eviction_id := _find_eviction_id(
					simulated_entries,
					simulated_ids,
					protected_entry_ids,
				)
				if eviction_id < 1:
					return null
				simulated_entries.erase(eviction_id)
				simulated_ids.erase(eviction_id)
				for candidate_index in range(candidates.size() - 1, -1, -1):
					if int(candidates[candidate_index]["entry_id"]) == eviction_id:
						candidates.remove_at(candidate_index)
				changes_entry_set = true
				simulated_index.rebuild(simulated_entries, simulated_ids)
		if stack.equipment_instance == null:
			for candidate in candidates:
				var entry_id := int(candidate["entry_id"])
				var existing := simulated_entries[entry_id] as WorldLootEntry
				var moved := mini(remaining, max_stack - existing.stack.count)
				if moved < 1:
					continue
				existing.stack.count += moved
				existing.remaining_lifetime = MATERIAL_LIFETIME
				protected_entry_ids[entry_id] = true
				remaining -= moved
				if remaining == 0:
					break
		if remaining > 0:
			assert(needs_new_entry and simulated_ids.size() < MAXIMUM_ENTRY_COUNT)
			var added_stack := InventoryStack.new(stack.item_id, remaining, stack.equipment_instance)
			var lifetime := WorldLootEntry.NO_LIFETIME if added_stack.equipment_instance != null else MATERIAL_LIFETIME
			simulated_entries[simulated_next_id] = WorldLootEntry.new(
				simulated_next_id,
				added_stack,
				world_position,
				lifetime,
			)
			simulated_ids.append(simulated_next_id)
			protected_entry_ids[simulated_next_id] = true
			simulated_next_id += 1
			changes_entry_set = true
			simulated_index.rebuild(simulated_entries, simulated_ids)
	simulated_ids.sort()
	return PreparedWorldLootChange.new(
		self,
		_revision,
		simulated_entries,
		simulated_ids,
		simulated_next_id,
		null,
		changes_entry_set,
		validation_next_equipment_instance_id,
	)

func prepare_take(entry_id: int, count: int = -1) -> PreparedWorldLootChange:
	var entry := _entries.get(entry_id) as WorldLootEntry
	if entry == null:
		return null
	var removed_count := entry.stack.count if count == -1 else count
	if removed_count < 1 or removed_count > entry.stack.count:
		return null
	if entry.stack.equipment_instance != null and removed_count != entry.stack.count:
		return null
	var simulated_entries := _copy_entries()
	var simulated_ids: Array[int] = _entry_ids.duplicate()
	var simulated_entry := simulated_entries[entry_id] as WorldLootEntry
	var removes_entry := removed_count == simulated_entry.stack.count
	var removed := InventoryStack.new(
		simulated_entry.stack.item_id,
		removed_count,
		simulated_entry.stack.equipment_instance,
	)
	simulated_entry.stack.count -= removed_count
	if simulated_entry.stack.count == 0:
		simulated_entries.erase(entry_id)
		simulated_ids.erase(entry_id)
	return PreparedWorldLootChange.new(
		self,
		_revision,
		simulated_entries,
		simulated_ids,
		_next_entry_id,
		removed,
		removes_entry,
	)

func prepare_advance_time(delta: float) -> PreparedWorldLootChange:
	if not is_finite(delta) or delta <= 0.0:
		return null
	var simulated_entries := _copy_entries()
	var simulated_ids: Array[int] = _entry_ids.duplicate()
	var changed := false
	var expired := false
	for entry_id in _entry_ids:
		var entry := simulated_entries[entry_id] as WorldLootEntry
		if not entry.has_lifetime():
			continue
		changed = true
		entry.remaining_lifetime -= delta
		if entry.remaining_lifetime <= 0.0:
			simulated_entries.erase(entry_id)
			simulated_ids.erase(entry_id)
			expired = true
	if not changed:
		return null
	return PreparedWorldLootChange.new(
		self,
		_revision,
		simulated_entries,
		simulated_ids,
		_next_entry_id,
		null,
		expired,
	)

func can_commit_prepared_change(prepared: PreparedWorldLootChange) -> bool:
	return (
		_is_current_prepared_change(prepared)
		and equipment_instance_factory.get_next_instance_id()
			>= prepared._get_minimum_next_equipment_instance_id()
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

func commit_prepared_change(prepared: PreparedWorldLootChange) -> bool:
	if not can_commit_prepared_change(prepared):
		return false
	_commit_prepared_change(prepared)
	return true

func _commit_prepared_change(prepared: PreparedWorldLootChange) -> void:
	assert(can_commit_prepared_change(prepared))
	var consumed := prepared._consume(self)
	assert(consumed)
	_entries = prepared._copy_committed_entries()
	_entry_ids = prepared._copy_committed_entry_ids()
	_next_entry_id = prepared._get_next_entry_id()
	_revision += 1
	if prepared._changes_entries():
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

func _find_eviction_id(
	entries: Dictionary,
	entry_ids: Array[int],
	excluded_entry_ids: Dictionary,
) -> int:
	var material_candidate_id := -1
	var material_candidate_lifetime := 0.0
	var equipment_candidate_id := -1
	for entry_id in entry_ids:
		var entry := entries[entry_id] as WorldLootEntry
		if excluded_entry_ids.has(entry_id):
			continue
		if not entry.has_lifetime():
			if equipment_candidate_id == -1 or entry_id < equipment_candidate_id:
				equipment_candidate_id = entry_id
			continue
		if (
			material_candidate_id == -1
			or entry.remaining_lifetime < material_candidate_lifetime
			or (
				entry.remaining_lifetime == material_candidate_lifetime
				and entry_id < material_candidate_id
			)
		):
			material_candidate_id = entry_id
			material_candidate_lifetime = entry.remaining_lifetime
	return material_candidate_id if material_candidate_id != -1 else equipment_candidate_id

static func _merge_candidate_before(first: Dictionary, second: Dictionary) -> bool:
	var first_distance := float(first["distance_squared"])
	var second_distance := float(second["distance_squared"])
	if first_distance == second_distance:
		return int(first["entry_id"]) < int(second["entry_id"])
	return first_distance < second_distance
