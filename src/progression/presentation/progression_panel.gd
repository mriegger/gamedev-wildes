extends VBoxContainer
class_name ProgressionPanel

@onready var level_label: Label = $Overview/Level as Label
@onready var experience_bar: ProgressBar = $Overview/ExperienceBar as ProgressBar
@onready var experience_label: Label = $Overview/ExperienceBar/Value as Label
@onready var available_points_label: Label = $AvailablePoints as Label
@onready var _perk_list: VBoxContainer = $PerkScroll/PerkList as VBoxContainer

var _actor_stats: ActorStats
var _perk_coordinator: PlayerPerkCoordinator
var _perk_rows: Dictionary = {}

func _ready() -> void:
	set_process(false)

func setup(actor_stats: ActorStats, perk_coordinator: PlayerPerkCoordinator) -> void:
	assert(actor_stats != null)
	assert(perk_coordinator != null)
	_actor_stats = actor_stats
	_perk_coordinator = perk_coordinator
	_build_perk_rows()
	_refresh()

func set_workspace_active(active: bool) -> void:
	if active and _actor_stats != null and _perk_coordinator != null:
		_refresh()
	set_process(active and _actor_stats != null and _perk_coordinator != null)

func get_displayed_perk_ids() -> Array[StringName]:
	var perk_ids: Array[StringName] = []
	for row in _perk_list.get_children():
		perk_ids.append(StringName(row.get_meta(&"perk_id")))
	return perk_ids

func get_perk_row(perk_id: StringName) -> PanelContainer:
	return _perk_rows.get(perk_id, null) as PanelContainer

func _process(_delta: float) -> void:
	_refresh()

func _build_perk_rows() -> void:
	for child in _perk_list.get_children():
		child.free()
	_perk_rows.clear()
	for definition in _perk_coordinator.get_definitions():
		var row := PanelContainer.new()
		row.name = String(definition.id).to_pascal_case()
		row.custom_minimum_size.y = 82.0
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_meta(&"perk_id", definition.id)
		var row_style := WildesStyle.make_panel(Color(0.10, 0.12, 0.14, 0.46), 9, Color(1, 1, 1, 0.12), 1)
		row_style.content_margin_left = 12.0
		row_style.content_margin_top = 10.0
		row_style.content_margin_right = 12.0
		row_style.content_margin_bottom = 10.0
		row.add_theme_stylebox_override(&"panel", row_style)

		var content := HBoxContainer.new()
		content.name = "Content"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override(&"separation", 10)
		row.add_child(content)

		var details := VBoxContainer.new()
		details.name = "Details"
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		details.mouse_filter = Control.MOUSE_FILTER_IGNORE
		details.add_theme_constant_override(&"separation", 4)
		content.add_child(details)

		var name_label := Label.new()
		name_label.name = "Name"
		name_label.text = definition.display_name
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_override(&"font", WildesStyle.BOLD_FONT)
		name_label.add_theme_font_size_override(&"font_size", 15)
		details.add_child(name_label)

		var effect_label := Label.new()
		effect_label.name = "Effect"
		effect_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		effect_label.add_theme_color_override(&"font_color", Color(0.70, 0.78, 0.72, 1))
		effect_label.add_theme_font_size_override(&"font_size", 11)
		details.add_child(effect_label)

		var rank_label := Label.new()
		rank_label.name = "Rank"
		rank_label.custom_minimum_size.x = 78.0
		rank_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_label.add_theme_font_override(&"font", WildesStyle.BOLD_FONT)
		rank_label.add_theme_font_size_override(&"font_size", 12)
		content.add_child(rank_label)

		var allocate_button := Button.new()
		allocate_button.name = "Allocate"
		allocate_button.custom_minimum_size = Vector2(88, 42)
		allocate_button.focus_mode = Control.FOCUS_NONE
		allocate_button.text = "ALLOCATE"
		allocate_button.add_theme_font_override(&"font", WildesStyle.BOLD_FONT)
		allocate_button.add_theme_font_size_override(&"font_size", 11)
		allocate_button.add_theme_stylebox_override(&"normal", WildesStyle.make_panel(Color(0.25, 0.42, 0.31, 0.72), 8, Color(0.62, 0.86, 0.69, 0.42), 1))
		allocate_button.add_theme_stylebox_override(&"hover", WildesStyle.make_panel(Color(0.34, 0.54, 0.41, 0.82), 8, Color(0.70, 0.92, 0.76, 0.68), 1))
		allocate_button.add_theme_stylebox_override(&"pressed", WildesStyle.make_panel(Color(0.18, 0.31, 0.23, 0.84), 8, Color(0.52, 0.76, 0.60, 0.64), 1))
		allocate_button.add_theme_stylebox_override(&"disabled", WildesStyle.make_panel(Color(0.10, 0.12, 0.14, 0.38), 8, Color(1, 1, 1, 0.07), 1))
		allocate_button.pressed.connect(_on_allocate_pressed.bind(definition.id))
		content.add_child(allocate_button)

		_perk_list.add_child(row)
		_perk_rows[definition.id] = row

func _refresh() -> void:
	if _actor_stats == null or _perk_coordinator == null:
		return
	var required_experience := _actor_stats.get_experience_to_next_level()
	level_label.text = "LEVEL %d" % _actor_stats.level
	experience_bar.max_value = required_experience
	experience_bar.value = _actor_stats.experience
	experience_label.text = "XP %d / %d" % [_actor_stats.experience, required_experience]
	available_points_label.text = "AVAILABLE POINTS: %d" % _perk_coordinator.get_unspent_point_count()
	for definition in _perk_coordinator.get_definitions():
		var row := get_perk_row(definition.id)
		var rank := _perk_coordinator.get_rank(definition.id)
		var effect_name := "HP" if definition.stat_id == &"hp" else definition.display_name
		var per_rank := _format_amount(definition.amount_per_rank)
		var total := _format_amount(definition.get_amount(rank))
		(row.get_node("Content/Details/Effect") as Label).text = "+%s %s per rank · +%s %s total" % [per_rank, effect_name, total, effect_name]
		(row.get_node("Content/Rank") as Label).text = "Rank %d / %d" % [rank, definition.maximum_rank]
		(row.get_node("Content/Allocate") as Button).disabled = not _perk_coordinator.can_allocate(definition.id)

func _on_allocate_pressed(perk_id: StringName) -> void:
	_perk_coordinator.try_allocate(perk_id)
	_refresh()

func _format_amount(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return str(roundi(amount))
	return str(amount)
