extends RefCounted
class_name BlockId

## Canonical Block IDs for Wildes.
## Single source of truth for all block types.
## Groups: Air, Terrain, Vegetation, Light/Utility (Torches)

enum Type {
	# Special / Empty
	AIR = 0,

	# Terrain - ground layers
	GRASS = 1,  # top layer grass
	DIRT = 2,   # under grass
	SAND = 3,   # lowland / beach
	STONE = 4,  # ridges / deep

	# Vegetation / Wood
	LOG = 5,      # tree trunk (also exposed as Wood in inventory)
	LEAVES = 6,   # tree foliage

	# Light / Decor
	TORCH = 7,    # wall/ground attachable light

	# Liquid
	WATER = 8,  

	COUNT = 9,
}

# Category groups - identity only, no physical duplication (SOLID_TERRAIN removed, use catalog for solidity)
const TERRAIN: Array[Type] = [Type.GRASS, Type.DIRT, Type.SAND, Type.STONE]
const VEGETATION: Array[Type] = [Type.LOG, Type.LEAVES]
const LIGHTS: Array[Type] = [Type.TORCH]
const LIQUIDS: Array[Type] = [Type.WATER]

# Display names for UI / debugging
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
}

# Internal short names
const INTERNAL_NAMES: Dictionary = {
	Type.AIR: "air",
	Type.GRASS: "grass",
	Type.DIRT: "dirt",
	Type.SAND: "sand",
	Type.STONE: "stone",
	Type.LOG: "log",
	Type.LEAVES: "leaves",
	Type.TORCH: "torch",
	Type.WATER: "water",
}


static func get_display_name(id: Type) -> String:
	return DISPLAY_NAMES.get(id, "Unknown")

static func get_internal_name(id: Type) -> String:
	return INTERNAL_NAMES.get(id, "unknown")

static func is_air(id: Type) -> bool:
	return id == Type.AIR

static func is_terrain(id: Type) -> bool:
	return id in TERRAIN

static func is_vegetation(id: Type) -> bool:
	return id in VEGETATION

static func is_light(id: Type) -> bool:
	return id in LIGHTS

static func is_water(id: Type) -> bool:
	return id in LIQUIDS

static func is_liquid(id: Type) -> bool:
	return id in LIQUIDS

static func is_valid(id: int) -> bool:
	return id >= Type.AIR and id < Type.COUNT

static func from_string(name: String) -> Type:
	var lower = name.to_lower()
	for k in INTERNAL_NAMES:
		if INTERNAL_NAMES[k] == lower:
			return k
	# allow display names
	for k in DISPLAY_NAMES:
		if DISPLAY_NAMES[k].to_lower() == lower:
			return k
	return Type.AIR
