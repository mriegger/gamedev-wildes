extends SceneTree

const VoxelPlayerVisibilitySensorType := preload("res://entities/awareness/voxel_player_visibility_sensor.gd")

const FLAT_HEIGHT: int = 6
const FEET_Y: float = FLAT_HEIGHT + 1.0
const DETECTION_RANGE: float = 10.0
const BODY_HEIGHT: float = 1.8

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[voxel_player_visibility_sensor] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-12, 13):
		for z in range(-12, 13):
			world.height_map_dict[Vector2i(x, z)] = FLAT_HEIGHT
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _test_phase_staggering() -> void:
	var world := _make_world()
	var observer := Vector3(0.5, FEET_Y, 0.5)
	var player := Vector3(4.5, FEET_Y, 0.5)
	var first := VoxelPlayerVisibilitySensorType.new(world, DETECTION_RANGE, BODY_HEIGHT, 1)
	var second := VoxelPlayerVisibilitySensorType.new(world, DETECTION_RANGE, BODY_HEIGHT, 2)
	var phase_delta := VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS / float(VoxelPlayerVisibilitySensorType.PHASE_COUNT)
	_expect(first.advance(phase_delta, observer, player), "first phase did not sample at its boundary")
	_expect(not second.advance(phase_delta, observer, player), "second phase sampled at the first phase boundary")
	_expect(second.advance(phase_delta, observer, player), "second phase did not sample at its boundary")

func _test_cached_occlusion_cadence() -> void:
	var world := _make_world()
	var observer := Vector3(0.5, FEET_Y, 0.5)
	var player := Vector3(4.5, FEET_Y, 0.5)
	var sensor := VoxelPlayerVisibilitySensorType.new(world, DETECTION_RANGE, BODY_HEIGHT, 0)
	_expect(sensor.advance(0.0, observer, player), "clear target was not visible on the initial sample")
	world.restore_block_edits({Vector3i(2, FLAT_HEIGHT + 2, 0): BlockId.Type.STONE}, {})
	var half_interval := VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS * 0.5
	_expect(sensor.advance(half_interval, observer, player), "cached visibility changed before the next sample")
	_expect(not sensor.advance(half_interval, observer, player), "occlusion was not observed at the next sample")

func _test_range_clears_cached_visibility() -> void:
	var world := _make_world()
	var observer := Vector3(0.5, FEET_Y, 0.5)
	var nearby_player := Vector3(4.5, FEET_Y, 0.5)
	var sensor := VoxelPlayerVisibilitySensorType.new(world, DETECTION_RANGE, BODY_HEIGHT, 0)
	_expect(sensor.advance(0.0, observer, nearby_player), "range fixture did not begin visible")
	var outside_player := observer + Vector3(DETECTION_RANGE + 0.001, 0.0, 0.0)
	_expect(not sensor.advance(0.0, observer, outside_player), "outside target retained cached visibility")
	_expect(not sensor.advance(0.0, observer, nearby_player), "cleared visibility returned before the next sample")
	_expect(sensor.advance(VoxelPlayerVisibilitySensorType.SAMPLE_INTERVAL_SECONDS, observer, nearby_player), "visibility did not return on the next sample")

func _run() -> void:
	_test_phase_staggering()
	_test_cached_occlusion_cadence()
	_test_range_clears_cached_visibility()
	if _failures == 0:
		print("VOXEL_PLAYER_VISIBILITY_SENSOR PASS")
		quit(0)
	else:
		print("VOXEL_PLAYER_VISIBILITY_SENSOR FAIL failures=%d" % _failures)
		quit(1)
