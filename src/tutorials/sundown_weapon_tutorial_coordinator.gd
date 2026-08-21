extends Node
class_name SundownWeaponTutorialCoordinator

const SUNDOWN_HOUR: float = 17.0
const NIGHT_HOUR: float = 19.0
var _inventory: InventoryModel
var _view: SundownWeaponTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _time_of_day_query: Callable
var _previous_time: float = 0.0
var _pending: bool = false

func _ready() -> void:
	set_process(false)

func setup(
	inventory: InventoryModel,
	view: SundownWeaponTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
	time_of_day_query: Callable,
) -> void:
	assert(inventory != null and view != null and progress != null and callout_arbiter != null)
	assert(time_of_day_query.is_valid())
	assert(_inventory == null and _view == null and _progress == null and _callout_arbiter == null)
	_inventory = inventory
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_time_of_day_query = time_of_day_query
	_previous_time = _get_time_of_day()
	_inventory.inventory_changed.connect(_on_inventory_changed)
	_view.tip_hidden.connect(_on_view_hidden)
	set_process(not _progress.is_sundown_weapon_tip_completed())
	if _previous_time >= SUNDOWN_HOUR and _previous_time < NIGHT_HOUR:
		_reach_sundown()

func _exit_tree() -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_on_inventory_changed):
		_inventory.inventory_changed.disconnect(_on_inventory_changed)
	if _view != null and _view.tip_hidden.is_connected(_on_view_hidden):
		_view.tip_hidden.disconnect(_on_view_hidden)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)

func _process(_delta: float) -> void:
	if _progress.is_sundown_weapon_tip_completed():
		set_process(false)
		return
	var current_time := _get_time_of_day()
	if not _pending and _crossed_sundown(_previous_time, current_time):
		_reach_sundown()
	_previous_time = current_time
	if not _pending:
		return
	if _has_weapon():
		_complete_without_showing()
		return
	if not _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
		return
	_pending = false
	_progress.complete_sundown_weapon_tip()
	_view.show_tip()
	set_process(false)

func dismiss_for_priority_callout() -> void:
	if _view.is_showing():
		_view.hide_tip()

func _on_inventory_changed() -> void:
	if _pending and _has_weapon():
		_complete_without_showing()

func _on_view_hidden() -> void:
	_callout_arbiter.release(self)

func _reach_sundown() -> void:
	if _has_weapon():
		_complete_without_showing()
		return
	_pending = true

func _complete_without_showing() -> void:
	_pending = false
	_progress.complete_sundown_weapon_tip()
	set_process(false)

func _has_weapon() -> bool:
	return CombatInventoryRules.has_ready_weapon(_inventory)

func _get_time_of_day() -> float:
	var time_of_day := float(_time_of_day_query.call())
	assert(is_finite(time_of_day))
	return fposmod(time_of_day, GameClock.HOURS_PER_DAY)

func _crossed_sundown(previous_time: float, current_time: float) -> bool:
	if current_time < previous_time:
		return current_time >= SUNDOWN_HOUR
	return previous_time < SUNDOWN_HOUR and current_time >= SUNDOWN_HOUR
