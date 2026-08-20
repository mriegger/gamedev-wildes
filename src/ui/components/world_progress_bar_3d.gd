extends Sprite3D
class_name WorldProgressBar3D

var _image: Image
var _image_texture: ImageTexture
var _bar_width: int = 0
var _bar_height: int = 0
var _background_color: Color
var _fill_color: Color
var _fill_ratio: float = 0.0
var _active: bool = false
var _has_rendered: bool = false

func configure_bar(width: int, height: int, p_pixel_size: float, background_color: Color, fill_color: Color) -> void:
	assert(width >= 3 and height >= 3)
	assert(is_finite(p_pixel_size) and p_pixel_size > 0.0)
	assert(_image == null)
	_bar_width = width
	_bar_height = height
	_background_color = background_color
	_fill_color = fill_color
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	centered = true
	double_sided = true
	fixed_size = false
	no_depth_test = false
	shaded = false
	pixel_size = p_pixel_size
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_image = Image.create(_bar_width, _bar_height, false, Image.FORMAT_RGBA8)
	_image_texture = ImageTexture.create_from_image(_image)
	texture = _image_texture

func set_bar_fill(active: bool, ratio: float) -> void:
	assert(_image != null and is_finite(ratio))
	var next_ratio := clampf(ratio, 0.0, 1.0)
	if _has_rendered and _active == active and is_equal_approx(_fill_ratio, next_ratio):
		return
	_active = active
	_fill_ratio = next_ratio
	_has_rendered = true
	visible = active
	_image.fill(_background_color)
	var interior_width := _bar_width - 2
	var fill_width := roundi(float(interior_width) * _fill_ratio)
	for x in range(1, 1 + fill_width):
		for y in range(1, _bar_height - 1):
			_image.set_pixel(x, y, _fill_color)
	_image_texture.update(_image)
