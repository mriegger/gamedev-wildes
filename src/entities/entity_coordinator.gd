extends Node3D
class_name EntityCoordinator

signal entity_melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile)

const SPAWN_INTERVAL_SECONDS: float = 2.0
const SPAWN_ATTEMPTS: int = 4
const MIN_SPAWN_DISTANCE: float = 18.0
const MAX_SPAWN_DISTANCE: float = 36.0
const DESPAWN_DISTANCE: float = 56.0
const SPATIAL_CELL_SIZE: float = 4.0
const SEPARATION_RADIUS: float = 1.2
const SEPARATION_SPEED: float = 1.25

var _catalog: EntityCatalog
var _voxel_world: VoxelWorld
var _position_ready: Callable
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _active: Dictionary = {}
var _spatial_index: EntitySpatialIndex = EntitySpatialIndex.new(SPATIAL_CELL_SIZE)
var _spawn_elapsed: float = 0.0
var _next_runtime_id: int = 1

func setup(p_catalog: EntityCatalog, p_voxel_world: VoxelWorld, world_seed: int, p_position_ready: Callable):
	assert(p_catalog != null and p_catalog.validate())
	assert(p_voxel_world != null)
	assert(p_position_ready.is_valid())
	_catalog = p_catalog
	_voxel_world = p_voxel_world
	_position_ready = p_position_ready
	_rng.seed = world_seed
	_spawn_elapsed = 0.0
	_spatial_index.clear()

func tick(delta: float, player_position: Vector3, time_of_day: float):
	assert(_catalog != null and _voxel_world != null)
	_despawn_distant(player_position)
	_refresh_spatial_index()
	var runtime_ids: Array = _active.keys()
	runtime_ids.sort()
	var separation_velocities: Dictionary = {}
	for runtime_id in runtime_ids:
		var actor := get_actor(runtime_id)
		if actor != null:
			separation_velocities[runtime_id] = _get_separation_velocity(actor)
	for runtime_id in runtime_ids:
		var actor := get_actor(runtime_id)
		if actor == null:
			continue
		actor.tick(delta, player_position, separation_velocities[runtime_id] as Vector3)
		_spatial_index.upsert(actor.runtime_id, actor.global_position, actor.get_world_bounds())
	_spawn_elapsed += delta
	if _spawn_elapsed < SPAWN_INTERVAL_SECONDS:
		return
	_spawn_elapsed = fmod(_spawn_elapsed, SPAWN_INTERVAL_SECONDS)
	var is_day := DayNightProfile.is_day_time(time_of_day)
	for definition in _catalog.definitions:
		if definition == null or _count_definition(definition.id) >= definition.max_active:
			continue
		if is_day != (definition.spawn_phase == EntityDefinition.SpawnPhase.DAY):
			continue
		if _try_spawn(definition, player_position):
			return

func _try_spawn(definition: EntityDefinition, player_position: Vector3) -> bool:
	for _attempt in range(SPAWN_ATTEMPTS):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(MIN_SPAWN_DISTANCE, MAX_SPAWN_DISTANCE)
		var x := int(floor(player_position.x + cos(angle) * distance))
		var z := int(floor(player_position.z + sin(angle) * distance))
		var feet_y := _find_spawn_y(definition, x, z)
		if feet_y == VoxelWorld.NO_SURFACE_Y:
			continue
		var spawn_position := Vector3(float(x) + 0.5, feet_y, float(z) + 0.5)
		var horizontal_offset := Vector2(spawn_position.x - player_position.x, spawn_position.z - player_position.z)
		var horizontal_distance_squared := horizontal_offset.length_squared()
		if horizontal_distance_squared < MIN_SPAWN_DISTANCE * MIN_SPAWN_DISTANCE or horizontal_distance_squared > MAX_SPAWN_DISTANCE * MAX_SPAWN_DISTANCE:
			continue
		if not bool(_position_ready.call(spawn_position)):
			continue
		var actor := definition.actor_scene.instantiate() as EntityActor
		if actor == null:
			push_error("[EntityCoordinator] Actor scene for %s must use EntityActor" % definition.id)
			return false
		var runtime_id := _next_runtime_id
		_next_runtime_id += 1
		_active[runtime_id] = actor
		add_child(actor)
		actor.global_position = spawn_position
		actor.setup(runtime_id, definition, _voxel_world, int(_rng.randi()))
		actor.melee_contact_reached.connect(_on_actor_melee_contact_reached)
		_spatial_index.upsert(runtime_id, actor.global_position, actor.get_world_bounds())
		return true
	return false

