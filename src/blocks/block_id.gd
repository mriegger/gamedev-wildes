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
	COBBLESTONE = 10,
	MOSSY_STONE_BRICKS = 11,
	STONE_BRICKS = 12,
	TERRACOTTA_BRICKS = 13,
	WOOD_PLANKS = 14,
	FARMLAND_DRY = 15,
	ANVIL = 16,
	COUNT = 17,
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
	Type.COBBLESTONE: "Cobblestone",
	Type.MOSSY_STONE_BRICKS: "Mossy Stone Bricks",
	Type.STONE_BRICKS: "Stone Bricks",
	Type.TERRACOTTA_BRICKS: "Terracotta Bricks",
	Type.WOOD_PLANKS: "Wood Planks",
	Type.FARMLAND_DRY: "Dry Farmland",
	Type.ANVIL: "Anvil",
}

static func get_display_name(id: Type) -> String:
	return DISPLAY_NAMES.get(id, "Unknown")

static func is_valid(id: int) -> bool:
	return id >= Type.AIR and id < Type.COUNT

static func is_chunk_cube(id: int) -> bool:
	return is_valid(id) and id != Type.AIR and id != Type.TORCH and id != Type.WATER and id != Type.ANVIL

static func occludes_chunk_face(id: int) -> bool:
	return is_chunk_cube(id)

static func is_ao_solid(id: int) -> bool:
	return is_valid(id) and id != Type.AIR and id != Type.TORCH and id != Type.WATER
