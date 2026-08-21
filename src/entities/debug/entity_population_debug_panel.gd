extends CanvasLayer
class_name EntityPopulationDebugPanel

const REFRESH_INTERVAL_SECONDS: float = 0.25

@onready var panel: Panel = $Panel
@onready var close_button: Button = $Panel/VBox/Header/CloseButton
@onready var scope_label: Label = $Panel/VBox/ScopeLabel
@onready var total_label: Label = $Panel/VBox/TotalLabel
@onready var population_label: Label = $Panel/VBox/PopulationLabel

var _snapshot_provider: Callable
var _refresh_remaining: float = 0.0

func _ready() -> void:
	visible = false
	set_process(false)
	panel.add_theme_stylebox_override("panel", WildesStyle.make_panel(Color(0.06, 0.07, 0.09, 0.94), 10, Color(0.55, 0.68, 0.82, 0.72), 1))
	close_button.pressed.connect(hide_panel)

func setup(snapshot_provider: Callable) -> void:
	assert(snapshot_provider.is_valid())
	_snapshot_provider = snapshot_provider

func _process(delta: float) -> void:
	_refresh_remaining = maxf(_refresh_remaining - delta, 0.0)
	if _refresh_remaining <= 0.0:
		refresh_population()

func toggle_panel() -> void:
	if visible:
		hide_panel()
	else:
		show_panel()

func show_panel() -> void:
	assert(_snapshot_provider.is_valid())
	visible = true
	set_process(true)
	refresh_population()

func hide_panel() -> void:
	visible = false
	set_process(false)

func is_open() -> bool:
	return visible

func refresh_population() -> void:
	if not _snapshot_provider.is_valid():
		return
	var snapshot := _snapshot_provider.call() as Dictionary
	if snapshot.is_empty():
		scope_label.text = "No active entity runtime"
		total_label.text = "Active: 0"
		population_label.text = ""
		return
	scope_label.text = String(snapshot.get("scope", "Current area"))
	var active := int(snapshot.get("active", 0))
	var population_cost := int(snapshot.get("population_cost", 0))
	var population_capacity := int(snapshot.get("population_capacity", 0))
	total_label.text = "Active: %d    Cost: %d / %d" % [active, population_cost, population_capacity]
	var lines: PackedStringArray = []
	for row in snapshot.get("rows", []) as Array:
		var definition_id := row.get("id", &"") as StringName
		var count := int(row.get("active", 0))
		var cap := int(row.get("ambient_cap", 0))
		var policy := "disabled" if not bool(row.get("ambient_enabled", false)) else ("uncapped" if cap == 0 else "cap %d" % cap)
		lines.append("%s: %d (%s)" % [String(definition_id).capitalize(), count, policy])
	population_label.text = "\n".join(lines)
	_refresh_remaining = REFRESH_INTERVAL_SECONDS
