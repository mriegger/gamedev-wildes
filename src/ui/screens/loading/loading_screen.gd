extends CanvasLayer
class_name LoadingScreen

const GAME_REVEAL_SECONDS := 0.8
const BAR_WIDTH_RATIO := 0.34
const MIN_BAR_WIDTH := 260.0
const MAX_BAR_WIDTH := 460.0
const BAR_HEIGHT := 4.0
const BAR_HORIZONTAL_MARGIN := 32.0

func _ready() -> void:
	get_viewport().size_changed.connect(_resize_progress_bar)
	_resize_progress_bar()

func setup(slot_id: int, save_data: Dictionary) -> void:
	var progress_bar := _get_progress_bar()
	var world_name := str(save_data.get("world_name", "World %d" % (slot_id + 1)))
	progress_bar.value = 0.0
	progress_bar.accessibility_name = "Loading %s" % world_name
	progress_bar.accessibility_description = "Preparing world"

func update_progress(stage: String, percent: float, details: String) -> void:
	var progress_bar := _get_progress_bar()
	progress_bar.value = maxf(progress_bar.value, clampf(percent, 0.0, 1.0) * 100.0)
	progress_bar.accessibility_description = "%s: %s" % [stage.capitalize(), details]

func fade_into_game() -> void:
	var control := $Control as Control
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(control, "modulate:a", 0.0, GAME_REVEAL_SECONDS)
	await tween.finished

func _resize_progress_bar() -> void:
	var viewport_width := get_viewport().get_visible_rect().size.x
	var available_width := maxf(viewport_width - BAR_HORIZONTAL_MARGIN, BAR_HEIGHT)
	_get_progress_bar().custom_minimum_size = Vector2(
		minf(clampf(viewport_width * BAR_WIDTH_RATIO, MIN_BAR_WIDTH, MAX_BAR_WIDTH), available_width),
		BAR_HEIGHT,
	)

func _get_progress_bar() -> ProgressBar:
	return get_node("Control/CenterContainer/ProgressBar") as ProgressBar
