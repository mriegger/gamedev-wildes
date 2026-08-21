extends Node
class_name FoodTutorialCoordinator

const ACTIVATION_RADIUS: float = 10.0
const DISMISS_DISTANCE: float = 14.0
const SEARCH_INTERVAL: float = 0.25
const FOOD_ITEM_IDS: Array[StringName] = [&"apple", &"pumpkin"]

var _player: Node3D
var _is_overworld_active: Callable
var _harvest: HarvestCoordinator
var _view: FoodTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _target_bounds: Variant = null
var _search_elapsed: float = SEARCH_INTERVAL

func _ready() -> void:
	set_process(false)

func setup(
	player: Node3D,
	is_overworld_active: Callable,
	camera: Camera3D,
	harvest: HarvestCoordinator,
	view: FoodTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
) -> void:
	assert(player != null)
	assert(is_overworld_active.is_valid())
	assert(camera != null)
	assert(harvest != null)
	assert(view != null)
	assert(progress != null)
	assert(callout_arbiter != null)
	assert(_player == null and _harvest == null and _view == null and _progress == null)
	_player = player
	_is_overworld_active = is_overworld_active
	_harvest = harvest
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_view.setup(camera)
	_harvest.items_harvested.connect(_on_items_harvested)
	_view.callout_hidden.connect(_on_view_hidden)
	set_process(not _progress.is_food_tip_completed())

func _exit_tree() -> void:
	if _harvest != null and _harvest.items_harvested.is_connected(_on_items_harvested):
		_harvest.items_harvested.disconnect(_on_items_harvested)
	if _view != null and _view.callout_hidden.is_connected(_on_view_hidden):
		_view.callout_hidden.disconnect(_on_view_hidden)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)

func _process(delta: float) -> void:
	if _progress == null or _progress.is_food_tip_completed():
		return
	if not bool(_is_overworld_active.call()):
		if _view.is_showing():
			_view.hide_tip()
		_target_bounds = null
		return
	if _target_bounds is AABB:
		var target_bounds := _target_bounds as AABB
		if not _view.is_showing() and _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
			_view.show_tip(target_bounds)
		_view.set_outline_suppressed(_is_normal_harvest_outline_active(target_bounds))
		var center := target_bounds.get_center()
		var distance := Vector2(_player.global_position.x - center.x, _player.global_position.z - center.z).length()
		if distance > DISMISS_DISTANCE:
			_complete()
		return
	_search_elapsed += delta
	if _search_elapsed < SEARCH_INTERVAL:
		return
	_search_elapsed = 0.0
	var nearby_bounds = _harvest.find_nearby_target_bounds(
		_player.global_position,
		ACTIVATION_RADIUS,
		FOOD_ITEM_IDS,
	)
	if nearby_bounds is AABB:
		if not _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
			return
		_target_bounds = nearby_bounds
		_view.show_tip(nearby_bounds as AABB)

func _is_normal_harvest_outline_active(target_bounds: AABB) -> bool:
	return _harvest.has_target() and _harvest.get_target_bounds().is_equal_approx(target_bounds)

func _on_items_harvested(item_ids: Array[StringName]) -> void:
	for item_id in item_ids:
		if FOOD_ITEM_IDS.has(item_id):
			_complete()
			return

func _on_view_hidden() -> void:
	_callout_arbiter.release(self)

func dismiss_for_priority_callout() -> void:
	_complete()

func _complete() -> void:
	if not _progress.complete_food_tip():
		return
	_view.hide_tip()
	set_process(false)
