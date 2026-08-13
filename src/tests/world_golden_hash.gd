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
	var encoding_probe := _encode_block_ids(PackedInt32Array([1, 257]))
	if encoding_probe.hex_encode() != "0100000001010000":
		print("FAIL block ID encoding is not 32-bit little-endian")
		quit(1)
		return
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
			"description": "SHA256 over deterministic base-terrain and tree block IDs (voxel_world.get_block_id_at) for fixed region, seed 1337 with jittered WorldConfig. Seeded post-terrain copper deposits are covered separately and intentionally excluded. Any noise/spline/biome/lake/river change that reshapes existing worlds must update this digest.",
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
	var block_catalog = load("res://blocks/block_catalog.tres") as BlockCatalog
	var gen = TerrainGenerator.new(config)
	gen.setup_noises()
	var voxel = VoxelWorld.new(config.chunk_size, config.max_build_y, config.water_level, config.meadow_radius, block_catalog)
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
	for x in range(REGION_X0, REGION_X1):
		for z in range(REGION_Z0, REGION_Z1):
			voxel.ensure_column_generated(x, z)
	var ctx = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var block_ids := PackedInt32Array()
	block_ids.resize((REGION_Y1 - REGION_Y0) * (REGION_X1 - REGION_X0) * (REGION_Z1 - REGION_Z0))
	var block_index := 0
	for y in range(REGION_Y0, REGION_Y1):
		for x in range(REGION_X0, REGION_X1):
			for z in range(REGION_Z0, REGION_Z1):
				block_ids[block_index] = voxel.get_block_id_at(Vector3i(x, y, z))
				block_index += 1
	ctx.update(_encode_block_ids(block_ids))
	var digest = ctx.finish()
	return digest.hex_encode()

func _encode_block_ids(block_ids: PackedInt32Array) -> PackedByteArray:
	var encoded := block_ids.to_byte_array()
	var native_one := PackedInt32Array([1]).to_byte_array()
	if native_one[0] == 1:
		return encoded
	for offset in range(0, encoded.size(), 4):
		var first := encoded[offset]
		var second := encoded[offset + 1]
		encoded[offset] = encoded[offset + 3]
		encoded[offset + 1] = encoded[offset + 2]
		encoded[offset + 2] = second
		encoded[offset + 3] = first
	return encoded

func _load_config() -> WorldConfig:
	var config = load("res://world/settings/world_config.tres") as WorldConfig
	return config.runtime_copy_for_seed(SEED)
