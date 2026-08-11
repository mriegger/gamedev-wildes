extends Control
class_name CraftProgressButton

signal pressed

@onready var _base: Panel = $Base as Panel
@onready var _fill: Panel = $Fill as Panel
@onready var _button: Button = $Button as Button

var _progress: float = 0.0
var _craft_enabled: bool = false
var _crafting: bool = false

func _ready() -> void:
	_base.add_theme_stylebox_override("panel", WildesStyle.make_panel(Color(0.14, 0.16, 0.18, 0.92), 10, Color(1, 1, 1, 0.20), 1))
	_fill.add_theme_stylebox_override("panel", WildesStyle.make_panel(Color(0.34, 0.66, 0.42, 0.78), 10, Color(0, 0, 0, 0), 0))
	_button.add_theme_stylebox_override("normal", WildesStyle.make_panel(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0))
	_button.add_theme_stylebox_override("hover", WildesStyle.make_panel(Color(1, 1, 1, 0.08), 10, Color(1, 1, 1, 0.16), 1))
	_button.add_theme_stylebox_override("pressed", WildesStyle.make_panel(Color(0, 0, 0, 0.12), 10, Color(1, 1, 1, 0.18), 1))
	_button.add_theme_stylebox_override("focus", WildesStyle.make_panel(Color(0, 0, 0, 0), 10, Color(0, 0, 0, 0), 0))
	_button.add_theme_stylebox_override("disabled", WildesStyle.make_panel(Color(0, 0, 0, 0.10), 10, Color(0, 0, 0, 0), 0))
	_button.add_theme_font_override("font", WildesStyle.BOLD_FONT)
	_button.add_theme_font_size_override("font_size", 16)
	_button.pressed.connect(func(): pressed.emit())
	_refresh()

func set_progress(value: float) -> void:
	_progress = clampf(value, 0.0, 1.0)
	_refresh()

func set_craft_enabled(value: bool) -> void:
	_craft_enabled = value
	_refresh()

func set_crafting(value: bool) -> void:
	_crafting = value
	_refresh()

func get_progress() -> float:
	return _progress

func is_craft_enabled() -> bool:
	return _craft_enabled

func _refresh() -> void:
	if not is_node_ready():
		return
	_fill.anchor_right = _progress
	_fill.offset_right = 0.0
	_fill.visible = _progress > 0.0
	_button.disabled = not _craft_enabled or _crafting
	_button.text = "CRAFTING" if _crafting else "CRAFT"
