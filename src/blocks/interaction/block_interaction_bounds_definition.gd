extends Resource
class_name BlockInteractionBoundsDefinition

@export_range(0, 16, 1) var horizontal_padding_pixels: int = 0
@export_range(0, 16, 1) var vertical_padding_pixels: int = 0

func validate(sprite_texture: Texture2D, source: String) -> bool:
	if sprite_texture == null:
		push_error("[BlockInteractionBoundsDefinition] Missing sprite texture at %s" % source)
		return false
	var image := sprite_texture.get_image()
	if image == null or image.is_empty():
		push_error("[BlockInteractionBoundsDefinition] Empty sprite texture at %s" % source)
		return false
	if OpaquePixelBounds.find(image).size == Vector2i.ZERO:
		push_error("[BlockInteractionBoundsDefinition] Sprite texture has no opaque pixels at %s" % source)
		return false
	return true

func resolve(sprite_texture: Texture2D) -> AABB:
	var uv_rect := resolve_uv_rect(sprite_texture)
	var minimum_y := 1.0 - uv_rect.end.y
	return AABB(Vector3(0.5 - uv_rect.size.x * 0.5, minimum_y, 0.5 - uv_rect.size.x * 0.5), Vector3(uv_rect.size.x, uv_rect.size.y, uv_rect.size.x))

func resolve_uv_rect(sprite_texture: Texture2D) -> Rect2:
	assert(sprite_texture != null)
	var image := sprite_texture.get_image()
	assert(image != null and not image.is_empty())
	var opaque_bounds := OpaquePixelBounds.find(image)
	assert(opaque_bounds.size != Vector2i.ZERO)
	var texture_size := Vector2(image.get_width(), image.get_height())
	var width := minf(1.0, float(opaque_bounds.size.x + horizontal_padding_pixels) / texture_size.x)
	var height := minf(1.0, float(opaque_bounds.size.y + vertical_padding_pixels) / texture_size.y)
	var opaque_center := Vector2(opaque_bounds.position) / texture_size + Vector2(opaque_bounds.size) / texture_size * 0.5
	var minimum := Vector2(
		clampf(opaque_center.x - width * 0.5, 0.0, 1.0 - width),
		clampf(opaque_center.y - height * 0.5, 0.0, 1.0 - height)
	)
	return Rect2(minimum, Vector2(width, height))
