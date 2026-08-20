extends SceneTree

var _errors: Array[String] = []

func _init() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var foliage_catalog := load("res://foliage/foliage_catalog.tres") as FoliageCatalog
	_expect(block_catalog.validate(), "block catalog invalid")
	_expect(foliage_catalog.validate(block_catalog), "foliage catalog invalid")
	var expected: Dictionary = {
		BlockId.Type.SHORT_GRASS: [105, "Short Grass", "short_grass.png", 57],
		BlockId.Type.GRASS_FOLIAGE: [106, "Grass", "grass.png", 35],
		BlockId.Type.BLUE_WILDFLOWER: [107, "Blue Wildflower", "blue_wildflower.png", 2],
		BlockId.Type.ORANGE_TULIP: [108, "Orange Tulip", "orange_tulip.png", 2],
		BlockId.Type.PINK_HEARTFLOWER: [109, "Pink Heartflower", "pink_heartflower.png", 2],
		BlockId.Type.RED_FLOWER: [110, "Red Flower", "red_flower.png", 2],
	}
	_expect(BlockId.Type.COUNT == 111, "block ID count changed")
	_expect(foliage_catalog.species.size() == expected.size(), "foliage species count mismatch")
	_expect(foliage_catalog.get_total_generation_weight() == 100, "foliage generation weights do not total 100")
	for block_id in expected:
		var values := expected[block_id] as Array
		var stable_id := values[0] as int
		var display_name := values[1] as String
		var texture_name := values[2] as String
		var generation_weight := values[3] as int
		var block := block_catalog.get_definition(block_id)
		var definition := foliage_catalog.get_species(block_id)
		_expect(block_id == stable_id, "stable ID changed for %s" % display_name)
		_expect(BlockId.get_display_name(block_id) == display_name, "display name mismatch for %s" % block_id)
		_expect(BlockId.is_foliage(block_id), "%s is not classified as foliage" % display_name)
		_expect(not BlockId.is_chunk_cube(block_id), "%s is classified as a cube" % display_name)
		_expect(not BlockId.occludes_chunk_face(block_id), "%s occludes chunk faces" % display_name)
		_expect(not BlockId.is_ao_solid(block_id), "%s contributes ambient occlusion" % display_name)
		_expect(not block.is_solid and not block.is_opaque, "%s blocks movement or light" % display_name)
		_expect(block.is_raycast_solid and block.is_breakable and block.is_replaceable, "%s interaction properties invalid" % display_name)
		_expect(definition.block == block, "%s does not reference its canonical block" % display_name)
		_expect(block.sprite_texture.resource_path == "res://assets/textures/foliage/%s" % texture_name, "%s texture mismatch" % display_name)
		_expect(block.sprite_texture.get_size() == Vector2(16, 16), "%s texture dimensions invalid" % display_name)
		var opaque_bounds := OpaquePixelBounds.find(block.sprite_texture.get_image())
		var uv_rect := block.interaction_bounds.resolve_uv_rect(block.sprite_texture)
		var expected_width := minf(1.0, float(opaque_bounds.size.x + 1) / 16.0)
		var expected_height := minf(1.0, float(opaque_bounds.size.y + 1) / 16.0)
		_expect(block.interaction_bounds != null, "%s interaction bounds are missing" % display_name)
		_expect(block.interaction_bounds.horizontal_padding_pixels == 1 and block.interaction_bounds.vertical_padding_pixels == 1, "%s interaction padding is not one pixel" % display_name)
		_expect(is_equal_approx(uv_rect.size.x, expected_width), "%s UV width does not match its opaque pixels" % display_name)
		_expect(is_equal_approx(uv_rect.size.y, expected_height), "%s UV height does not match its opaque pixels" % display_name)
		_expect(uv_rect.position.x >= 0.0 and uv_rect.end.x <= 1.0, "%s UV bounds escaped the texture width" % display_name)
		_expect(uv_rect.position.y >= 0.0 and uv_rect.end.y <= 1.0, "%s UV bounds escaped the texture height" % display_name)
		_expect(definition.generation_weight == generation_weight, "%s generation weight mismatch" % display_name)
	var classified_count := 0
	for block_id in BlockId.DISPLAY_NAMES:
		if BlockId.is_foliage(block_id):
			classified_count += 1
	_expect(classified_count == expected.size(), "foliage classification contains unexpected IDs")
	if _errors.is_empty():
		print("FOLIAGE_CONTENT PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
