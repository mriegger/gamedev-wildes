extends SceneTree

const VoxelCoverSearchType := preload("res://entities/skeleton/voxel_cover_search.gd")

const FEET_Y: float = 1.0
const BODY_WIDTH: float = 0.6
const BODY_HEIGHT: float = 1.8
const ORIGIN := Vector3(0.5, FEET_Y, 0.5)

class TestVoxelSpace:
	extends VoxelSpace

	var has_ground: bool = true
	var highest_top_queries: int = 0
	var movement_solids: Dictionary = {}
	var raycast_solids: Dictionary = {}

	func add_wall(x: int, z: int, blocks_movement: bool = true) -> void:
		for y in range(1, 3):
			var cell := Vector3i(x, y, z)
			raycast_solids[cell] = true
			if blocks_movement:
				movement_solids[cell] = true

	func add_movement_column(x: int, z: int) -> void:
		for y in range(1, 3):
			movement_solids[Vector3i(x, y, z)] = true

	func get_highest_top(_x: int, _z: int) -> float:
		highest_top_queries += 1
		return FEET_Y if has_ground else VoxelSpace.NO_SURFACE_Y

	func is_solid(position: Vector3i) -> bool:
		return movement_solids.has(position)

	func is_raycast_solid(position: Vector3i) -> bool:
		return raycast_solids.has(position)

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	_test_nearest_reachable_hidden_position()
	_test_closer_unreachable_position_is_rejected()
	_test_candidate_columns_are_bounded_per_tick()
	_test_no_cover_exhausts_search()
	_test_equal_distance_result_is_deterministic()
	if _failures == 0:
		print("VOXEL_COVER_SEARCH PASS")
		quit(0)
	else:
		print("VOXEL_COVER_SEARCH FAIL failures=%d" % _failures)
		quit(1)

func _test_nearest_reachable_hidden_position() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(0, 1)
	space.add_wall(4, -1)
	var search := _make_search(space)
	search.begin(ORIGIN, _observation())
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "reachable cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(0.5, FEET_Y, 2.5)), "search did not choose the nearest reachable hidden position")

func _test_closer_unreachable_position_is_rejected() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(0, 1)
	for x in range(-1, 2):
		for z in range(1, 4):
			if x != 0 or z != 2:
				space.add_movement_column(x, z)
	space.add_movement_column(0, 4)
	space.add_wall(4, -1)
	var search := _make_search(space)
	search.begin(ORIGIN, _observation())
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "farther reachable cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(4.5, FEET_Y, 0.5)), "search accepted a closer unreachable hidden position")

func _test_candidate_columns_are_bounded_per_tick() -> void:
	var space := TestVoxelSpace.new()
	space.has_ground = false
	var search := _make_search(space)
	search.begin(ORIGIN, _observation())
	search.advance(NavigationSearchBudget.new(2))
	_expect(space.highest_top_queries == VoxelCoverSearchType.CANDIDATES_PER_TICK, "one advance examined more than 32 candidate columns")
	_expect(search.status == VoxelCoverSearchType.Status.SEARCHING, "bounded search exhausted all candidates in one advance")

func _test_no_cover_exhausts_search() -> void:
	var search := _make_search(TestVoxelSpace.new())
	search.begin(ORIGIN, _observation())
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.EXHAUSTED, "clear terrain did not exhaust without cover")

func _test_equal_distance_result_is_deterministic() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(-2, -1)
	space.add_wall(2, -1)
	var first := _make_search(space)
	var second := _make_search(space)
	first.begin(ORIGIN, _observation())
	second.begin(ORIGIN, _observation())
	_run_to_completion(first)
	_run_to_completion(second)
	_expect(first.status == VoxelCoverSearchType.Status.FOUND and second.status == VoxelCoverSearchType.Status.FOUND, "equal-distance cover was not found")
	if first.status == VoxelCoverSearchType.Status.FOUND and second.status == VoxelCoverSearchType.Status.FOUND:
		_expect(first.get_target().is_equal_approx(second.get_target()), "identical searches selected different cover")
		_expect(first.get_target().is_equal_approx(Vector3(-1.5, FEET_Y, 0.5)), "coordinate ordering did not break equal-distance ties deterministically")

func _make_search(space: VoxelSpace) -> VoxelCoverSearchType:
	return VoxelCoverSearchType.new(space, BODY_WIDTH, BODY_HEIGHT, EntityNavigationLimits.new(32, 512, 2))

func _observation() -> EntityTargetObservation:
	return EntityTargetObservation.new(
		Vector3(20.5, FEET_Y, 0.5),
		Vector3(0.5, FEET_Y + BODY_HEIGHT * 0.5, -8.5),
		Vector3.BACK,
		Vector3.RIGHT,
	)

func _run_to_completion(search: VoxelCoverSearchType) -> void:
	var budget := NavigationSearchBudget.new(2)
	for _step in range(256):
		search.advance(budget)
		if search.status != VoxelCoverSearchType.Status.SEARCHING:
			return
		budget.reset()
	_expect(false, "cover search did not reach a terminal status")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[voxel_cover_search] FAIL: %s" % message)
