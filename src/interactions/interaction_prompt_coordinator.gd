extends RefCounted
class_name InteractionPromptCoordinator

var _hud: HUD
var _is_gameplay_ui_blocked: Callable
var _level_prompt: String
var _harvest_prompt: String

func setup(hud: HUD, is_gameplay_ui_blocked: Callable) -> void:
	assert(hud != null)
	assert(is_gameplay_ui_blocked.is_valid())
	assert(_hud == null)
	_hud = hud
	_is_gameplay_ui_blocked = is_gameplay_ui_blocked

func set_level_prompt(text: String) -> void:
	if _level_prompt == text:
		return
	_level_prompt = text
	_refresh()

func set_harvest_prompt(text: String) -> void:
	if _harvest_prompt == text:
		return
	_harvest_prompt = text
	_refresh()

func is_interaction_blocked() -> bool:
	assert(_hud != null)
	return bool(_is_gameplay_ui_blocked.call())

func _refresh() -> void:
	assert(_hud != null)
	var text := _harvest_prompt if not _harvest_prompt.is_empty() else _level_prompt
	if text.is_empty():
		_hud.hide_interaction_prompt()
	else:
		_hud.show_interaction_prompt(text)
