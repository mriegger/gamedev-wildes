extends Sprite3D
class_name EnemyHealthBar3D

const TEXTURE_WIDTH: int = 48
const TEXTURE_HEIGHT: int = 6
const PIXEL_SIZE: float = 0.025
const HEIGHT_OFFSET: float = 0.25
const BACKGROUND_COLOR: Color = Color(0.015, 0.015, 0.02, 0.95)
const HEALTH_COLOR: Color = Color(0.9, 0.08, 0.08, 1.0)

var _stats: ActorStats
var _image: Image
var _image_texture: ImageTexture

func setup(stats: ActorStats, body_height: float) -> void:
	assert(stats != null and stats.has_stat(&"hp"))
	assert(is_finite(body_height) and body_height > 0.0)
	assert(_stats == null)
	_stats = stats
	position = Vector3(0.0, body_height + HEIGHT_OFFSET, 0.0)
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	centered = true
	double_sided = true
	fixed_size = false
	no_depth_test = false
	shaded = false
	pixel_size = PIXEL_SIZE
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_image = Image.create(TEXTURE_WIDTH, TEXTURE_HEIGHT, false, Image.FORMAT_RGBA8)
	_image_texture = ImageTexture.create_from_image(_image)
	texture = _image_texture
	_stats.health_changed.connect(_on_health_changed)
	_refresh(_stats.current_hp, _stats.get_value(&"hp"))

func get_health_ratio() -> float:
	if _stats == null:
		return 1.0
	return clampf(_stats.current_hp / _stats.get_value(&"hp"), 0.0, 1.0)

func _on_health_changed(current_hp: float, maximum_hp: float) -> void:
	_refresh(current_hp, maximum_hp)

func _refresh(current_hp: float, maximum_hp: float) -> void:
	assert(is_finite(current_hp) and is_finite(maximum_hp) and maximum_hp > 0.0)
	var ratio := clampf(current_hp / maximum_hp, 0.0, 1.0)
	visible = current_hp > 0.0 and ratio < 1.0
	_image.fill(BACKGROUND_COLOR)
	var interior_width := TEXTURE_WIDTH - 2
	var fill_width := roundi(float(interior_width) * ratio)
	for x in range(1, 1 + fill_width):
		for y in range(1, TEXTURE_HEIGHT - 1):
			_image.set_pixel(x, y, HEALTH_COLOR)
	_image_texture.update(_image)

func _exit_tree() -> void:
	if _stats != null and _stats.health_changed.is_connected(_on_health_changed):
		_stats.health_changed.disconnect(_on_health_changed)
	_stats = null
