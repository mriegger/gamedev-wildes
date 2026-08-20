extends Resource
class_name EntityDefinition

enum SpawnPhase {
	DAY,
	NIGHT,
}

enum SpawnPlacement {
	GROUNDED,
	AERIAL,
}

@export var id: StringName
@export var actor_scene: PackedScene
@export var behavior: EntityBehaviorDefinition
@export var stats_definition: CombatStatsDefinition
@export var damage_affinities: Array[DamageAffinityDefinition]
@export_range(0, 999999999, 1, "or_greater") var experience_reward: int = 0
@export var loot_pool: LootPoolDefinition
@export var defeat_spawn: EntityDefeatSpawnDefinition
@export_range(0.1, 4.0, 0.01) var body_width: float = 0.6
@export_range(0.1, 4.0, 0.01) var body_height: float = 1.8
@export var ambient_spawn_enabled: bool = true
@export var ambient_spawn_phase: SpawnPhase = SpawnPhase.NIGHT
@export_range(0, 64, 1) var ambient_max_active: int = 1
@export_range(0.01, 10000.0, 0.01, "or_greater") var ambient_spawn_weight: float = 100.0
@export var ambient_spawn_floor_ids: Array[int] = []
@export var spawn_placement: SpawnPlacement = SpawnPlacement.GROUNDED
@export_range(1, 32, 1) var ambient_aerial_altitude_min_blocks: int = 8
@export_range(1, 32, 1) var ambient_aerial_altitude_max_blocks: int = 14
@export var ambient_despawn_outside_spawn_phase: bool = false
@export var combat_targetable: bool = true
@export var hostile_to_player: bool = false

func validate(source: String) -> bool:
	var valid := true
	if id.is_empty():
		push_error("[EntityDefinition] Empty ID at %s" % source)
		valid = false
	if actor_scene == null:
		push_error("[EntityDefinition] Missing actor scene for %s at %s" % [id, source])
		valid = false
	if behavior == null:
		push_error("[EntityDefinition] Missing behavior for %s at %s" % [id, source])
		valid = false
	elif not behavior.validate(source):
		valid = false
	if stats_definition == null:
		push_error("[EntityDefinition] Missing stats definition for %s at %s" % [id, source])
		valid = false
	elif not stats_definition.validate():
		push_error("[EntityDefinition] Invalid stats definition for %s at %s" % [id, source])
		valid = false
	var affinity_ids: Dictionary[StringName, bool] = {}
	for affinity in damage_affinities:
		if affinity == null or not affinity.validate(source):
			valid = false
			continue
		if affinity_ids.has(affinity.damage_type.id):
			push_error("[EntityDefinition] Duplicate %s affinity for %s at %s" % [affinity.damage_type.id, id, source])
			valid = false
		else:
			affinity_ids[affinity.damage_type.id] = true
	if experience_reward < 0:
		push_error("[EntityDefinition] Invalid experience reward for %s at %s" % [id, source])
		valid = false
	if loot_pool != null and not loot_pool.validate():
		push_error("[EntityDefinition] Invalid loot pool for %s at %s" % [id, source])
		valid = false
	if defeat_spawn != null and not defeat_spawn.validate(source):
		valid = false
	if actor_scene != null and behavior != null and not is_actor_compatible():
		push_error("[EntityDefinition] Actor scene and behavior are incompatible for %s at %s" % [id, source])
		valid = false
	if not is_finite(body_width) or body_width <= 0.0 or not is_finite(body_height) or body_height <= 0.0:
		push_error("[EntityDefinition] Invalid body dimensions for %s at %s" % [id, source])
		valid = false
	if ambient_spawn_enabled:
		if ambient_max_active < 0:
			push_error("[EntityDefinition] Invalid active cap for %s at %s" % [id, source])
			valid = false
		if not is_finite(ambient_spawn_weight) or ambient_spawn_weight <= 0.0:
			push_error("[EntityDefinition] Invalid ambient spawn weight for %s at %s" % [id, source])
			valid = false
		if ambient_spawn_floor_ids.is_empty():
			push_error("[EntityDefinition] Missing spawn floors for %s at %s" % [id, source])
			valid = false
	else:
		if ambient_max_active != 0:
			push_error("[EntityDefinition] Disabled ambient spawn has an active cap for %s at %s" % [id, source])
			valid = false
		if not ambient_spawn_floor_ids.is_empty():
			push_error("[EntityDefinition] Disabled ambient spawn has spawn floors for %s at %s" % [id, source])
			valid = false
	if spawn_placement == SpawnPlacement.AERIAL and (ambient_aerial_altitude_min_blocks < 1 or ambient_aerial_altitude_min_blocks > ambient_aerial_altitude_max_blocks):
		push_error("[EntityDefinition] Invalid aerial altitude range for %s at %s" % [id, source])
		valid = false
	if not combat_targetable and experience_reward != 0:
		push_error("[EntityDefinition] Non-targetable entity %s rewards experience at %s" % [id, source])
		valid = false
	if hostile_to_player and not combat_targetable:
		push_error("[EntityDefinition] Hostile entity %s is not combat-targetable at %s" % [id, source])
		valid = false
	for block_id in ambient_spawn_floor_ids:
		if not BlockId.is_valid(block_id) or block_id in [BlockId.Type.AIR, BlockId.Type.WATER]:
			push_error("[EntityDefinition] Invalid spawn floor %d for %s at %s" % [block_id, id, source])
			valid = false
	return valid

func is_actor_compatible() -> bool:
	if actor_scene == null or behavior == null:
		return false
	var actor_root := actor_scene.instantiate()
	if actor_root == null:
		return false
	var compatible := (
		actor_root is EntityActor
		and (actor_root as EntityActor).supports_behavior(behavior)
		and (actor_root as EntityActor).has_valid_presentation()
		and (not combat_targetable or (actor_root as EntityActor).supports_player_hit_response())
	)
	actor_root.free()
	return compatible

func can_spawn_ambiently_on(block_id: int) -> bool:
	return block_id in ambient_spawn_floor_ids

func get_damage_response(damage_type: DamageTypeDefinition) -> int:
	assert(damage_type != null)
	for affinity in damage_affinities:
		if affinity.damage_type.id == damage_type.id:
			return affinity.response
	return DamageAffinityDefinition.Response.NEUTRAL
