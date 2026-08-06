extends RefCounted
class_name BlockTextureSet

var texture_array: Texture2DArray
var top_layers := PackedInt32Array()
var side_layers := PackedInt32Array()
var bottom_layers := PackedInt32Array()

var _sources: Array[Texture2D] = []
var _layers_by_path: Dictionary = {}

func _init(block_catalog: BlockCatalog) -> void:
	var catalog_valid := block_catalog.validate()
	assert(catalog_valid)
	top_layers.resize(BlockId.Type.COUNT)
	side_layers.resize(BlockId.Type.COUNT)
	bottom_layers.resize(BlockId.Type.COUNT)
	top_layers.fill(-1)
	side_layers.fill(-1)
	bottom_layers.fill(-1)
	for block_id in range(BlockId.Type.COUNT):
		if not BlockId.is_chunk_cube(block_id):
			continue
		var definition := block_catalog.get_definition(block_id)
		top_layers[block_id] = _get_or_add_layer(definition.top_texture)
		side_layers[block_id] = _get_or_add_layer(definition.side_texture)
		bottom_layers[block_id] = _get_or_add_layer(definition.bottom_texture)
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
