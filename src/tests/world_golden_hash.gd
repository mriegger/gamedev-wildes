extends SceneTree

const GOLDEN_PATH: String = "res://tests/golden_world_hash.json"
const SEED: int = 1337
const REGION_X0: int = -32
const REGION_X1: int = 32
const REGION_Z0: int = -32
const REGION_Z1: int = 32
const REGION_Y0: int = 0
const REGION_Y1: int = 128

func _init():
	var args: Array = OS.get_cmdline_user_args()
	var do_update: bool = false
	for a in args:
		if a == "--update" or a == "--write" or a == "--generate":
			do_update = true
	var expected: String = ""
	var expected_region: Dictionary = {}
	if FileAccess.file_exists(GOLDEN_PATH):
		var f = FileAccess.open(GOLDEN_PATH, FileAccess.READ)
		if f != null:
			var txt = f.get_as_text()
			f.close()
			var parsed = JSON.parse_string(txt)
			if parsed is Dictionary:
				expected = str(parsed.get("digest", ""))
				expected_region = parsed.get("region", {}) as Dictionary
				var seed_in_file = int(parsed.get("seed", SEED))
				if seed_in_file != SEED:
					print("WARN golden file seed %d != expected %d" % [seed_in_file, SEED])
	if do_update:
		var digest = _compute_hash()
		var out = {
			"seed": SEED,
			"region": {"x0": REGION_X0, "x1": REGION_X1, "z0": REGION_Z0, "z1": REGION_Z1, "y0": REGION_Y0, "y1": REGION_Y1},
			"digest": digest,
			"description": "SHA256 over block IDs (voxel_world.get_block_id_at) for fixed region, seed 1337 with jittered WorldConfig. Any noise/spline/biome/lake/river change that reshapes existing worlds must update this digest.",
			"generated_by": "src/tests/world_golden_hash.gd --update"
		}
		var json_str = JSON.stringify(out, "\t")
		var out_path = GOLDEN_PATH.replace("res://", "src/")
		var wf = FileAccess.open(out_path, FileAccess.WRITE)
		if wf == null:
			wf = FileAccess.open("src/tests/golden_world_hash.json", FileAccess.WRITE)
		if wf != null:
			wf.store_string(json_str + "\n")
			wf.close()
			print("wrote golden hash %s to %s" % [digest, out_path])
			var wf2 = FileAccess.open("tests/golden_world_hash.json", FileAccess.WRITE)
			if wf2 != null:
				wf2.store_string(json_str + "\n")
				wf2.close()
		quit(0)
		return
	if expected == "":
		print("FAIL no expected digest found at %s" % GOLDEN_PATH)
		quit(1)
		return
	var actual = _compute_hash()
	if actual == expected:
		print("GOLDEN PASS seed=%d region x[%d,%d) z[%d,%d) y[%d,%d) digest=%s" % [SEED, REGION_X0, REGION_X1, REGION_Z0, REGION_Z1, REGION_Y0, REGION_Y1, actual])
		quit(0)
	else:
		print("GOLDEN FAIL seed=%d region x[%d,%d) z[%d,%d) y[%d,%d)" % [SEED, REGION_X0, REGION_X1, REGION_Z0, REGION_Z1, REGION_Y0, REGION_Y1])
		print(" expected=%s" % expected)
		print("   actual=%s" % actual)
		print("If this is an intentional worldgen change, regenerate with: godot --path src --headless --script res://tests/world_golden_hash.gd -- --update")
		quit(1)

func _compute_hash() -> String:
	var config = _load_config()
	var gen = TerrainGenerator.new(config)
	gen.setup_noises()
	var voxel = VoxelWorld.new(config.chunk_size, config.max_build_y)
	voxel.setup_infinite(config.chunk_size, config.max_build_y)
	voxel.water_level = config.water_level
	voxel.set_generator_ref(gen)
	var needed_x0 = REGION_X0
	var needed_z0 = REGION_Z0
	var needed_sx = REGION_X1 - REGION_X0
	var needed_sz = REGION_Z1 - REGION_Z0
	for cx in range(int(floor(float(needed_x0) / config.chunk_size)) - 1, int(ceil(float(needed_x0 + needed_sx) / config.chunk_size)) + 1):
		for cz in range(int(floor(float(needed_z0) / config.chunk_size)) - 1, int(ceil(float(needed_z0 + needed_sz) / config.chunk_size)) + 1):
			var origin_x = cx * config.chunk_size
			var origin_z = cz * config.chunk_size
			var payload = gen.build_cache_with_generation(origin_x, origin_z, config.chunk_size, config.max_build_y, {}, {}, {}, false)
			voxel.apply_chunk_gen(payload)
			voxel.apply_tree_chunk(payload)
			voxel.apply_chunk_gen_for_coord(Vector2i(cx, cz), payload)
			voxel.apply_tree_chunk_for_coord(Vector2i(cx, cz), payload)
	for x in range(REGION_X0, REGION_X1):
		for z in range(REGION_Z0, REGION_Z1):
			voxel.ensure_column_generated(x, z)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for y in range(REGION_Y0, REGION_Y1):
		for x in range(REGION_X0, REGION_X1):
			for z in range(REGION_Z0, REGION_Z1):
				var id = voxel.get_block_id_at(Vector3i(x, y, z))
				ctx.update(PackedByteArray([id & 0xFF]))
	var digest = ctx.finish()
	return digest.hex_encode()

func _load_config() -> WorldConfig:
	var p = "res://world/generation/world_config.tres"
	var cfg: WorldConfig = null
	if ResourceLoader.exists(p):
		cfg = load(p) as WorldConfig
		if cfg != null:
			cfg = cfg.duplicate() as WorldConfig
	if cfg == null:
		cfg = WorldConfig.new()
	cfg.seed_value = SEED
	var jitter_rng = RandomNumberGenerator.new()
	jitter_rng.seed = cfg.seed_value
	cfg.base_height = 8.5 + jitter_rng.randf_range(-0.8, 1.5)
	cfg.meadow_radius = 22.0 + jitter_rng.randf_range(-2.0, 6.0)
	cfg.tree_density = 0.01 + jitter_rng.randf_range(-0.003, 0.008)
	cfg.continentalness_frequency = clamp(0.0018 + jitter_rng.randf_range(-0.0004, 0.0006), 0.0005, 0.01)
	cfg.erosion_frequency = clamp(0.0045 + jitter_rng.randf_range(-0.001, 0.0015), 0.001, 0.015)
	cfg.peaks_valleys_frequency = clamp(0.018 + jitter_rng.randf_range(-0.003, 0.004), 0.005, 0.04)
	return cfg
