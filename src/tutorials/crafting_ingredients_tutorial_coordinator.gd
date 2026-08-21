extends Node
class_name CraftingIngredientsTutorialCoordinator

var _crafting_panel: CraftingPanel
var _view: CraftingIngredientsTutorialView
var _progress: TutorialProgress
var _callout_arbiter: TutorialCalloutArbiter
var _pending: bool = false

func _ready() -> void:
	set_process(false)

func setup(
	crafting_panel: CraftingPanel,
	view: CraftingIngredientsTutorialView,
	progress: TutorialProgress,
	callout_arbiter: TutorialCalloutArbiter,
) -> void:
	assert(crafting_panel != null and view != null and progress != null and callout_arbiter != null)
	assert(_crafting_panel == null and _view == null and _progress == null and _callout_arbiter == null)
	_crafting_panel = crafting_panel
	_view = view
	_progress = progress
	_callout_arbiter = callout_arbiter
	_view.setup(crafting_panel)
	_crafting_panel.opened.connect(_on_crafting_opened)
	_crafting_panel.closed.connect(_on_crafting_closed)
	_crafting_panel.interacted.connect(_on_crafting_interacted)
	_view.tip_hidden.connect(_on_view_hidden)

func _exit_tree() -> void:
	if _crafting_panel != null and _crafting_panel.opened.is_connected(_on_crafting_opened):
		_crafting_panel.opened.disconnect(_on_crafting_opened)
	if _crafting_panel != null and _crafting_panel.closed.is_connected(_on_crafting_closed):
		_crafting_panel.closed.disconnect(_on_crafting_closed)
	if _crafting_panel != null and _crafting_panel.interacted.is_connected(_on_crafting_interacted):
		_crafting_panel.interacted.disconnect(_on_crafting_interacted)
	if _view != null and _view.tip_hidden.is_connected(_on_view_hidden):
		_view.tip_hidden.disconnect(_on_view_hidden)
	if _callout_arbiter != null:
		_callout_arbiter.release(self)

func _process(_delta: float) -> void:
	if not _pending or _progress.is_crafting_ingredients_tip_completed() or not _crafting_panel.is_open():
		return
	if not _callout_arbiter.try_acquire(self):
		return
	_pending = false
	_view.show_tip()
	set_process(false)

func _on_crafting_opened() -> void:
	if _progress.is_crafting_ingredients_tip_completed():
		return
	_pending = true
	set_process(true)

func _on_crafting_closed() -> void:
	_complete()

func _on_crafting_interacted() -> void:
	_complete()

func _on_view_hidden() -> void:
	_callout_arbiter.release(self)

func _complete() -> void:
	if not _pending and not _view.is_showing():
		return
	_pending = false
	if not _progress.complete_crafting_ingredients_tip():
		return
	_view.hide_tip()
	set_process(false)
