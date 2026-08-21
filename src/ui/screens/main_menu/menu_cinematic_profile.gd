extends Resource
class_name MenuCinematicProfile

const MAX_TOTAL_POPULATION_COST := 32

@export var world_seed: int = 1337
@export var maximum_anchor_radius: float = 72.0
@export var logo_delay_seconds: float = 0.5
@export var logo_fade_seconds: float = 1.5
@export var world_fade_seconds: float = 2.0
@export var controls_fade_seconds: float = 1.0
@export var crossfade_seconds: float = 1.25
@export var shots: Array[MenuCinematicShot] = []

func validate(entity_catalog: EntityCatalog) -> bool:
	if (
		entity_catalog == null
		or not is_finite(maximum_anchor_radius)
		or maximum_anchor_radius <= 0.0
		or shots.is_empty()
		or not is_finite(logo_delay_seconds)
		or logo_delay_seconds < 0.0
		or not is_finite(logo_fade_seconds)
		or logo_fade_seconds <= 0.0
		or not is_finite(world_fade_seconds)
		or world_fade_seconds <= 0.0
		or not is_finite(controls_fade_seconds)
		or controls_fade_seconds <= 0.0
		or not is_finite(crossfade_seconds)
		or crossfade_seconds <= 0.0
	):
		return false
	var ids: Dictionary = {}
	var population_cost := 0
	for shot in shots:
		if shot == null or not shot.validate(entity_catalog, maximum_anchor_radius) or ids.has(shot.id):
			return false
		ids[shot.id] = true
		for spawn in shot.spawns:
			population_cost += spawn.count * entity_catalog.get_maximum_lineage_capacity(spawn.entity_id)
			if population_cost > MAX_TOTAL_POPULATION_COST:
				return false
	return population_cost > 0
