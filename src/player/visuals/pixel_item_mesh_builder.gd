extends RefCounted
class_name PixelItemMeshBuilder

static func build(texture: Texture2D, grip_pixel: Vector2i, max_dimension: float, depth_pixels: float) -> ArrayMesh:
	assert(texture != null)
	assert(depth_pixels > 0.0)
	var image := texture.get_image()
	assert(image != null and not image.is_empty())
	assert(image.get_width() == image.get_height())
	var bounds := _get_opaque_bounds(image)
	assert(bounds.size != Vector2i.ZERO)
	var pixel_scale := max_dimension / float(max(bounds.size.x, bounds.size.y))
	var depth := pixel_scale * depth_pixels
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not _is_opaque(image, x, y):
				continue
			_add_pixel(surface, image, Vector2i(x, y), grip_pixel, pixel_scale, depth)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = 0.82
	surface.set_material(material)
	return surface.commit() as ArrayMesh

static func _get_opaque_bounds(image: Image) -> Rect2i:
	var min_pos := Vector2i(image.get_width(), image.get_height())
	var max_pos := Vector2i(-1, -1)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if _is_opaque(image, x, y):
				min_pos.x = min(min_pos.x, x)
				min_pos.y = min(min_pos.y, y)
				max_pos.x = max(max_pos.x, x)
				max_pos.y = max(max_pos.y, y)
	if max_pos.x < min_pos.x:
		return Rect2i()
	return Rect2i(min_pos, max_pos - min_pos + Vector2i.ONE)

static func _is_opaque(image: Image, x: int, y: int) -> bool:
	return x >= 0 and x < image.get_width() and y >= 0 and y < image.get_height() and image.get_pixel(x, y).a >= 0.5

static func _add_pixel(surface: SurfaceTool, image: Image, pixel: Vector2i, grip: Vector2i, scale: float, depth: float):
	var left := (float(pixel.x - grip.x) - 0.5) * scale
	var right := left + scale
	var top := (float(grip.y - pixel.y) + 0.5) * scale
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
	if not _is_opaque(image, pixel.x - 1, pixel.y):
		_add_solid_quad(surface, Vector3(left, bottom, back), Vector3(left, bottom, front), Vector3(left, top, front), Vector3(left, top, back), Vector3.LEFT, center_uv)
	if not _is_opaque(image, pixel.x + 1, pixel.y):
		_add_solid_quad(surface, Vector3(right, bottom, front), Vector3(right, bottom, back), Vector3(right, top, back), Vector3(right, top, front), Vector3.RIGHT, center_uv)
	if not _is_opaque(image, pixel.x, pixel.y - 1):
		_add_solid_quad(surface, Vector3(left, top, front), Vector3(right, top, front), Vector3(right, top, back), Vector3(left, top, back), Vector3.UP, center_uv)
	if not _is_opaque(image, pixel.x, pixel.y + 1):
		_add_solid_quad(surface, Vector3(left, bottom, back), Vector3(right, bottom, back), Vector3(right, bottom, front), Vector3(left, bottom, front), Vector3.DOWN, center_uv)

static func _add_solid_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv: Vector2):
	_add_quad(surface, a, b, c, d, normal, uv, uv, uv, uv)

static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, uv_a: Vector2, uv_b: Vector2, uv_c: Vector2, uv_d: Vector2):
	_add_vertex(surface, a, normal, uv_a)
	_add_vertex(surface, b, normal, uv_b)
	_add_vertex(surface, c, normal, uv_c)
	_add_vertex(surface, a, normal, uv_a)
	_add_vertex(surface, c, normal, uv_c)
	_add_vertex(surface, d, normal, uv_d)

static func _add_vertex(surface: SurfaceTool, position: Vector3, normal: Vector3, uv: Vector2):
	surface.set_normal(normal)
	surface.set_uv(uv)
	surface.add_vertex(position)
