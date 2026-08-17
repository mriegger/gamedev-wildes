extends SceneTree

const EntityTargetObservationType := preload("res://entities/entity_target_observation.gd")
const VoxelCameraOcclusionType := preload("res://entities/skeleton/voxel_camera_occlusion.gd")

const FEET_POSITION := Vector3(0.5, 0.0, 5.5)
const BODY_WIDTH: float = 2.0
const BODY_HEIGHT: float = 3.0

class TestVoxelSpace:
	extends VoxelSpace

	var solid_cells: Dictionary = {}

	func add_wall(z: int, minimum_x: int, maximum_x: int, minimum_y: int, maximum_y: int) -> void:
		for x in range(minimum_x, maximum_x + 1):
			for y in range(minimum_y, maximum_y + 1):
				solid_cells[Vector3i(x, y, z)] = true

	func is_raycast_solid(position: Vector3i) -> bool:
		return solid_cells.has(position)

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _run() -> void:
	_test_fully_hidden_body()
	_test_partial_head_exposure()
	_test_partial_side_exposure()
	_test_clear_view()
	_test_camera_rotation()
	_test_diagonal_pitched_full_cover()
	_test_diagonal_pitched_corner_exposure()
	if _failures == 0:
		print("VOXEL_CAMERA_OCCLUSION PASS")
		quit(0)
	else:
		print("VOXEL_CAMERA_OCCLUSION FAIL failures=%d" % _failures)
		quit(1)

func _test_fully_hidden_body() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(2, -1, 1, 0, 2)
	_expect(
		VoxelCameraOcclusionType.is_hidden(space, _north_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"a wall covering every silhouette sample did not hide the body",
	)

func _test_partial_head_exposure() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(2, -1, 1, 0, 1)
	_expect(
		not VoxelCameraOcclusionType.is_hidden(space, _north_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"an exposed head row was treated as hidden",
	)

func _test_partial_side_exposure() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(2, 0, 1, 0, 2)
	_expect(
		not VoxelCameraOcclusionType.is_hidden(space, _north_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"an exposed side column was treated as hidden",
	)

func _test_clear_view() -> void:
	var space := TestVoxelSpace.new()
	_expect(
		not VoxelCameraOcclusionType.is_hidden(space, _north_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"a clear camera view was treated as hidden",
	)

func _test_camera_rotation() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(2, -1, 1, 0, 2)
	_expect(
		VoxelCameraOcclusionType.is_hidden(space, _north_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"the north-facing camera did not recognize its covering wall",
	)
	var rotated_observation := EntityTargetObservationType.new(
		Vector3.ZERO,
		Vector3(-5.5, 1.5, 5.5),
		Vector3.RIGHT,
		Vector3.FORWARD,
	)
	_expect(
		not VoxelCameraOcclusionType.is_hidden(space, rotated_observation, FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"rotating the camera did not expose the body beside the wall",
	)

func _test_diagonal_pitched_full_cover() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(2, -6, -1, -10, 10)
	_expect(
		VoxelCameraOcclusionType.is_hidden(space, _diagonal_pitched_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"a full diagonal cover wall did not hide the pitched body bounds",
	)

func _test_diagonal_pitched_corner_exposure() -> void:
	var space := TestVoxelSpace.new()
	space.add_wall(2, -6, -2, -10, 10)
	_expect(
		not VoxelCameraOcclusionType.is_hidden(space, _diagonal_pitched_observation(), FEET_POSITION, BODY_WIDTH, BODY_HEIGHT),
		"an exposed depth corner was treated as hidden by a pitched diagonal camera",
	)

func _diagonal_pitched_observation() -> EntityTargetObservationType:
	var camera_forward := Vector3(1.0, -0.35, 1.0).normalized()
	return EntityTargetObservationType.new(
		Vector3.ZERO,
		Vector3(-5.5, 5.0, -0.5),
		camera_forward,
		Vector3(1.0, 0.0, -1.0),
	)

func _north_observation() -> EntityTargetObservationType:
	return EntityTargetObservationType.new(
		Vector3.ZERO,
		Vector3(0.5, 1.5, -2.5),
		Vector3.BACK,
		Vector3.RIGHT,
	)

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[voxel_camera_occlusion] FAIL: %s" % message)
