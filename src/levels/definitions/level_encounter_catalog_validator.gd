extends RefCounted
class_name LevelEncounterCatalogValidator

const EntitySpawnGeometryType := preload("res://entities/entity_spawn_geometry.gd")
const LevelModuleSpaceType := preload("res://levels/definitions/level_module_space.gd")

static func validate(level_catalog: LevelCatalog, entity_catalog: EntityCatalog) -> bool:
	if level_catalog == null or entity_catalog == null or not level_catalog.validate() or not entity_catalog.validate():
		return false
	var valid := true
	for level in level_catalog.levels:
		if level == null:
			continue
		for requirement in level.room_requirements:
			if requirement == null or requirement.encounter == null:
				continue
			for group in requirement.encounter.enemy_groups:
				if group == null:
					continue
				if not entity_catalog.has_definition(group.entity_id):
					push_error("[LevelEncounterCatalogValidator] Unknown entity %s for %s" % [group.entity_id, level.level_id])
					valid = false
					continue
				var entity := entity_catalog.get_definition(group.entity_id)
				for module_id in requirement.module_ids:
					if not level_catalog.has_module(module_id):
						continue
					var module := level_catalog.get_module(module_id)
					if not _has_usable_candidate(module, entity):
						push_error("[LevelEncounterCatalogValidator] Module %s cannot spawn %s for %s" % [module_id, group.entity_id, level.level_id])
						valid = false
	return valid

static func _has_usable_candidate(module: LevelModuleDefinition, entity: EntityDefinition) -> bool:
	var space := LevelModuleSpaceType.new(module)
	for feet_cell in module.get_enemy_spawn_candidate_cells():
		var feet_position := Vector3(feet_cell) + Vector3(0.5, 0.0, 0.5)
		if EntitySpawnGeometryType.can_spawn(space, entity, feet_position):
			return true
	return false
