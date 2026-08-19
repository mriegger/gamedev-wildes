extends RefCounted
class_name PreparedHarvestTransaction

var _owner: RefCounted
var _source: HarvestSource
var _source_change: PreparedHarvestChange
var _inventory_change: PreparedInventoryLoadoutChange

func _init(
	p_owner: RefCounted,
	p_source: HarvestSource,
	p_source_change: PreparedHarvestChange,
	p_inventory_change: PreparedInventoryLoadoutChange,
) -> void:
	_owner = p_owner
	_source = p_source
	_source_change = p_source_change
	_inventory_change = p_inventory_change

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _get_source() -> HarvestSource:
	return _source

func _get_source_change() -> PreparedHarvestChange:
	return _source_change

func _get_inventory_change() -> PreparedInventoryLoadoutChange:
	return _inventory_change
