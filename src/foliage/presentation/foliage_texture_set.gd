extends RefCounted
class_name FoliageTextureSet

var texture_array: Texture2DArray
var texture_layers := PackedInt32Array()
var texture_uv_rects: Array[Rect2] = []

var _sources: Array[Texture2D] = []
var _layers_by_path: Dictionary = {}

func _init(catalog: FoliageCatalog) -> void:
	assert(catalog != null)
	texture_layers.resize(BlockId.Type.COUNT)
	texture_layers.fill(-1)
	texture_uv_rects.resize(BlockId.Type.COUNT)
	texture_uv_rects.fill(Rect2(Vector2.ZERO, Vector2.ONE))
	for definition in catalog.species:
		assert(definition != null)
		var block_id := int(definition.block.id)
		assert(BlockId.is_foliage(block_id))
		texture_layers[block_id] = _get_or_add_layer(definition.block.sprite_texture)
		texture_uv_rects[block_id] = definition.block.interaction_bounds.resolve_uv_rect(definition.block.sprite_texture)
	var images: Array[Image] = []
	for source in _sources:
		var image := source.get_image()
		assert(image != null)
		if image.is_compressed():
			var decompress_error := image.decompress()
			assert(decompress_error == OK)
		assert(image.get_width() == 16 and image.get_height() == 16)
		image.convert(Image.FORMAT_RGBA8)
		if not image.has_mipmaps():
			var mipmap_error := image.generate_mipmaps()
			assert(mipmap_error == OK)
		images.append(image)
	texture_array = Texture2DArray.new()
	var texture_array_error := texture_array.create_from_images(images)
	assert(texture_array_error == OK)
	_sources.clear()
	_layers_by_path.clear()

func _get_or_add_layer(texture: Texture2D) -> int:
	assert(texture != null)
	var path := texture.resource_path
	assert(not path.is_empty())
	if _layers_by_path.has(path):
		return int(_layers_by_path[path])
	var layer := _sources.size()
	_sources.append(texture)
	_layers_by_path[path] = layer
	return layer
