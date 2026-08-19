extends RefCounted
class_name OpaquePixelBounds

const ALPHA_THRESHOLD: float = 0.5

static func find(image: Image) -> Rect2i:
	assert(image != null and not image.is_empty())
	var min_position := Vector2i(image.get_width(), image.get_height())
	var max_position := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not contains(image, x, y):
				continue
			min_position.x = mini(min_position.x, x)
			min_position.y = mini(min_position.y, y)
			max_position.x = maxi(max_position.x, x)
			max_position.y = maxi(max_position.y, y)
	if max_position.x < min_position.x:
		return Rect2i()
	return Rect2i(min_position, max_position - min_position + Vector2i.ONE)

static func contains(image: Image, x: int, y: int) -> bool:
	return x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height() and image.get_pixel(x, y).a >= ALPHA_THRESHOLD
