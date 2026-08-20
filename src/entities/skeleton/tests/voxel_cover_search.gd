extends SceneTree

const VoxelCoverSearchType := preload("res://entities/skeleton/voxel_cover_search.gd")

const FEET_Y: float = 1.0
const BODY_WIDTH: float = 0.6
const BODY_HEIGHT: float = 1.8
const ORIGIN := Vector3(0.5, FEET_Y, 0.5)

class TestVoxelSpace:
	extends VoxelSpace

	var default_ground_y: float = FEET_Y
	var ground_heights: Dictionary = {}
	var solid_queries: int = 0
	var raycast_queries: int = 0
	var movement_solids: Dictionary = {}
	var raycast_solids: Dictionary = {}

	func add_wall(x: int, z: int, blocks_movement: bool = true) -> void:
		add_wall_levels(x, z, 1, 2, blocks_movement)

	func add_wall_levels(x: int, z: int, min_y: int, max_y: int, blocks_movement: bool = false) -> void:
		for y in range(min_y, max_y + 1):
			var cell := Vector3i(x, y, z)
			raycast_solids[cell] = true
			if blocks_movement:
				movement_solids[cell] = true

	func add_movement_column(x: int, z: int) -> void:
		for y in range(1, 3):
			movement_solids[Vector3i(x, y, z)] = true

	func add_supporting_block(x: int, z: int, top: int) -> void:
		movement_solids[Vector3i(x, top - 1, z)] = true

	func set_ground_height(x: int, z: int, height: float) -> void:
		ground_heights[Vector2i(x, z)] = height

	func get_highest_top(x: int, z: int) -> float:
		return float(ground_heights.get(Vector2i(x, z), default_ground_y))

	func is_solid(position: Vector3i) -> bool:
		solid_queries += 1
		if movement_solids.has(position):
			return true
		var ground_y := float(ground_heights.get(Vector2i(position.x, position.z), default_ground_y))
		return position.y == roundi(ground_y) - 1

	func is_raycast_solid(position: Vector3i) -> bool:
		raycast_queries += 1
		return raycast_solids.has(position)

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	_test_nearest_reachable_hidden_position()
	_test_candidate_exclusion_origin_is_independent()
	_test_closer_unreachable_position_is_rejected()
	_test_exact_radius_boundary()
	_test_total_search_nodes_are_bounded()
	_test_wide_body_support_uses_full_footprint()
	_test_reachable_nodes_are_bounded_per_tick()
	_test_search_resumes_after_each_tick()
	_test_reachable_one_block_up_position()
	_test_reachable_one_block_down_position()
	_test_reachable_multi_step_hill_endpoint()
	_test_varied_height_ground_below_overhang()
	_test_budget_starvation_retains_search_frontier()
	_test_canopy_top_is_not_selected()
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
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "reachable cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(0.5, FEET_Y, 2.5)), "search did not choose the nearest reachable hidden position")
		var path := search.get_target_path()
		_expect(path.front() == Vector3i(0, int(FEET_Y), 0), "cover path did not start at the search origin")
		_expect(path.back() == Vector3i(0, int(FEET_Y), 2), "cover path did not end at the selected target")

func _test_candidate_exclusion_origin_is_independent() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(0, -1)
	var current_origin := ORIGIN + Vector3(2.0, 0.0, 0.0)

	var ordering_search := _make_search(space)
	ordering_search.begin(current_origin, ORIGIN, _observation(), 1.0)
	ordering_search.advance(NavigationSearchBudget.new(1))
	_expect(ordering_search._closed.has(Vector3i(2, int(FEET_Y), 0)), "reachable search did not begin at the current actor position")
	_expect(ordering_search._origin_feet == Vector3i(2, int(FEET_Y), 0), "pathfinding origin did not use the current actor position")

	var unrestricted_search := _make_search(space)
	unrestricted_search.begin(current_origin, ORIGIN, _observation(), 0.0)
	_run_to_completion(unrestricted_search)
	_expect(unrestricted_search.status == VoxelCoverSearchType.Status.FOUND, "hidden attack origin was not a valid unrestricted candidate")
	if unrestricted_search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(unrestricted_search.get_target().is_equal_approx(ORIGIN), "test setup did not make the attack origin the nearest hidden candidate")
	var retreat_search := _make_search(space)
	retreat_search.begin(current_origin, ORIGIN, _observation(), 1.0)
	_run_to_completion(retreat_search)
	_expect(retreat_search.status == VoxelCoverSearchType.Status.FOUND, "minimum-distance retreat did not find farther cover")
	if retreat_search.status == VoxelCoverSearchType.Status.FOUND:
		var target := retreat_search.get_target()
		var horizontal_offset := Vector2(target.x - ORIGIN.x, target.z - ORIGIN.z)
		_expect(horizontal_offset.length_squared() >= 1.0, "candidate filter used the current actor position instead of the attack origin")

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
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "farther reachable cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(4.5, FEET_Y, 0.5)), "search accepted a closer unreachable hidden position")