func _find_spawn_y(definition: EntityDefinition, x: int, z: int) -> float:
	for floor_y in range(_voxel_world.max_build_y - 1, -1, -1):
		var floor_id := _voxel_world.get_block_id_at(Vector3i(x, floor_y, z))
		if not definition.can_spawn_on(floor_id):
			continue
		var feet_y := floor_y + 1
		if _has_clearance(definition, x, feet_y, z):
			return float(feet_y)
	return VoxelWorld.NO_SURFACE_Y

func _has_clearance(definition: EntityDefinition, x: int, feet_y: int, z: int) -> bool:
	var required_height := ceili(definition.body_height)
	for y in range(feet_y, feet_y + required_height):
		if _voxel_world.is_solid(Vector3i(x, y, z)):
			return false
	return true

func _despawn_distant(player_position: Vector3):
	var max_distance_squared := DESPAWN_DISTANCE * DESPAWN_DISTANCE
	var to_remove: Array[int] = []
	for runtime_id in _active:
		var actor := _active[runtime_id] as EntityActor
		if not is_instance_valid(actor) or actor.global_position.distance_squared_to(player_position) > max_distance_squared or not bool(_position_ready.call(actor.global_position)):
			to_remove.append(runtime_id)
	for runtime_id in to_remove:
		_despawn(runtime_id)

func _despawn(runtime_id: int):
	if not _active.has(runtime_id):
		return
	var actor := _active[runtime_id] as EntityActor
	_active.erase(runtime_id)
	_spatial_index.remove(runtime_id)
	if is_instance_valid(actor):
		actor.queue_free()

func _count_definition(definition_id: StringName) -> int:
	var count := 0
	for actor in _active.values():
		if is_instance_valid(actor) and (actor as EntityActor).definition.id == definition_id:
			count += 1
	return count

func _refresh_spatial_index():
	for actor in _active.values():
		if is_instance_valid(actor):
			var entity := actor as EntityActor
			_spatial_index.upsert(entity.runtime_id, entity.global_position, entity.get_world_bounds())

func _get_separation_velocity(actor: EntityActor) -> Vector3:
	var separation := Vector3.ZERO
	for nearby_id in _spatial_index.query_nearby(actor.global_position, SEPARATION_RADIUS):
		if nearby_id == actor.runtime_id:
			continue
		var other := get_actor(nearby_id)
		if other == null:
			continue
		var offset := actor.global_position - other.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001:
			offset = Vector3.RIGHT if actor.runtime_id < other.runtime_id else Vector3.LEFT
			distance = 0.0
		var strength := 1.0 - distance / SEPARATION_RADIUS
		if strength > 0.0:
			separation += offset.normalized() * strength
	if separation.length_squared() > 1.0:
		separation = separation.normalized()
	return separation * SEPARATION_SPEED

func get_active_count() -> int:
	return _active.size()

func get_active_actors() -> Array[EntityActor]:
	var actors: Array[EntityActor] = []
	for actor in _active.values():
		if is_instance_valid(actor):
			actors.append(actor as EntityActor)
	return actors

func get_actor(runtime_id: int) -> EntityActor:
	var actor := _active.get(runtime_id) as EntityActor
	return actor if is_instance_valid(actor) else null

func record_melee_contact(contact: MeleeContact):
	var target := get_actor(contact.target_runtime_id)
	if target != null:
		target.record_melee_contact(contact.hit_direction)

func _on_actor_melee_contact_reached(source_runtime_id: int, profile: MeleeAttackProfile):
	entity_melee_contact_reached.emit(source_runtime_id, profile)

func shutdown():
	for runtime_id in _active.keys():
		_despawn(runtime_id)
	_active.clear()
	_spatial_index.clear()
	_catalog = null
	_voxel_world = null
	_position_ready = Callable()
