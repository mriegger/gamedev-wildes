extends RefCounted
class_name PixelItemMeshBuilder

const MAX_CENTERED_SOURCE_DIMENSION: int = 32

static func build(texture: Texture2D, grip_pixel: Vector2i, max_dimension: float, depth_pixels: float) -> ArrayMesh:
	assert(texture != null)
	assert(max_dimension > 0.0)
	assert(depth_pixels > 0.0)
	var image := texture.get_image()
	assert(image != null and not image.is_empty())
	assert(image.get_width() == image.get_height())
	return _build(texture, image, Vector2(grip_pixel), max_dimension, depth_pixels, false)

static func build_centered(texture: Texture2D, max_dimension: float, depth_pixels: float) -> ArrayMesh:
	assert(texture != null)
	assert(max_dimension > 0.0)
	assert(depth_pixels > 0.0)
	var image := _bounded_image(texture.get_image())
	var bounds := OpaquePixelBounds.find(image)
	assert(bounds.size != Vector2i.ZERO)
	var center := Vector2(bounds.position) + (Vector2(bounds.size) - Vector2.ONE) * 0.5
	return _build(texture, image, center, max_dimension, depth_pixels, true)

static func _bounded_image(source: Image) -> Image:
	assert(source != null and not source.is_empty())
	var source_max_dimension := maxi(source.get_width(), source.get_height())
	if source_max_dimension <= MAX_CENTERED_SOURCE_DIMENSION:
		return source
	var scale := float(MAX_CENTERED_SOURCE_DIMENSION) / float(source_max_dimension)
	var image := source.duplicate()
	image.resize(
		maxi(1, roundi(float(source.get_width()) * scale)),
		maxi(1, roundi(float(source.get_height()) * scale)),
		Image.INTERPOLATE_NEAREST,
	)
	return image

static func _build(
	texture: Texture2D,
	image: Image,
	anchor_pixel: Vector2,
	max_dimension: float,
	depth_pixels: float,
	use_alpha_scissor: bool,
) -> ArrayMesh:
	var bounds := OpaquePixelBounds.find(image)
	assert(bounds.size != Vector2i.ZERO)
	var pixel_scale := max_dimension / float(max(bounds.size.x, bounds.size.y))
	var depth := pixel_scale * depth_pixels
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			if not OpaquePixelBounds.contains(image, x, y):
				continue
			_add_pixel(surface, image, Vector2i(x, y), anchor_pixel, pixel_scale, depth)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.roughness = 0.82
	if use_alpha_scissor:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = OpaquePixelBounds.ALPHA_THRESHOLD
	surface.set_material(material)
	return surface.commit() as ArrayMesh

static func _add_pixel(surface: SurfaceTool, image: Image, pixel: Vector2i, anchor: Vector2, scale: float, depth: float):
	var left := (float(pixel.x) - anchor.x - 0.5) * scale
	var right := left + scale
	var top := (anchor.y - float(pixel.y) + 0.5) * scale
	var bottom := top - scale
	var front := depth * 0.5
	var back := -front
	var uv_left := float(pixel.x) / float(image.get_width())
	var uv_right := float(pixel.x + 1) / float(image.get_width())
	var uv_top := float(pixel.y) / float(image.get_height())
	var uv_bottom := float(pixel.y + 1) / float(image.get_height())
	var center_uv := Vector2((uv_left + uv_right) * 0.5, (uv_top + uv_bottom) * 0.5)
	_add_quad(surface,
		Vector3(left, bottom, front), Vector3(right, bottom, front), Vector3(right, top, front), Vector3(left, top, front),
		Vector3.BACK,
		Vector2(uv_left, uv_bottom), Vector2(uv_right, uv_bottom), Vector2(uv_right, uv_top), Vector2(uv_left, uv_top))
	_add_quad(surface,
		Vector3(right, bottom, back), Vector3(left, bottom, back), Vector3(left, top, back), Vector3(right, top, back),
		Vector3.FORWARD,
		Vector2(uv_right, uv_bottom), Vector2(uv_left, uv_bottom), Vector2(uv_left, uv_top), Vector2(uv_right, uv_top))
	if not OpaquePixelBounds.contains(image, pixel.x - 1, pixel.y):
		_add_solid_quad(surface, Vector3(left, bottom, back), Vector3(left, bottom, front), Vector3(left, top, front), Vector3(left, top, back), Vector3.LEFT, center_uv)
	if not OpaquePixelBounds.contains(image, pixel.x + 1, pixel.y):
		_add_solid_quad(surface, Vector3(right, bottom, front), Vector3(right, bottom, back), Vector3(right, top, back), Vector3(right, top, front), Vector3.RIGHT, center_uv)
	if not OpaquePixelBounds.contains(image, pixel.x, pixel.y - 1):
		_add_solid_quad(surface, Vector3(left, top, front), Vector3(right, top, front), Vector3(right, top, back), Vector3(left, top, back), Vector3.UP, center_uv)
	if not OpaquePixelBounds.contains(image, pixel.x, pixel.y + 1):
		_add_solid_quad(surface, Vector3(left, bottom, back), Vector3(right, bottom, back), Vector3(right, bottom, front), Vector3(left, bottom, front), Vector3.DOWN, center_uv)

static func _add_solid_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv: Vector2):
	_add_quad(surface, a, b, c, d, normal, uv, uv, uv, uv)

static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2):
	_add_vertex(surface, a, normal, uv_a)
	_add_vertex(surface, c, normal, uv_c)
	_add_vertex(surface, b, normal, uv_b)
	_add_vertex(surface, a, normal, uv_a)
	_add_vertex(surface, d, normal, uv_d)
	_add_vertex(surface, c, normal, uv_c)

static func _add_vertex(surface: SurfaceTool, position: Vector3, normal: Vector3, uv: Vector2):
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.add_vertex(position)
