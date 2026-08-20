extends SceneTree

class TestVoxelSpace:
	extends VoxelSpace

	var _solid_cells: Dictionary = {}
	var _blocked_faces: Dictionary = {}
	var _interaction_bounds: Dictionary = {}

	func add_solid(cell: Vector3i) -> void:
		_solid_cells[cell] = true

	func set_interaction_bounds(cell: Vector3i, bounds: AABB) -> void:
		_interaction_bounds[cell] = bounds

	func block_face(cell: Vector3i, normal: Vector3i) -> void:
		var faces := _blocked_faces.get(cell, []) as Array
		faces.append(normal)
		_blocked_faces[cell] = faces

	func is_raycast_solid(position: Vector3i) -> bool:
		return _solid_cells.has(position)

	func get_interaction_bounds(position: Vector3i) -> AABB:
		return _interaction_bounds.get(position, AABB(Vector3(position), Vector3.ONE)) as AABB

	func is_face_targetable(block_position: Vector3i, face_normal: Vector3i) -> bool:
		if not is_raycast_solid(block_position):
			return false
		var faces := _blocked_faces.get(block_position, []) as Array
		return not faces.has(face_normal)

var _errors: Array[String] = []

func _init() -> void:
	_test_axes()
	_test_diagonal_tie_order()
	_test_starting_inside_solid()
	_test_starting_outside_custom_bounds()
	_test_untargetable_face()
	_test_exact_reach()
	_test_custom_bounds()
	_test_zero_direction()
	if _errors.is_empty():
		print("VOXEL_RAYCAST PASS")
		quit(0)
	else:
		for error in _errors:
			push_error(error)
		quit(1)

func _test_axes() -> void:
	var cases: Array[Dictionary] = [
		{
			"label": "+x",
			"direction": Vector3.RIGHT,
			"target": Vector3i(2, 0, 0),
			"placement": Vector3i(1, 0, 0),
			"normal": Vector3i.LEFT,
		},
		{
			"label": "-x",
			"direction": Vector3.LEFT,
			"target": Vector3i(-2, 0, 0),
			"placement": Vector3i(-1, 0, 0),
			"normal": Vector3i.RIGHT,
		},
		{
			"label": "+y",
			"direction": Vector3.UP,
			"target": Vector3i(0, 2, 0),
			"placement": Vector3i(0, 1, 0),
			"normal": Vector3i.DOWN,
		},
		{
			"label": "-y",
			"direction": Vector3.DOWN,
			"target": Vector3i(0, -2, 0),
			"placement": Vector3i(0, -1, 0),
			"normal": Vector3i.UP,
		},
		{
			"label": "+z",
			"direction": Vector3.BACK,
			"target": Vector3i(0, 0, 2),
			"placement": Vector3i(0, 0, 1),
			"normal": Vector3i.FORWARD,
		},
		{
			"label": "-z",
			"direction": Vector3.FORWARD,
			"target": Vector3i(0, 0, -2),
			"placement": Vector3i(0, 0, -1),
			"normal": Vector3i.BACK,
		},
	]
	for test_case in cases:
		var space := TestVoxelSpace.new()
		space.add_solid(test_case["target"] as Vector3i)
		var hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), test_case["direction"] as Vector3, 4.0)
		_expect_hit(
			hit,
			test_case["target"] as Vector3i,
			test_case["placement"] as Vector3i,
			test_case["normal"] as Vector3i,
			String(test_case["label"])
		)
		if hit != null:
			_expect(hit.interaction_bounds == AABB(Vector3(test_case["target"] as Vector3i), Vector3.ONE), "%s ray omitted its full-cell interaction bounds" % String(test_case["label"]))

func _test_diagonal_tie_order() -> void:
	var space := TestVoxelSpace.new()
	space.add_solid(Vector3i(1, 0, 1))
	var hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3(1.0, 0.0, 1.0), 3.0)
	_expect_hit(hit, Vector3i(1, 0, 1), Vector3i(0, 0, 1), Vector3i.LEFT, "diagonal")

func _test_starting_inside_solid() -> void:
	var space := TestVoxelSpace.new()
	space.add_solid(Vector3i.ZERO)
	space.add_solid(Vector3i(2, 0, 0))
	var hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 4.0)
	_expect_hit(hit, Vector3i(2, 0, 0), Vector3i(1, 0, 0), Vector3i.LEFT, "start solid")

