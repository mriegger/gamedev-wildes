extends SceneTree

const SAMPLE_MIN: int = -48
const SAMPLE_MAX: int = 48

var _errors: Array[String] = []
var _generator: FoliageGenerator
var _catalog: FoliageCatalog

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	_catalog = load("res://foliage/foliage_catalog.tres") as FoliageCatalog
	_expect(_catalog.validate(block_catalog), "foliage catalog invalid")
	_generator = FoliageGenerator.new(_catalog, 1337)
	_test_repeatability()
	_test_seed_variance()
	_test_density_bounds()
	_test_species_reachability()
	_test_order_independence()
	_test_patch_distribution()
	_test_biome_densities()
	if _errors.is_empty():
		print("FOLIAGE_GENERATOR PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_repeatability() -> void:
	for x in range(SAMPLE_MIN, SAMPLE_MAX):
		for z in range(SAMPLE_MIN, SAMPLE_MAX):
			var first := _generator.select_block_id(x, z, 0.45)
			var second := _generator.select_block_id(x, z, 0.45)
			_expect(first == second, "selection changed at %d,%d" % [x, z])

func _test_seed_variance() -> void:
	var changed := 0
	var sample_count := 0
	var other_generator := FoliageGenerator.new(_catalog, 7331)
	for x in range(SAMPLE_MIN, SAMPLE_MAX):
		for z in range(SAMPLE_MIN, SAMPLE_MAX):
			var first := _generator.select_block_id(x, z, 1.0)
			var second := other_generator.select_block_id(x, z, 1.0)
			changed += int(first != second)
			sample_count += 1
	_expect(changed > sample_count / 2, "different seeds changed only %d of %d selections" % [changed, sample_count])

func _test_density_bounds() -> void:
	var low_count := 0
	var middle_count := 0
	var high_count := 0
	var sample_count := 0
	for x in range(SAMPLE_MIN, SAMPLE_MAX):
		for z in range(SAMPLE_MIN, SAMPLE_MAX):
			var empty := _generator.select_block_id(x, z, 0.0)
			var low := _generator.select_block_id(x, z, 0.2)
			var middle := _generator.select_block_id(x, z, 0.45)
			var high := _generator.select_block_id(x, z, 1.0)
			_expect(empty == BlockId.Type.AIR, "zero density selected foliage at %d,%d" % [x, z])
			_expect(high != BlockId.Type.AIR, "full density selected air at %d,%d" % [x, z])
			if low != BlockId.Type.AIR:
				_expect(middle == low and high == low, "density changed species at %d,%d" % [x, z])
			low_count += int(low != BlockId.Type.AIR)
			middle_count += int(middle != BlockId.Type.AIR)
			high_count += int(high != BlockId.Type.AIR)
			sample_count += 1
	_expect(low_count < middle_count and middle_count < high_count, "density did not increase occupancy")
	var middle_ratio := float(middle_count) / float(sample_count)
	_expect(middle_ratio >= 0.42 and middle_ratio <= 0.48, "0.45 density produced %.3f occupancy" % middle_ratio)

func _test_species_reachability() -> void:
	var reached: Dictionary = {}
	var generator := FoliageGenerator.new(_catalog, 8675309)
	for x in range(SAMPLE_MIN, SAMPLE_MAX):
		for z in range(SAMPLE_MIN, SAMPLE_MAX):
			reached[generator.select_block_id(x, z, 1.0)] = true
	for definition in _catalog.species:
		_expect(reached.has(definition.block.id), "%s was unreachable" % BlockId.get_display_name(definition.block.id))

func _test_order_independence() -> void:
	var coordinates: Array[Vector2i] = []
	for x in range(-24, 24):
		for z in range(-24, 24):
			coordinates.append(Vector2i(x, z))
	var generator := FoliageGenerator.new(_catalog, 424242)
	var forward: Dictionary = {}
	for coordinate in coordinates:
		forward[coordinate] = generator.select_block_id(coordinate.x, coordinate.y, 0.55)
	coordinates.reverse()
	var reverse: Dictionary = {}
	for coordinate in coordinates:
		reverse[coordinate] = generator.select_block_id(coordinate.x, coordinate.y, 0.55)
	_expect(forward == reverse, "selection depended on traversal order")

func _test_patch_distribution() -> void:
	var sparsest := FoliageGenerator.PATCH_SIZE * FoliageGenerator.PATCH_SIZE
	var densest := 0
	for patch_x in range(-12, 12):
		for patch_z in range(-12, 12):
			var count := 0
			var origin_x := patch_x * FoliageGenerator.PATCH_SIZE
			var origin_z := patch_z * FoliageGenerator.PATCH_SIZE
			for x_offset in range(FoliageGenerator.PATCH_SIZE):
				for z_offset in range(FoliageGenerator.PATCH_SIZE):
					var block_id := _generator.select_block_id(origin_x + x_offset, origin_z + z_offset, 0.28)
					count += int(block_id != BlockId.Type.AIR)
			sparsest = mini(sparsest, count)
			densest = maxi(densest, count)
	_expect(sparsest <= 8, "foliage patches never opened natural clearings")
	_expect(densest >= 24, "foliage patches never formed dense clusters")

func _test_biome_densities() -> void:
	var library := load("res://world/generation/biome_library.tres") as BiomeLibrary
	_expect(library.validate(), "biome foliage densities invalid")
	var densities: Dictionary = {}
	for biome in library.biomes:
		densities[biome.biome_id] = biome.foliage_density
	_expect(is_zero_approx(densities.get("desert", -1.0)), "desert generated foliage")
	_expect(float(densities.get("wetland", 0.0)) > float(densities.get("plains", 0.0)), "wetland was not denser than plains")
	_expect(float(densities.get("plains", 0.0)) > float(densities.get("highland", 0.0)), "plains were not denser than highland")
	_expect(float(densities.get("highland", 0.0)) > float(densities.get("mountains", 0.0)), "highland was not denser than mountains")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
