extends Resource
class_name BiomeLibrary

@export var biomes: Array[Biome] = []

func validate() -> bool:
	var valid := true
	var ids: Dictionary = {}
	if biomes.is_empty():
		push_error("[BiomeLibrary] No biomes configured")
		valid = false
	for biome in biomes:
		if biome == null:
			push_error("[BiomeLibrary] Null biome")
			valid = false
			continue
		if biome.biome_id.is_empty():
			push_error("[BiomeLibrary] Biome has an empty id")
			valid = false
			continue
		if ids.has(biome.biome_id):
			push_error("[BiomeLibrary] Duplicate biome id: %s" % biome.biome_id)
			valid = false
			continue
		ids[biome.biome_id] = true
	return valid

func find_closest(params: PackedFloat32Array) -> Biome:
	var best: Biome
	var best_distance: float = INF
	for biome in biomes:
		var distance := biome.distance_squared_to(params)
		if distance < best_distance:
			best = biome
			best_distance = distance
	return best