func _test_starting_outside_custom_bounds() -> void:
	var space := TestVoxelSpace.new()
	var foliage_cell := Vector3i.ZERO
	var contiguous_cell := Vector3i.RIGHT
	space.add_solid(foliage_cell)
	space.set_interaction_bounds(foliage_cell, AABB(Vector3(0.375, 0.0, 0.375), Vector3(0.25, 0.75, 0.25)))
	space.add_solid(contiguous_cell)
	var foliage_hit := VoxelRaycast.cast(space, Vector3(0.1, 0.5, 0.5), Vector3.RIGHT, 2.0)
	_expect_hit(foliage_hit, foliage_cell, foliage_cell + Vector3i.LEFT, Vector3i.LEFT, "custom bounds start margin")
	if foliage_hit != null:
		_expect(is_equal_approx(foliage_hit.ray_distance, 0.275), "custom bounds start margin reported the wrong distance")
	var margin_hit := VoxelRaycast.cast(space, Vector3(0.1, 0.5, 0.2), Vector3.RIGHT, 2.0)
	_expect_hit(margin_hit, contiguous_cell, foliage_cell, Vector3i.LEFT, "custom bounds transparent start margin")
	if margin_hit != null:
		_expect(is_equal_approx(margin_hit.ray_distance, 0.9), "custom bounds transparent start margin reported the wrong distance")

func _test_untargetable_face() -> void:
	var space := TestVoxelSpace.new()
	space.add_solid(Vector3i(1, 0, 0))
	space.block_face(Vector3i(1, 0, 0), Vector3i.LEFT)
	space.add_solid(Vector3i(3, 0, 0))
	var hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 4.0)
	_expect_hit(hit, Vector3i(3, 0, 0), Vector3i(2, 0, 0), Vector3i.LEFT, "untargetable face")

func _test_exact_reach() -> void:
	var space := TestVoxelSpace.new()
	space.add_solid(Vector3i(6, 0, 0))
	var exact_hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 5.5)
	_expect_hit(exact_hit, Vector3i(6, 0, 0), Vector3i(5, 0, 0), Vector3i.LEFT, "exact reach")
	_expect(is_equal_approx(exact_hit.ray_distance, 5.5), "exact reach reported the wrong ray distance")
	var short_hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 5.4999)
	_expect(short_hit == null, "ray shorter than the exact boundary reached its target")
	var copied_hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 5.5)
	_expect(copied_hit != exact_hit, "raycasts reused mutable hit state")

func _test_custom_bounds() -> void:
	var space := TestVoxelSpace.new()
	var foliage_cell := Vector3i(2, 0, 0)
	var fallback_cell := Vector3i(4, 0, 0)
	space.add_solid(foliage_cell)
	space.set_interaction_bounds(foliage_cell, AABB(Vector3(2.375, 0.0, 0.375), Vector3(0.25, 0.75, 0.25)))
	space.add_solid(fallback_cell)
	var centered_hit := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.RIGHT, 5.0)
	_expect_hit(centered_hit, foliage_cell, foliage_cell + Vector3i.LEFT, Vector3i.LEFT, "custom bounds center")
	if centered_hit != null:
		_expect(centered_hit.interaction_bounds == AABB(Vector3(2.375, 0.0, 0.375), Vector3(0.25, 0.75, 0.25)), "custom bounds were not retained on the ray hit")
		_expect(is_equal_approx(centered_hit.ray_distance, 1.875), "custom bounds reported the cell boundary instead of the shape boundary")
	var width_miss := VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.2), Vector3.RIGHT, 5.0)
	_expect_hit(width_miss, fallback_cell, fallback_cell + Vector3i.LEFT, Vector3i.LEFT, "custom bounds width miss")
	var height_miss := VoxelRaycast.cast(space, Vector3(0.5, 0.9, 0.5), Vector3.RIGHT, 5.0)
	_expect_hit(height_miss, fallback_cell, fallback_cell + Vector3i.LEFT, Vector3i.LEFT, "custom bounds height miss")
	var top_hit := VoxelRaycast.cast(space, Vector3(2.5, 2.0, 0.5), Vector3.DOWN, 3.0)
	_expect_hit(top_hit, foliage_cell, foliage_cell + Vector3i.UP, Vector3i.UP, "custom bounds top")
	_expect(is_equal_approx(top_hit.ray_distance, 1.25), "custom bounds top distance was incorrect")

func _test_zero_direction() -> void:
	var space := TestVoxelSpace.new()
	space.add_solid(Vector3i(1, 0, 0))
	_expect(VoxelRaycast.cast(space, Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 4.0) == null, "zero direction produced a hit")

func _expect_hit(
	hit: VoxelRaycastHit,
	target: Vector3i,
	placement: Vector3i,
	normal: Vector3i,
	label: String
) -> void:
	_expect(hit != null, "%s ray did not hit" % label)
	if hit == null:
		return
	_expect(hit.target_cell == target, "%s ray targeted %s instead of %s" % [label, hit.target_cell, target])
	_expect(hit.placement_cell == placement, "%s ray placed at %s instead of %s" % [label, hit.placement_cell, placement])
	_expect(hit.face_normal == normal, "%s ray normal was %s instead of %s" % [label, hit.face_normal, normal])

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
