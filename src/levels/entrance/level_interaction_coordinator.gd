extends Node
class_name LevelInteractionCoordinator

signal interaction_requested

const INTERACTION_RANGE: float = 2.5

var _player: PlayerMotor
var _prompt_coordinator: InteractionPromptCoordinator
var _target_position: Vector3
var _prompt: String
var _has_target: bool = false
var _prompt_visible: bool = false

func _ready():
	set_process(false)

func setup(player: PlayerMotor, prompt_coordinator: InteractionPromptCoordinator):
	assert(player != null and prompt_coordinator != null)
	_player = player
	_prompt_coordinator = prompt_coordinator
	set_process(true)

func set_target(position: Vector3, prompt: String):
	_target_position = position
	_prompt = prompt
	_has_target = true

func clear_target():
	_has_target = false
	_set_prompt_visible(false)

func _process(_delta: float):
	var in_range := _has_target and not _prompt_coordinator.is_interaction_blocked() and _player.global_position.distance_squared_to(_target_position) <= INTERACTION_RANGE * INTERACTION_RANGE
	_set_prompt_visible(in_range)
	if in_range and Input.is_action_just_pressed("interact"):
		interaction_requested.emit()

func _set_prompt_visible(visible: bool):
	if _prompt_visible == visible:
		return
	_prompt_visible = visible
	if visible:
		_prompt_coordinator.set_level_prompt(_prompt)
	else:
		_prompt_coordinator.set_level_prompt("")
