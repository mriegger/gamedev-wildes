extends Resource
class_name MenuCinematicSpawn

@export var entity_id: StringName
@export var count: int = 1
@export var column_offset: Vector2i
@export var spread_radius: int = 4
@export var behavior_seed: int

func validate(entity_catalog: EntityCatalog) -> bool:
	return (
		entity_catalog != null
		and entity_catalog.has_definition(entity_id)
		and count > 0
		and count <= 8
		and spread_radius >= 0
		and spread_radius <= 12
		and behavior_seed != 0
	)
