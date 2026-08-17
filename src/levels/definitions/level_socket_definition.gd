extends Resource
class_name LevelSocketDefinition

enum Direction {
	NORTH,
	EAST,
	SOUTH,
	WEST,
}

@export var socket_id: StringName
@export var cell: Vector3i
@export var direction: Direction = Direction.NORTH

static func is_valid_direction(value: int) -> bool:
	return value >= 0 and value < Direction.size()

static func vector_for(value: Direction) -> Vector3i:
	match value:
		Direction.NORTH:
			return Vector3i(0, 0, -1)
		Direction.EAST:
			return Vector3i(1, 0, 0)
		Direction.SOUTH:
			return Vector3i(0, 0, 1)
		Direction.WEST:
			return Vector3i(-1, 0, 0)
	return Vector3i.ZERO

static func opposite(value: Direction) -> Direction:
	return ((int(value) + 2) % 4) as Direction

static func rotate(value: Direction, quarter_turns: int) -> Direction:
	return ((int(value) + posmod(quarter_turns, 4)) % 4) as Direction
