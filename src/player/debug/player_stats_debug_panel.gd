extends CanvasLayer
class_name PlayerStatsDebugPanel

@onready var panel: Panel = $Panel
@onready var close_button: Button = $Panel/VBox/Header/CloseButton
@onready var level: SpinBox = $Panel/VBox/Progression/Level
@onready var experience: SpinBox = $Panel/VBox/Progression/Experience
@onready var current_hp: SpinBox = $Panel/VBox/CurrentHP/Value
@onready var stats_grid: GridContainer = $Panel/VBox/StatsGrid

var _stats: ActorStats
var _base_controls: Dictionary = {}
var _effective_labels: Dictionary = {}
var _syncing: bool = false

func _ready():
	panel.add_theme_stylebox_override("panel", WildesStyle.make_panel(Color(0.06, 0.07, 0.09, 0.96), 10, Color(0.55, 0.68, 0.82, 0.72), 1))
	close_button.pressed.connect(hide_panel)
	level.value_changed.connect(_on_progression_changed)
	experience.value_changed.connect(_on_progression_changed)
	current_hp.value_changed.connect(_on_current_hp_changed)

func setup(stats: ActorStats):
	_stats = stats
	for stat_id in stats.get_stat_ids():
		var label := Label.new()
		label.text = String(stat_id).capitalize()
		stats_grid.add_child(label)
		var base := SpinBox.new()
		base.name = "%sBase" % String(stat_id).to_pascal_case()
		base.min_value = 0.0
		base.max_value = 999999.0
		base.allow_greater = true
		base.value_changed.connect(_on_base_value_changed.bind(stat_id))
		stats_grid.add_child(base)
		var effective := Label.new()
		effective.custom_minimum_size.x = 100.0
		stats_grid.add_child(effective)
		_base_controls[stat_id] = base
		_effective_labels[stat_id] = effective
	_refresh()

func _process(_delta):
	if visible:
		_refresh()

func is_open() -> bool:
	return visible

func toggle_panel():
	visible = not visible
	if visible:
		_refresh()

func hide_panel():
	visible = false

func _refresh():
	if _stats == null:
		return
	_syncing = true
	level.set_value_no_signal(_stats.level)
	experience.max_value = 999999999.0
	experience.set_value_no_signal(_stats.experience)
	current_hp.max_value = _stats.get_value(&"hp")
	current_hp.set_value_no_signal(_stats.current_hp)
	for stat_id in _base_controls:
		(_base_controls[stat_id] as SpinBox).set_value_no_signal(_stats.get_base_value(stat_id))
		(_effective_labels[stat_id] as Label).text = "Effective: %.2f" % _stats.get_value(stat_id)
	_syncing = false

func _on_base_value_changed(value: float, stat_id: StringName):
	if not _syncing:
		_stats.set_base_value(stat_id, value)

func _on_current_hp_changed(value: float):
	if not _syncing:
		_stats.set_current_hp(value)

func _on_progression_changed(_value: float):
	if not _syncing:
		_stats.set_progression(roundi(level.value), roundi(experience.value))
