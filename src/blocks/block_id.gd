extends RefCounted
class_name BlockId

enum Type {
	AIR = 0,
	GRASS = 1,
	DIRT = 2,
	SAND = 3,
	STONE = 4,
	LOG = 5,
	LEAVES = 6,
	TORCH = 7,
	WATER = 8,
	COPPER = 9,
	COUNT = 10,
}

const DISPLAY_NAMES: Dictionary = {
	Type.AIR: "Air",
	Type.GRASS: "Grass",
	Type.DIRT: "Dirt",
	Type.SAND: "Sand",
	Type.STONE: "Stone",
	Type.LOG: "Wood",
	Type.LEAVES: "Leaves",
	Type.TORCH: "Torch",
	Type.WATER: "Water",
	Type.COPPER: "Copper",
}

static func get_display_name(id: Type) -> String:
	return DISPLAY_NAMES.get(id, "Unknown")

static func is_valid(id: int) -> bool:
	return id >= Type.AIR and id < Type.COUNT

static func is_chunk_cube(id: int) -> bool:
	return is_valid(id) and id != Type.AIR and id != Type.TORCH and id != Type.WATER
