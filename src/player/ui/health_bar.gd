extends Control
class_name PlayerHealthBar

const PREFERRED_WIDTH: float = 280.0
const BAR_HEIGHT: float = 16.0
const EDGE_MARGIN: float = 24.0

@onready var progress_bar: ProgressBar = $ProgressBar as ProgressBar
@onready var value_label: Label = $ProgressBar/ValueLabel as Label

var _stats: ActorStats
var _right_inset: float = 0.0

func _ready():
	set_process(false)
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()

func setup(stats: ActorStats):
	assert(stats != null and stats.has_stat(&"hp"))
	_stats = stats
	_refresh()
	set_process(true)

func _process(_delta: float):
	_refresh()

func set_right_inset(inset: float):
	assert(is_finite(inset) and inset >= 0.0)
	_right_inset = inset
	_apply_layout()

func _apply_layout():
	var viewport_width := get_viewport_rect().size.x
	var available_width := maxf(viewport_width - _right_inset - EDGE_MARGIN * 2.0, 0.0)
	var bar_width := minf(PREFERRED_WIDTH, available_width)
	progress_bar.offset_right = -(EDGE_MARGIN + _right_inset)
	progress_bar.offset_left = progress_bar.offset_right - bar_width
	progress_bar.offset_top = EDGE_MARGIN
	progress_bar.offset_bottom = EDGE_MARGIN + BAR_HEIGHT
	progress_bar.visible = bar_width > 0.0

func _refresh():
	var maximum_hp := _stats.get_value(&"hp")
	progress_bar.max_value = maximum_hp
	progress_bar.value = _stats.current_hp
	value_label.text = "HP %s / %s" % [_format_value(_stats.current_hp), _format_value(maximum_hp)]

func _format_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return String.num(value, 1)
