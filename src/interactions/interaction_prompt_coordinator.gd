extends RefCounted
class_name InteractionPromptCoordinator

var _hud: HUD
var _level_prompt: String
var _harvest_prompt: String

func setup(hud: HUD) -> void:
	assert(hud != null)
	assert(_hud == null)
	_hud = hud

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
	return _hud.is_side_panel_open() or _hud.dev_console.is_open()

func _refresh() -> void:
	assert(_hud != null)
	var text := _harvest_prompt if not _harvest_prompt.is_empty() else _level_prompt
	if text.is_empty():
		_hud.hide_interaction_prompt()
	else:
		_hud.show_interaction_prompt(text)
