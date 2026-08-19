extends RefCounted
class_name PreparedInventoryLoadoutChange

var _owner: RefCounted
var _inventory_change: PreparedInventoryChange
var _stat_change: PreparedStatModifierChange
var _committed: bool = false
var _notified: bool = false
var _depleted: bool = false
var _health_changed: bool = false

func _init(
	p_owner: RefCounted,
	p_inventory_change: PreparedInventoryChange,
	p_stat_change: PreparedStatModifierChange,
) -> void:
	_owner = p_owner
	_inventory_change = p_inventory_change
	_stat_change = p_stat_change

func get_result_stack() -> InventoryStack:
	return _inventory_change.get_result_stack()

func _is_for(owner: RefCounted) -> bool:
	return _owner == owner

func _get_inventory_change() -> PreparedInventoryChange:
	return _inventory_change

func _get_stat_change() -> PreparedStatModifierChange:
	return _stat_change

func _mark_committed(depleted: bool, health_changed: bool) -> bool:
	if _committed:
		return false
	_committed = true
	_depleted = depleted
	_health_changed = health_changed
	return true

func _consume_notification() -> bool:
	if not _committed or _notified:
		return false
	_notified = true
	return true

func _should_notify_health_changed() -> bool:
	return _notified and _health_changed

func _should_notify_health_depleted() -> bool:
	return _notified and _depleted