func _test_exact_radius_boundary() -> void:
	var limits := EntityNavigationLimits.new(4, 128, 1)
	var search := VoxelCoverSearchType.new(TestVoxelSpace.new(), BODY_WIDTH, BODY_HEIGHT, limits)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search._closed.has(Vector3i(-4, int(FEET_Y), 0)), "negative navigation-radius boundary was excluded")
	_expect(search._closed.has(Vector3i(4, int(FEET_Y), 0)), "positive navigation-radius boundary was excluded")
	for feet in search._closed:
		var offset := feet as Vector3i - Vector3i(0, int(FEET_Y), 0)
		_expect(offset.x * offset.x + offset.z * offset.z <= 16, "reachable search expanded beyond its navigation radius")

func _test_total_search_nodes_are_bounded() -> void:
	var limits := EntityNavigationLimits.new(30, 20, 1)
	var search := VoxelCoverSearchType.new(TestVoxelSpace.new(), BODY_WIDTH, BODY_HEIGHT, limits)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search._path_costs.size() == 20, "cover search exceeded or failed to use its total navigation node limit")

func _test_wide_body_support_uses_full_footprint() -> void:
	var space := TestVoxelSpace.new()
	space.default_ground_y = VoxelSpace.NO_SURFACE_Y
	space.set_ground_height(-1, 0, FEET_Y)
	var limits := EntityNavigationLimits.new(4, 64, 1)
	var search := VoxelCoverSearchType.new(space, 1.4, BODY_HEIGHT, limits)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_expect(search.status == VoxelCoverSearchType.Status.SEARCHING, "wide-body cover rejected support at the edge of its footprint")

func _test_reachable_nodes_are_bounded_per_tick() -> void:
	var space := TestVoxelSpace.new()
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	var budget := NavigationSearchBudget.new(2)
	search.advance(budget)
	_expect(search._closed.size() > 0 and search._closed.size() <= VoxelCoverSearchType.NODES_PER_TICK, "one advance exceeded its reachable-node limit")
	_expect(space.solid_queries <= 4096, "one advance exceeded the bounded movement-probe workload")
	_expect(space.raycast_queries <= 4096, "one advance exceeded the bounded occlusion-probe workload")
	_expect(budget.try_acquire(), "one cover-search slice consumed more than one navigation slot")
	_expect(not budget.try_acquire(), "cover search did not consume one navigation slot")
	_expect(search.status == VoxelCoverSearchType.Status.SEARCHING, "bounded search exhausted all candidates in one advance")

func _test_search_resumes_after_each_tick() -> void:
	var space := TestVoxelSpace.new()
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	var budget := NavigationSearchBudget.new(1)
	budget.try_acquire()
	search.advance(budget)
	_expect(search._closed.is_empty(), "budget-starved search advanced reachable nodes")
	budget.reset()
	search.advance(budget)
	var first_tick_nodes := search._closed.size()
	_expect(first_tick_nodes > 0 and first_tick_nodes <= VoxelCoverSearchType.NODES_PER_TICK, "resumed search did not process one bounded node slice")
	budget.reset()
	search.advance(budget)
	_expect(search._closed.size() > first_tick_nodes, "search did not resume its existing frontier")
	_expect(search._closed.size() <= first_tick_nodes + VoxelCoverSearchType.NODES_PER_TICK, "resumed search exceeded its node slice")
	_expect(search.status == VoxelCoverSearchType.Status.SEARCHING, "resumed bounded search terminated unexpectedly")

