extends SceneTree

const WatcherTeleportSearchType := preload("res://entities/watcher/watcher_teleport_search.gd")
const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")
const VoxelLineOfSightType := preload("res://combat/voxel_line_of_sight.gd")

const FEET_Y: float = 1.0
const PLAYER_POSITION := Vector3(0.5, FEET_Y, 0.5)
const PREVIOUS_POSITION := Vector3(3.5, FEET_Y, 0.5)

class TestVoxelSpace:
	extends VoxelSpace

	var raycast_solids: Dictionary = {}

	func get_highest_top(_x: int, _z: int) -> float:
		return FEET_Y

	func is_solid(position: Vector3i) -> bool:
		return position.y == int(FEET_Y) - 1

	func is_raycast_solid(position: Vector3i) -> bool:
		return position.y == int(FEET_Y) - 1 or raycast_solids.has(position)

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	_test_seeded_order_is_deterministic()
	_test_candidates_are_centered_grounded_and_opposite()
	_test_ready_filter_rejects_candidates()
	_test_clear_candidates_precede_occluded_fallbacks()
	if _failures == 0:
		print("WATCHER_TELEPORT_SEARCH PASS")
		quit(0)
	else:
		print("WATCHER_TELEPORT_SEARCH FAIL failures=%d" % _failures)
		quit(1)

func _test_seeded_order_is_deterministic() -> void:
	var space := TestVoxelSpace.new()
	var first := _find_candidates(space, 77231, 1, _always_ready)
	var repeated := _find_candidates(space, 77231, 1, _always_ready)
	var next_sequence := _find_candidates(space, 77231, 2, _always_ready)
	_expect(not first.is_empty(), "flat terrain produced no teleport candidates")
	_expect(first == repeated, "identical seed and sequence changed teleport order")
	_expect(first != next_sequence, "next teleport sequence reused the complete candidate order")

func _test_candidates_are_centered_grounded_and_opposite() -> void:
	var definition := _make_definition()
	var player_bounds := _player_bounds()
	var previous_bearing := Vector2(
		PREVIOUS_POSITION.x - PLAYER_POSITION.x,
		PREVIOUS_POSITION.z - PLAYER_POSITION.z,
	).normalized()
	var candidates := _find_candidates(TestVoxelSpace.new(), 991, 3, _always_ready)
	for candidate in candidates:
		_expect(is_equal_approx(candidate.x - floorf(candidate.x), 0.5), "candidate x was not cell-centered")
		_expect(is_equal_approx(candidate.z - floorf(candidate.z), 0.5), "candidate z was not cell-centered")
		_expect(is_equal_approx(candidate.y, roundf(candidate.y)), "candidate y was not integral")
		_expect(is_equal_approx(candidate.y, FEET_Y), "flat-ground candidate used an unsupported elevation")
		var bearing := Vector2(
			candidate.x - PLAYER_POSITION.x,
			candidate.z - PLAYER_POSITION.z,
		).normalized()
		_expect(previous_bearing.dot(bearing) <= WatcherTeleportSearchType.BEARING_EPSILON, "candidate was less than 90 degrees from the previous bearing")
		_expect(not player_bounds.intersects(EntitySpawnGeometryType.get_bounds(definition, candidate)), "candidate overlapped the player")
		var distance := Vector2(
			candidate.x - PLAYER_POSITION.x,
			candidate.z - PLAYER_POSITION.z,
		).length()
		var nearest_radius_error := INF
		for radius in WatcherTeleportSearchType.RADII:
			nearest_radius_error = minf(nearest_radius_error, absf(distance - radius))
		_expect(nearest_radius_error <= sqrt(0.5), "candidate was not snapped from an authored teleport radius")

func _test_ready_filter_rejects_candidates() -> void:
	var candidates := _find_candidates(TestVoxelSpace.new(), 119, 1, _far_cells_only)
	_expect(not candidates.is_empty(), "ready filter rejected every far candidate")
	for candidate in candidates:
		var planar_offset := Vector2(
			candidate.x - PLAYER_POSITION.x,
			candidate.z - PLAYER_POSITION.z,
		)
		_expect(planar_offset.length() >= 9.0, "position readiness rejection was ignored")

func _test_clear_candidates_precede_occluded_fallbacks() -> void:
	var space := TestVoxelSpace.new()
	var definition := _make_definition()
	var baseline := _find_candidates(space, 48611, 4, _always_ready)
	_expect(not baseline.is_empty(), "occlusion fixture had no baseline candidate")
	if baseline.is_empty():
		return
	var player_center := _player_bounds().get_center()
	var blocked_center := EntitySpawnGeometryType.get_bounds(definition, baseline[0]).get_center()
	var midpoint := player_center.lerp(blocked_center, 0.5)
	space.raycast_solids[Vector3i(floori(midpoint.x), floori(midpoint.y), floori(midpoint.z))] = true
	var candidates := _find_candidates(space, 48611, 4, _always_ready)
	var saw_clear := false
	var saw_occluded := false
	for candidate in candidates:
		var candidate_center := EntitySpawnGeometryType.get_bounds(definition, candidate).get_center()
		var clear := VoxelLineOfSightType.has_clear_path(space, player_center, candidate_center)
		if clear:
			saw_clear = true
			_expect(not saw_occluded, "clear candidate appeared after an occluded fallback")
		else:
			saw_occluded = true
	_expect(saw_clear, "occlusion fixture did not retain a clear candidate")
	_expect(saw_occluded, "occlusion fixture did not produce an occluded fallback")

func _find_candidates(
	space: VoxelSpace,
	behavior_seed: int,
	teleport_sequence: int,
	position_ready: Callable,
) -> Array[Vector3]:
	return WatcherTeleportSearchType.find_candidates(
		space,
		_make_definition(),
		behavior_seed,
		teleport_sequence,
		PLAYER_POSITION,
		_player_bounds(),
		PREVIOUS_POSITION,
		position_ready,
	)

func _make_definition() -> EntityDefinition:
	var definition := EntityDefinition.new()
	definition.body_width = 0.7
	definition.body_height = 2.7
	definition.spawn_placement = EntityDefinition.SpawnPlacement.GROUNDED
	return definition

func _player_bounds() -> AABB:
	return AABB(
		PLAYER_POSITION + Vector3(-0.3, 0.0, -0.3),
		Vector3(0.6, 1.8, 0.6),
	)

func _always_ready(_position: Vector3) -> bool:
	return true

func _far_cells_only(position: Vector3) -> bool:
	return Vector2(
		position.x - PLAYER_POSITION.x,
		position.z - PLAYER_POSITION.z,
	).length() >= 9.0

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[watcher_teleport_search] FAIL: %s" % message)
