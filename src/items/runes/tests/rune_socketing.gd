extends SceneTree

const WEAPON_ID: StringName = &"socket_test_weapon"
const RUNE_ID: StringName = &"basic_rune"
const ARMOR_ONLY_RUNE_ID: StringName = &"armor_only_rune"
const RUNE_SOURCE_INDEX: int = InventoryModel.HOTBAR_SIZE
const NON_RUNE_SOURCE_INDEX: int = InventoryModel.HOTBAR_SIZE + 1
const INCOMPATIBLE_RUNE_SOURCE_INDEX: int = InventoryModel.HOTBAR_SIZE + 2

var _errors: Array[String] = []

func _init() -> void:
	var catalog := _build_catalog()
	var inventory := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	inventory.slots[0] = _equipment_stack(inventory, WEAPON_ID)
	inventory.slots[1] = _equipment_stack(inventory, WEAPON_ID)
	inventory.slots[RUNE_SOURCE_INDEX] = InventoryStack.new(RUNE_ID, 3)
	inventory.slots[NON_RUNE_SOURCE_INDEX] = InventoryStack.new(&"sand_block", 32)
	inventory.slots[INCOMPATIBLE_RUNE_SOURCE_INDEX] = InventoryStack.new(ARMOR_ONLY_RUNE_ID, 1)
	var proficiency := ItemProficiency.new(catalog)
	var coordinator := RuneSocketingCoordinator.new()
	_expect(coordinator.setup(inventory, proficiency), "valid empty socket state was rejected")
	_expect(coordinator.is_socketable_gear_index(0), "weapon was not socketable")
	_expect(coordinator.is_socketable_gear_index(1), "second weapon copy was not socketable")
	_expect(not coordinator.is_socketable_gear_index(RUNE_SOURCE_INDEX), "rune was treated as gear")
	_expect(not coordinator.is_socketable_gear_index(-1), "negative inventory index was socketable")
	_expect(coordinator.get_total_slot_count(0) == 3, "slot count did not follow proficiency definition")
	_expect(coordinator.get_unlocked_slot_count(0) == 1, "initial free slot count changed")
	_expect(coordinator.get_slot_state(0, 0) == RuneSocketingCoordinator.SlotState.EMPTY, "free slot was not empty")
	_expect(coordinator.get_slot_state(0, 1) == RuneSocketingCoordinator.SlotState.LOCKED, "second slot was not locked")
	_expect(coordinator.get_slot_state(0, 2) == RuneSocketingCoordinator.SlotState.LOCKED, "third slot was not locked")
	_expect(coordinator.get_slot_state(0, 3) == RuneSocketingCoordinator.SlotState.UNAVAILABLE, "fourth slot was available")
	_expect(coordinator.get_slot_state(0, -1) == RuneSocketingCoordinator.SlotState.UNAVAILABLE, "negative slot was available")

	var locked_before := inventory.to_dict()
	_expect(not coordinator.can_socket(0, 2, RUNE_SOURCE_INDEX), "locked slot accepted a rune")
	_expect(not coordinator.try_socket(0, 2, RUNE_SOURCE_INDEX), "socket command committed to a locked slot")
	_expect(inventory.to_dict() == locked_before, "locked socket attempt changed inventory")
	_expect(proficiency.add_experience(WEAPON_ID, 20.0) == 2, "weapon did not reach the third socket unlock")
	_expect(coordinator.get_unlocked_slot_count(0) == 3, "proficiency did not unlock all sockets")
	_expect(coordinator.get_slot_state(0, 2) == RuneSocketingCoordinator.SlotState.EMPTY, "unlocked third slot was not empty")

	_expect(not coordinator.can_socket(0, 0, NON_RUNE_SOURCE_INDEX), "non-rune item was socketable")
	_expect(not coordinator.can_socket(0, 0, INCOMPATIBLE_RUNE_SOURCE_INDEX), "incompatible rune was socketable")
	_expect(coordinator.can_socket(0, 2, RUNE_SOURCE_INDEX), "compatible rune could not target third slot")
	_expect(coordinator.try_socket(0, 2, RUNE_SOURCE_INDEX), "compatible rune did not socket")
	_expect(inventory.get_socketed_rune_ids(0) == _rune_ids([&"", &"", RUNE_ID]), "third slot position was not preserved")
	_expect(inventory.get_socketed_rune_ids(1).is_empty(), "socketing one copy changed another copy")
	_expect(inventory.get_slot(RUNE_SOURCE_INDEX).count == 2, "socketing did not consume exactly one rune")
	_expect(coordinator.get_slot_state(0, 2) == RuneSocketingCoordinator.SlotState.FILLED, "socketed slot was not filled")
	_expect(coordinator.get_socketed_rune_id(0, 2) == RUNE_ID, "socket query returned the wrong rune")
	_expect(not coordinator.can_socket(0, 2, RUNE_SOURCE_INDEX), "filled slot accepted another rune")

	_expect(coordinator.can_socket(0, 0, RUNE_SOURCE_INDEX), "duplicate rune could not target another slot")
	_expect(coordinator.try_socket(0, 0, RUNE_SOURCE_INDEX), "duplicate rune did not socket")
	_expect(inventory.get_socketed_rune_ids(0) == _rune_ids([RUNE_ID, &"", RUNE_ID]), "duplicate rune loadout changed fixed positions")
	_expect(coordinator.can_unsocket(0, 2), "filled third slot could not be unsocketed")
	_expect(coordinator.try_unsocket(0, 2), "third slot rune did not unsocket")
	_expect(inventory.get_socketed_rune_ids(0) == _rune_ids([RUNE_ID]), "unsocket did not trim trailing empty positions")
	_expect(inventory.get_inventory_item_count(RUNE_ID) == 2, "unsocket did not return exactly one rune")
	_expect(not coordinator.can_unsocket(0, 1), "empty slot was unsocketable")
	_expect(coordinator.try_unsocket(0, 0), "first slot rune did not unsocket")
	_expect(inventory.get_socketed_rune_ids(0).is_empty(), "last unsocket did not clear loadout")
	_expect(inventory.get_inventory_item_count(RUNE_ID) == 3, "socket round trip changed rune count")

	_test_setup_validation(catalog)
	_test_full_inventory_rejection(catalog)

	if _errors.is_empty():
		print("RUNE_SOCKETING PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_setup_validation(catalog: ItemCatalog) -> void:
	var valid := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	valid.slots[0] = _equipment_stack(valid, WEAPON_ID, _rune_ids([RUNE_ID]))
	_expect(RuneSocketingCoordinator.new().setup(valid, ItemProficiency.new(catalog)), "valid restored loadout was rejected")

	var trailing_empty := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	trailing_empty.slots[0] = _unchecked_equipment_stack(WEAPON_ID, _rune_ids([RUNE_ID, &""]))
	_expect(not RuneSocketingCoordinator.new().setup(trailing_empty, ItemProficiency.new(catalog)), "trailing empty socket sentinel was accepted")

	var unknown_rune := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	unknown_rune.slots[0] = _unchecked_equipment_stack(WEAPON_ID, _rune_ids([&"missing_rune"]))
	_expect(not RuneSocketingCoordinator.new().setup(unknown_rune, ItemProficiency.new(catalog)), "unknown restored rune was accepted")

	var incompatible_rune := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	incompatible_rune.slots[0] = _unchecked_equipment_stack(WEAPON_ID, _rune_ids([ARMOR_ONLY_RUNE_ID]))
	var incompatible_coordinator := RuneSocketingCoordinator.new()
	_expect(incompatible_coordinator.setup(incompatible_rune, ItemProficiency.new(catalog)), "grandfathered incompatible rune was rejected")
	_expect(incompatible_coordinator.can_unsocket(0, 0), "grandfathered incompatible rune could not be unsocketed")
	_expect(incompatible_coordinator.try_unsocket(0, 0), "grandfathered incompatible rune did not unsocket")
	_expect(incompatible_rune.get_socketed_rune_ids(0).is_empty(), "grandfathered incompatible rune remained socketed")

	var reduced_slots := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	reduced_slots.slots[0] = _equipment_stack(reduced_slots, WEAPON_ID, _rune_ids([&"", &"", RUNE_ID]))
	var weapon := catalog.get_definition(WEAPON_ID)
	var original_slot_unlock_levels := weapon.proficiency.slot_unlock_levels
	weapon.proficiency.slot_unlock_levels = PackedInt32Array([0])
	var reduced_slot_coordinator := RuneSocketingCoordinator.new()
	_expect(reduced_slot_coordinator.setup(reduced_slots, ItemProficiency.new(catalog)), "grandfathered removed socket was rejected")
	_expect(reduced_slot_coordinator.get_total_slot_count(0) == 3, "grandfathered removed socket was hidden")
	_expect(reduced_slot_coordinator.get_slot_state(0, 2) == RuneSocketingCoordinator.SlotState.FILLED, "grandfathered removed socket was not filled")
	_expect(reduced_slot_coordinator.can_unsocket(0, 2), "grandfathered removed socket could not be unsocketed")
	_expect(reduced_slot_coordinator.try_unsocket(0, 2), "grandfathered removed socket did not unsocket")
	weapon.proficiency.slot_unlock_levels = original_slot_unlock_levels

	var preattached_rune := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	preattached_rune.slots[0] = _equipment_stack(preattached_rune, WEAPON_ID, _rune_ids([&"", RUNE_ID]))
	var preattached_coordinator := RuneSocketingCoordinator.new()
	_expect(preattached_coordinator.setup(preattached_rune, ItemProficiency.new(catalog)), "preattached rune in a locked slot was rejected")
	_expect(preattached_coordinator.get_slot_state(0, 1) == RuneSocketingCoordinator.SlotState.FILLED, "preattached locked rune was not visible")
	_expect(preattached_coordinator.can_unsocket(0, 1), "preattached locked rune could not be unsocketed")

	var too_many := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	too_many.slots[0] = _unchecked_equipment_stack(WEAPON_ID, _rune_ids([RUNE_ID, RUNE_ID, RUNE_ID, RUNE_ID]))
	_expect(not RuneSocketingCoordinator.new().setup(too_many, ItemProficiency.new(catalog)), "loadout beyond gear capacity was accepted")

	var non_gear := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	non_gear.slots[0] = _unchecked_equipment_stack(&"sand_block", _rune_ids([RUNE_ID]))
	var failed_coordinator := RuneSocketingCoordinator.new()
	_expect(not failed_coordinator.setup(non_gear, ItemProficiency.new(catalog)), "socketed non-gear item was accepted")
	_expect(not failed_coordinator.is_socketable_gear_index(0), "failed setup retained dependencies")

func _test_full_inventory_rejection(catalog: ItemCatalog) -> void:
	var inventory := InventoryModel.new(catalog, EquipmentInstanceFactory.new(catalog))
	inventory.slots[0] = _equipment_stack(inventory, WEAPON_ID, _rune_ids([RUNE_ID]))
	for index in range(1, InventoryModel.FILLABLE_SIZE):
		inventory.slots[index] = InventoryStack.new(&"sand_block", 99)
	var coordinator := RuneSocketingCoordinator.new()
	_expect(coordinator.setup(inventory, ItemProficiency.new(catalog)), "full inventory fixture was invalid")
	var before := inventory.to_dict()
	_expect(not coordinator.can_unsocket(0, 0), "unsocket was allowed without inventory capacity")
	_expect(not coordinator.try_unsocket(0, 0), "unsocket committed without inventory capacity")
	_expect(inventory.to_dict() == before, "failed unsocket changed full inventory")

func _build_catalog() -> ItemCatalog:
	var source := load("res://items/item_catalog.tres") as ItemCatalog
	var armor_type := source.get_equipment_type(&"armor")
	var weapon := source.get_definition(&"copper_sword").duplicate(true) as ItemDefinition
	weapon.id = WEAPON_ID
	weapon.proficiency = _proficiency_definition()
	var rune := source.get_definition(RUNE_ID).duplicate(true) as RuneDefinition
	var armor_only_rune := rune.duplicate(true) as RuneDefinition
	armor_only_rune.id = ARMOR_ONLY_RUNE_ID
	var compatible_types: Array[EquipmentTypeDefinition] = [armor_type]
	armor_only_rune.compatible_equipment_types = compatible_types
	armor_only_rune.compatible_armor_slots = RuneDefinition.ALL_ARMOR_SLOTS
	var sand := source.get_definition(&"sand_block")
	var definitions: Array[ItemDefinition] = [weapon, rune, armor_only_rune, sand]
	var catalog := ItemCatalog.new()
	catalog.equipment_types = source.equipment_types
	catalog.definitions = definitions
	return catalog

func _proficiency_definition() -> ProficiencyDefinition:
	var definition := ProficiencyDefinition.new()
	definition.experience_requirements = PackedFloat64Array([10.0, 10.0, 10.0])
	definition.slot_unlock_levels = PackedInt32Array([0, 1, 2])
	return definition

func _rune_ids(values: Array[StringName]) -> Array[StringName]:
	return values

func _equipment_stack(
	inventory: InventoryModel,
	item_id: StringName,
	rune_ids: Array[StringName] = [],
) -> InventoryStack:
	var affixes: Array[EquipmentAffixDefinition] = []
	var instance := inventory.equipment_instance_factory.create(item_id, affixes, rune_ids)
	assert(instance != null)
	return InventoryStack.new(item_id, 1, instance)

func _unchecked_equipment_stack(
	item_id: StringName,
	rune_ids: Array[StringName],
) -> InventoryStack:
	var affixes: Array[EquipmentAffixInstance] = []
	return InventoryStack.new(item_id, 1, EquipmentInstance.new(1, affixes, rune_ids))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
