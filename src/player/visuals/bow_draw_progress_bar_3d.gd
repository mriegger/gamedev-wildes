extends WorldProgressBar3D
class_name BowDrawProgressBar3D

const TEXTURE_WIDTH: int = 64
const TEXTURE_HEIGHT: int = 8
const PIXEL_SIZE: float = 0.02
const HEIGHT_OFFSET: float = 0.3
const BACKGROUND_COLOR: Color = Color(0.015, 0.015, 0.02, 0.95)
const FILL_COLOR: Color = Color(0.96, 0.78, 0.08, 1.0)

var _progress: float = 0.0

func _ready() -> void:
	configure_bar(TEXTURE_WIDTH, TEXTURE_HEIGHT, PIXEL_SIZE, BACKGROUND_COLOR, FILL_COLOR)
	set_progress(false, 0.0)

func set_body_height(body_height: float) -> void:
	assert(is_finite(body_height) and body_height > 0.0)
	position = Vector3(0.0, body_height + HEIGHT_OFFSET, 0.0)

func set_progress(active: bool, progress: float) -> void:
	assert(is_finite(progress))
	_progress = clampf(progress, 0.0, 1.0)
	set_bar_fill(active, _progress)
