extends Node
class_name PlacementPromptCoordinator

const PROMPT: String = "Right Click to Place Block"

var _interactor: PlayerInteractor
var _prompt: InteractionPromptCoordinator
var _visible: bool = false

func _ready() -> void:
	set_process(false)

func setup(interactor: PlayerInteractor, prompt: InteractionPromptCoordinator) -> void:
	assert(interactor != null and prompt != null)
	assert(_interactor == null and _prompt == null)
	_interactor = interactor
	_prompt = prompt
	set_process(true)
	_refresh()

func _exit_tree() -> void:
	if _prompt != null:
		_prompt.set_placement_prompt("")

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	var visible := (
		_interactor != null
		and _interactor.is_editing_enabled()
		and _interactor.get_selected_placement_action() != null
		and not _prompt.is_interaction_blocked()
	)
	if _visible == visible:
		return
	_visible = visible
	_prompt.set_placement_prompt(PROMPT if visible else "")
