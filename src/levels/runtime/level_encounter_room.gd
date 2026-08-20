extends RefCounted
class_name LevelEncounterRoom

var parent_room_id: int:
	get:
		return _parent_room_id
var parent_door_id: int:
	get:
		return _parent_door_id
var child_room_ids: Array[int]:
	get:
		return _child_room_ids.duplicate()
var door_ids: Array[int]:
	get:
		return _door_ids.duplicate()
var enemy_ids: Array[StringName]:
	get:
		return _enemy_ids.duplicate()
var spawn_cells: Array[Vector3i]:
	get:
		return _spawn_cells.duplicate()
var discovery_placement_ids: Array[int]:
	get:
		return _discovery_placement_ids.duplicate()

var _room_id: int
var _parent_room_id: int
var _parent_door_id: int
var _child_room_ids: Array[int] = []
var _door_ids: Array[int] = []
var _enemy_ids: Array[StringName] = []
var _spawn_cells: Array[Vector3i] = []
var _discovery_placement_ids: Array[int] = []
var _interior_cells: Dictionary = {}

func _init(
	p_room_id: int,
	p_parent_room_id: int,
	p_parent_door_id: int,
	p_child_room_ids: Array[int],
	p_door_ids: Array[int],
	p_enemy_ids: Array[StringName],
	p_spawn_cells: Array[Vector3i],
	p_discovery_placement_ids: Array[int],
	p_interior_cells: Dictionary,
) -> void:
	assert(p_room_id >= 0)
	assert(p_parent_room_id >= -1 and p_parent_door_id >= 0)
	assert(not p_door_ids.is_empty() and not p_discovery_placement_ids.is_empty())
	assert(p_enemy_ids.is_empty() == p_spawn_cells.is_empty())
	_room_id = p_room_id
	_parent_room_id = p_parent_room_id
	_parent_door_id = p_parent_door_id
	_child_room_ids.assign(p_child_room_ids)
	_door_ids.assign(p_door_ids)
	_enemy_ids.assign(p_enemy_ids)
	_spawn_cells.assign(p_spawn_cells)
	_discovery_placement_ids.assign(p_discovery_placement_ids)
	_interior_cells = p_interior_cells.duplicate()

func has_encounter() -> bool:
	return not _enemy_ids.is_empty()

func contains_body(feet_position: Vector3, body_width: float, body_height: float, doorways: Array[LevelDoorway]) -> bool:
	assert(feet_position.is_finite() and body_width > 0.0 and body_height > 0.0)
	var half_width := body_width * 0.5
	var body_bounds := AABB(
		feet_position + Vector3(-half_width, 0.0, -half_width),
		Vector3(body_width, body_height, body_width)
	)
	var minimum := Vector3i(
		floori(body_bounds.position.x),
		floori(body_bounds.position.y),
		floori(body_bounds.position.z)
	)
	var maximum_point := body_bounds.end - Vector3.ONE * 0.001
	var maximum := Vector3i(
		floori(maximum_point.x),
		floori(maximum_point.y),
		floori(maximum_point.z)
	)
	for y in range(minimum.y, maximum.y + 1):
		for z in range(minimum.z, maximum.z + 1):
			for x in range(minimum.x, maximum.x + 1):
				if not _interior_cells.has(Vector3i(x, y, z)):
					return false
	for doorway in doorways:
		if doorway == null or doorway.room_id != _room_id:
			continue
		for cell in doorway.aperture_cells:
			if body_bounds.intersects(AABB(Vector3(cell), Vector3.ONE)):
				return false
	return true