func _test_reachable_one_block_up_position() -> void:
	var space := TestVoxelSpace.new()
	space.set_ground_height(0, 2, FEET_Y + 1.0)
	space.add_wall_levels(0, 1, 1, 4)
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "reachable one-block-up cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(0.5, FEET_Y + 1.0, 2.5)), "one-block-up cover resolved to the wrong elevation")

func _test_reachable_one_block_down_position() -> void:
	var space := TestVoxelSpace.new()
	space.set_ground_height(0, 2, FEET_Y - 1.0)
	space.add_wall_levels(0, 1, -1, 2)
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "reachable one-block-down cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(0.5, FEET_Y - 1.0, 2.5)), "one-block-down cover resolved to the wrong elevation")

func _test_reachable_multi_step_hill_endpoint() -> void:
	var space := TestVoxelSpace.new()
	space.set_ground_height(1, 0, FEET_Y + 1.0)
	space.set_ground_height(2, 0, FEET_Y + 2.0)
	space.set_ground_height(3, 0, FEET_Y + 3.0)
	space.add_wall_levels(2, 0, 1, 7)
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _side_observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "reachable multi-step hill cover was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(3.5, FEET_Y + 3.0, 0.5)), "multi-step hill cover resolved to the wrong elevation")

func _test_varied_height_ground_below_overhang() -> void:
	var space := TestVoxelSpace.new()
	space.set_ground_height(1, 0, FEET_Y + 1.0)
	space.set_ground_height(2, 0, FEET_Y + 2.0)
	space.set_ground_height(3, 0, FEET_Y + 8.0)
	space.add_supporting_block(3, 0, int(FEET_Y + 3.0))
	space.add_wall_levels(3, 0, int(FEET_Y + 7.0), int(FEET_Y + 7.0), true)
	space.add_wall_levels(2, 0, 1, 10)
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _side_observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "reachable varied-height ground below an overhang was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(3.5, FEET_Y + 3.0, 0.5)), "overhang search did not select the reachable lower terrain")

func _test_budget_starvation_retains_search_frontier() -> void:
	var space := TestVoxelSpace.new()
	space.set_ground_height(0, 2, FEET_Y + 1.0)
	space.add_wall_levels(0, 1, 1, 4)
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	var budget := NavigationSearchBudget.new(1)
	budget.try_acquire()
	search.advance(budget)
	_expect(search.status == VoxelCoverSearchType.Status.SEARCHING, "budget-starved search skipped its pending elevation")
	budget.reset()
	search.advance(budget)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "budget-starved candidate was not retried")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(0.5, FEET_Y + 1.0, 2.5)), "budget starvation advanced past the pending candidate")

func _test_canopy_top_is_not_selected() -> void:
	var space := TestVoxelSpace.new()
	space.set_ground_height(0, 2, FEET_Y + 5.0)
	space.add_supporting_block(0, 2, int(FEET_Y))
	space.add_wall_levels(0, 1, 1, 7)
	var search := _make_search(space)
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.FOUND, "walkable ground beneath a canopy was not found")
	if search.status == VoxelCoverSearchType.Status.FOUND:
		_expect(search.get_target().is_equal_approx(Vector3(0.5, FEET_Y, 2.5)), "search selected an arbitrary canopy top")

func _test_no_cover_exhausts_search() -> void:
	var search := _make_search(TestVoxelSpace.new())
	search.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	_run_to_completion(search)
	_expect(search.status == VoxelCoverSearchType.Status.EXHAUSTED, "clear terrain did not exhaust without cover")

func _test_equal_distance_result_is_deterministic() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(-2, -1)
	space.add_wall(2, -1)
	var first := _make_search(space)
	var second := _make_search(space)
	first.begin(ORIGIN, ORIGIN, _observation(), 0.0)
	second.begin(ORIGIN, ORIGIN, _observation(), 0.0)
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

func _side_observation() -> EntityTargetObservation:
	return EntityTargetObservation.new(
		Vector3(20.5, FEET_Y, 0.5),
		Vector3(-8.5, FEET_Y + BODY_HEIGHT * 0.5, 0.5),
		Vector3.RIGHT,
		Vector3.BACK,
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
