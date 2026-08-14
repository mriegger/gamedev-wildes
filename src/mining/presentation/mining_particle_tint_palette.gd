extends RefCounted
class_name MiningParticleTintPalette

var _tints_by_block_id: Dictionary = {}

func _init(block_catalog: BlockCatalog):
	for definition in block_catalog.definitions:
		if BlockId.is_chunk_cube(definition.id):
			_tints_by_block_id[definition.id] = _average_texture_color(definition.bottom_texture)

func get_tint(block_id: int) -> Color:
	assert(_tints_by_block_id.has(block_id))
	return _tints_by_block_id[block_id]

func _average_texture_color(texture: Texture2D) -> Color:
	var image := texture.get_image()
	var rgb_sum := Vector3.ZERO
	var weight: float = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			rgb_sum += Vector3(pixel.r, pixel.g, pixel.b) * pixel.a
			weight += pixel.a
	assert(weight > 0.0)
	return Color(rgb_sum.x / weight, rgb_sum.y / weight, rgb_sum.z / weight, 1.0)
