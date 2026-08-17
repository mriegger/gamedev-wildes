extends SceneTree

var _failures: Array[String] = []

func _init() -> void:
	_test_cell_contract()
	_test_size_and_id_contracts()
	_test_valid_definition()
	_test_malformed_definitions()
	if _failures.is_empty():
		print("STRUCTURE_DEFINITION PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)

func _test_cell_contract() -> void:
	_expect(StructureCell.VOID == -1 and StructureCell.AIR == 0, "stable structure cell encodings changed")
	_expect(StructureCell.is_valid(StructureCell.VOID), "level module VOID was rejected")
	_expect(not StructureCell.is_generic_valid(StructureCell.VOID), "generic structure accepted VOID")
	_expect(StructureCell.is_generic_valid(BlockId.Type.STONE), "generic structure rejected a cube block")
	_expect(not StructureCell.is_generic_valid(BlockId.Type.TORCH), "generic dense cells accepted a torch")
	_expect(not StructureCell.is_generic_valid(BlockId.Type.WATER), "generic dense cells accepted water")
	var size := Vector3i(3, 2, 4)
	var seen: Dictionary = {}
	for y in size.y:
		for z in size.z:
			for x in size.x:
				var cell := Vector3i(x, y, z)
				var index := StructureCell.index_of(cell, size)
				_expect(index >= 0 and index < size.x * size.y * size.z, "dense index escaped bounds")
				_expect(not seen.has(index), "dense index collapsed two cells")
				seen[index] = true
	_expect(seen.size() == size.x * size.y * size.z, "dense index did not cover every cell")

func _test_size_and_id_contracts() -> void:
	_expect(StructureDefinition.is_valid_size(Vector3i(64, 64, 64)), "maximum generic size was rejected")
	_expect(not StructureDefinition.is_valid_size(Vector3i(65, 1, 1)), "oversized generic axis was accepted")
	_expect(not StructureDefinition.is_valid_size(Vector3i(0, 1, 1)), "zero generic axis was accepted")
	for valid_id in [&"stone_arch", &"a", &"room2_west"]:
		_expect(StructureDefinition.is_valid_id(valid_id), "valid ID was rejected: %s" % valid_id)
	for invalid_id in [&"", &"StoneArch", &"2stone", &"stone__arch", &"stone-arch", &"../stone"]:
		_expect(not StructureDefinition.is_valid_id(invalid_id), "invalid ID was accepted: %s" % invalid_id)

func _test_valid_definition() -> void:
	var definition := _make_valid_definition()
	_expect(definition.validate(), "valid generic definition was rejected")
	_expect(definition.format_version == 1, "generic format version changed")
	_expect(definition.cell_at(Vector3i.ZERO) == BlockId.Type.STONE, "generic dense lookup changed")
	_expect(definition.torches.size() == 1 and definition.torches[0].support_direction == Vector3i.LEFT, "generic torch contract changed")

func _test_malformed_definitions() -> void:
	var output: Array = []
	var exit_code := OS.execute(
		OS.get_executable_path(),
		["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://structures/tests/structure_definition_malformed_probe.gd"],
		output,
		true,
	)
	var text := "\n".join(PackedStringArray(output))
	_expect(exit_code == 0, "malformed definition probe exited %d" % exit_code)
	_expect(text.contains("STRUCTURE_DEFINITION_MALFORMED PASS"), "malformed definition probe did not reject every invalid resource")

func _make_valid_definition() -> StructureDefinition:
	var definition := StructureDefinition.new()
	definition.format_version = StructureDefinition.CURRENT_FORMAT_VERSION
	definition.structure_id = &"test_structure"
	definition.size = Vector3i(2, 2, 2)
	definition.cells.resize(8)
	definition.cells.fill(StructureCell.AIR)
	definition.cells[StructureCell.index_of(Vector3i.ZERO, definition.size)] = BlockId.Type.STONE
	var torch := StructureTorchDefinition.new()
	torch.cell = Vector3i(1, 0, 0)
	torch.support_direction = Vector3i.LEFT
	definition.torches.append(torch)
	return definition

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
