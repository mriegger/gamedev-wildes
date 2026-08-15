extends CanvasLayer
class_name LevelEncounterHUD

const CLEARED_SECONDS: float = 1.5

@onready var _panel: PanelContainer = $Panel as PanelContainer
@onready var _label: Label = $Panel/Margin/Label as Label

var _clear_remaining: float = 0.0

func _ready() -> void:
	_panel.visible = false
	set_process(false)

func show_encounter(active_enemy_count: int, pending_enemy_count: int) -> void:
	assert(active_enemy_count >= 0 and pending_enemy_count >= 0 and active_enemy_count + pending_enemy_count > 0)
	_clear_remaining = 0.0
	_label.text = "Room Locked  •  %d active  •  %d pending" % [active_enemy_count, pending_enemy_count]
	_panel.visible = true
	set_process(false)

func show_cleared() -> void:
	_clear_remaining = CLEARED_SECONDS
	_label.text = "Room Cleared"
	_panel.visible = true
	set_process(true)

func hide_status() -> void:
	_clear_remaining = 0.0
	_panel.visible = false
	set_process(false)

func _process(delta: float) -> void:
	_clear_remaining = maxf(_clear_remaining - delta, 0.0)
	if is_zero_approx(_clear_remaining):
		hide_status()
