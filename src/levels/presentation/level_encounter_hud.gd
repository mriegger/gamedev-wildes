extends CanvasLayer
class_name LevelEncounterHUD

const CLEARED_SECONDS: float = 1.5

@onready var _panel: PanelContainer = $Panel as PanelContainer
@onready var _label: Label = $Panel/Margin/Label as Label

var _clear_remaining: float = 0.0

func _ready() -> void:
	_panel.visible = false
	set_process(false)

func show_summary(summary: LevelEncounterSummary) -> void:
	assert(summary != null)
	if summary.active_wave_count == 0:
		if is_zero_approx(_clear_remaining):
			hide_status()
		return
	_clear_remaining = 0.0
	var wave_label := "wave" if summary.active_wave_count == 1 else "waves"
	_label.text = "%d %s  •  %d active  •  %d pending" % [
		summary.active_wave_count,
		wave_label,
		summary.active_enemy_count,
		summary.pending_enemy_count,
	]
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
