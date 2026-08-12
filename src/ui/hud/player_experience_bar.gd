extends Control
class_name PlayerExperienceBar

const PREFERRED_WIDTH: float = 624.0
const BAR_HEIGHT: float = 20.0
const HOTBAR_TOP_INSET: float = 96.0
const EDGE_MARGIN: float = 12.0

@onready var progress_bar: ProgressBar = $ProgressBar as ProgressBar
@onready var value_label: Label = $ProgressBar/ValueLabel as Label

var _stats: ActorStats
var _right_inset: float = 0.0

func _ready():
	set_process(false)
	get_viewport().size_changed.connect(_apply_layout)
	_apply_layout()

func setup(stats: ActorStats):
	assert(stats != null and stats.get_experience_to_next_level() > 0)
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
	var center_offset := _right_inset * -0.5
	progress_bar.offset_left = center_offset - bar_width * 0.5
	progress_bar.offset_top = -HOTBAR_TOP_INSET - BAR_HEIGHT
	progress_bar.offset_right = center_offset + bar_width * 0.5
	progress_bar.offset_bottom = -HOTBAR_TOP_INSET
	progress_bar.visible = bar_width > 0.0

func _refresh():
	var required_experience := _stats.get_experience_to_next_level()
	progress_bar.max_value = required_experience
	progress_bar.value = _stats.experience
	value_label.text = "Level %d - %d / %d XP" % [_stats.level, _stats.experience, required_experience]
