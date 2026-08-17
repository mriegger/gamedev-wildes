extends RefCounted
class_name CreativeToolbelt

const SLOT_COUNT: int = 9

var _item_catalog: ItemCatalog
var _placeable_item_ids: Array[StringName] = []
var _assigned_item_ids: Array[StringName] = []
var _selected_index: int = 0

func setup(item_catalog: ItemCatalog) -> bool:
	if item_catalog == null or _item_catalog != null:
		return false
	var placeable_item_ids: Array[StringName] = []
	for definition in item_catalog.definitions:
		if definition != null and definition.secondary_action is BlockPlacementActionDefinition:
			placeable_item_ids.append(definition.id)
	if placeable_item_ids.size() < SLOT_COUNT:
		return false
	_item_catalog = item_catalog
	_placeable_item_ids.assign(placeable_item_ids)
	for index in range(SLOT_COUNT):
		_assigned_item_ids.append(_placeable_item_ids[index])
	return true

func get_placeable_item_ids() -> Array[StringName]:
	return _placeable_item_ids.duplicate()

func get_assigned_item_ids() -> Array[StringName]:
	return _assigned_item_ids.duplicate()

func get_selected_index() -> int:
	return _selected_index

func get_selected_item_id() -> StringName:
	return _assigned_item_ids[_selected_index]

func get_selected_placement_action() -> BlockPlacementActionDefinition:
	return _item_catalog.get_definition(get_selected_item_id()).secondary_action as BlockPlacementActionDefinition

func try_assign(slot_index: int, item_id: StringName) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT or not _placeable_item_ids.has(item_id):
		return false
	if _assigned_item_ids[slot_index] == item_id:
		return false
	_assigned_item_ids[slot_index] = item_id
	return true

func try_select(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= SLOT_COUNT or slot_index == _selected_index:
		return false
	_selected_index = slot_index
	return true
