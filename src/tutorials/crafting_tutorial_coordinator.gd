extends Node
class_name CraftingTutorialCoordinator

const SHOW_DELAY_SECONDS: float = 5.0

var _interactor: PlayerInteractor
var _crafting_panel: CraftingPanel
var _view: CraftingTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _armed: bool = false
var _elapsed: float = 0.0

func _ready() -> void:
	set_process(false)

func setup(
	interactor: PlayerInteractor,
	crafting_panel: CraftingPanel,
	view: CraftingTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
	has_mined_before: bool,
) -> void:
	assert(interactor != null and crafting_panel != null and view != null)
	assert(progress != null and callout_arbiter != null)
	assert(_interactor == null and _crafting_panel == null and _view == null and _progress == null)
	_interactor = interactor
	_crafting_panel = crafting_panel
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_armed = has_mined_before
	_interactor.block_mined.connect(_on_block_mined)
	_crafting_panel.opened.connect(_on_crafting_opened)
	_view.tip_hidden.connect(_on_view_hidden)
	set_process(_armed and not _progress.is_crafting_tip_completed())

func _exit_tree() -> void:
	if _interactor != null and _interactor.block_mined.is_connected(_on_block_mined):
		_interactor.block_mined.disconnect(_on_block_mined)
	if _crafting_panel != null and _crafting_panel.opened.is_connected(_on_crafting_opened):
		_crafting_panel.opened.disconnect(_on_crafting_opened)
	if _view != null and _view.tip_hidden.is_connected(_on_view_hidden):
		_view.tip_hidden.disconnect(_on_view_hidden)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)

func _process(delta: float) -> void:
	if _progress == null or _progress.is_crafting_tip_completed() or not _armed or _view.is_showing():
		return
	if not _callout_arbiter.is_available(self):
		_elapsed = 0.0
		return
	_elapsed += delta
	if _elapsed < SHOW_DELAY_SECONDS or not _callout_arbiter.try_acquire(self, dismiss_for_priority_callout):
		return
	_view.show_tip()

func _on_block_mined(_position: Vector3i, _block_id: int) -> void:
	if _progress.is_crafting_tip_completed() or _armed:
		return
	_armed = true
	_elapsed = 0.0
	set_process(true)

func _on_crafting_opened() -> void:
	_complete()

func _on_view_hidden() -> void:
	_callout_arbiter.release(self)

func dismiss_for_priority_callout() -> void:
	_complete()

func _complete() -> void:
	if not _progress.complete_crafting_tip():
		return
	_view.hide_tip()
	set_process(false)
