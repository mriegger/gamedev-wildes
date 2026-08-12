extends Control
class_name PlayerHealthBar

const BAR_WIDTH: float = 280.0
const RIGHT_MARGIN: float = 24.0

@onready var progress_bar: ProgressBar = $ProgressBar as ProgressBar
@onready var value_label: Label = $ProgressBar/ValueLabel as Label

var _stats: ActorStats

func _ready():
	set_process(false)

func setup(stats: ActorStats):
	assert(stats != null and stats.has_stat(&"hp"))
	_stats = stats
	_refresh()
	set_process(true)

func _process(_delta: float):
	_refresh()

func set_right_inset(inset: float):
	assert(is_finite(inset) and inset >= 0.0)
	progress_bar.offset_right = -(RIGHT_MARGIN + inset)
	progress_bar.offset_left = -(RIGHT_MARGIN + inset + BAR_WIDTH)

func _refresh():
	var maximum_hp := _stats.get_value(&"hp")
	progress_bar.max_value = maximum_hp
	progress_bar.value = _stats.current_hp
	value_label.text = "HP %s / %s" % [_format_value(_stats.current_hp), _format_value(maximum_hp)]

func _format_value(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return str(roundi(value))
	return String.num(value, 1)
