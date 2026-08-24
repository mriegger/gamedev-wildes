extends RefCounted
class_name PreparedApplePlantingTransaction

var _owner: RefCounted
var _plant_change: PreparedApplePlantChange
var _inventory_change: PreparedInventoryLoadoutChange

func _init(
	p_owner: RefCounted,
	p_plant_change: PreparedApplePlantChange,
	p_inventory_change: PreparedInventoryLoadoutChange,
) -> void:
	_owner = p_owner
	_plant_change = p_plant_change
	_inventory_change = p_inventory_change

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _get_plant_change() -> PreparedApplePlantChange:
	return _plant_change

func _get_inventory_change() -> PreparedInventoryLoadoutChange:
	return _inventory_change
