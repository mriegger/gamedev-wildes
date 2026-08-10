extends Resource
class_name EntityDefinition

enum SpawnPhase {
	DAY,
	NIGHT,
}

@export var id: StringName
@export var actor_scene: PackedScene
@export var behavior: EntityBehaviorDefinition
@export_range(0.1, 4.0, 0.01) var body_width: float = 0.6
@export_range(0.1, 4.0, 0.01) var body_height: float = 1.8
@export var spawn_phase: SpawnPhase = SpawnPhase.NIGHT
@export_range(1, 64, 1) var max_active: int = 1
@export var spawn_floor_ids: Array[int] = []

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
	if actor_scene != null and behavior != null and not is_actor_compatible():
		push_error("[EntityDefinition] Actor scene and behavior are incompatible for %s at %s" % [id, source])
		valid = false
	if body_width <= 0.0 or body_height <= 0.0:
		push_error("[EntityDefinition] Invalid body dimensions for %s at %s" % [id, source])
		valid = false
	if max_active < 1:
		push_error("[EntityDefinition] Invalid active cap for %s at %s" % [id, source])
		valid = false
	if spawn_floor_ids.is_empty():
		push_error("[EntityDefinition] Missing spawn floors for %s at %s" % [id, source])
		valid = false
	for block_id in spawn_floor_ids:
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
	)
	actor_root.free()
	return compatible

func can_spawn_on(block_id: int) -> bool:
	return block_id in spawn_floor_ids
