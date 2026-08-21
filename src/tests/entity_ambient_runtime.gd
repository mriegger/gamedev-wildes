extends SceneTree

const FLOOR_Y: int = 1
const FEET_Y: float = 2.0
const TEST_RADIUS: int = 48
const FIXED_DELTA: float = 0.1
const SIMULATION_TICKS: int = 80

var _failures: int = 0
var _melee_contacts: int = 0
var _radial_contacts: int = 0
var _defeats: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[entity_ambient_runtime] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(16, 32, 5, 8.0, block_catalog)
	for x in range(-TEST_RADIUS, TEST_RADIUS + 1):
		for z in range(-TEST_RADIUS, TEST_RADIUS + 1):
			world.height_map_dict[Vector2i(x, z)] = FLOOR_Y
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _on_melee_contact(_runtime_id: int, _profile: MeleeAttackProfile) -> void:
	_melee_contacts += 1

func _on_radial_contact(_runtime_id: int, _profile: MeleeAttackProfile) -> void:
	_radial_contacts += 1

func _on_defeated(_defeat: EntityDefeat) -> void:
	_defeats += 1

func _test_target_free_species_and_audio() -> void:
	var runtime := EntityRuntime.new()
	root.add_child(runtime)
	var mirror_runtime := EntityRuntime.new()
	root.add_child(mirror_runtime)
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	var world := _make_world()
	runtime.setup(catalog, world, 32, 16, EntityNavigationLimits.new(48, 2048, 3), EntityRuntime.Mode.PRESENTATION)
	mirror_runtime.setup(catalog, _make_world(), 32, 16, EntityNavigationLimits.new(48, 2048, 3), EntityRuntime.Mode.PRESENTATION)
	runtime.entity_melee_contact_reached.connect(_on_melee_contact)
	runtime.entity_radial_contact_reached.connect(_on_radial_contact)
	runtime.entity_defeated.connect(_on_defeated)
	var definition_ids: Array[StringName] = [
		&"zombie",
		&"sheep",
		&"bird",
		&"skeleton",
		&"slime_large",
		&"watcher",
		&"stone_golem",
	]
	var requests: Array[EntitySpawnRequest] = []
	for index in definition_ids.size():
		var feet_position := Vector3(float(index * 6 - 18) + 0.5, FEET_Y, 0.5)
		if definition_ids[index] == &"bird":
			feet_position.y = FEET_Y + 10.0
		requests.append(EntitySpawnRequest.new(definition_ids[index], feet_position, 4100 + index))
	var runtime_ids := runtime.try_spawn_batch(requests)
	var mirror_runtime_ids := mirror_runtime.try_spawn_batch(requests)
	_expect(runtime_ids.size() == definition_ids.size(), "target-free fixture did not spawn every species")
	_expect(mirror_runtime_ids.size() == definition_ids.size(), "deterministic mirror did not spawn every species")
	_expect(runtime.get_child_count() == runtime.get_active_count(), "presentation-only runtime retained an unused actor pool")
	_expect(mirror_runtime.get_child_count() == mirror_runtime.get_active_count(), "deterministic mirror retained an unused actor pool")
	if runtime_ids.size() != definition_ids.size() or mirror_runtime_ids.size() != definition_ids.size():
		runtime.shutdown()
		runtime.free()
		mirror_runtime.shutdown()
		mirror_runtime.free()
		return
	var initial_positions: Dictionary = {}
	for runtime_id in runtime_ids:
		var actor := runtime.get_actor(runtime_id)
		actor.set_process(false)
		initial_positions[runtime_id] = actor.global_position
		_expect(actor.health_bar == null, "%s created gameplay health presentation" % actor.definition.id)
		if actor.vocalizations != null:
			_expect(not actor.vocalizations.is_processing(), "%s vocalizations ignored disabled audio" % actor.definition.id)
			actor.vocalizations._remaining_seconds = 0.0
			actor.vocalizations._process(0.0)
			_expect(not actor.vocalizations.playing and actor.vocalizations.stream == null, "%s vocalized while audio was disabled" % actor.definition.id)
	for _tick_index in SIMULATION_TICKS:
		runtime.tick_ambient(FIXED_DELTA)
		mirror_runtime.tick_ambient(FIXED_DELTA)
		for actor in runtime.get_active_actors():
			actor.animation_driver.advance(FIXED_DELTA)
		for actor in mirror_runtime.get_active_actors():
			actor.animation_driver.advance(FIXED_DELTA)
	var zombie := runtime.get_actor(runtime_ids[0]) as ZombieActor
	var sheep := runtime.get_actor(runtime_ids[1]) as SheepActor
	var bird := runtime.get_actor(runtime_ids[2]) as BirdActor
	var skeleton := runtime.get_actor(runtime_ids[3]) as SkeletonActor
	var slime := runtime.get_actor(runtime_ids[4]) as SlimeActor
	var watcher := runtime.get_actor(runtime_ids[5]) as WatcherActor
	var golem := runtime.get_actor(runtime_ids[6]) as StoneGolemActor
	_expect(zombie.brain.state == GroundMeleeEnemyBrain.State.WANDER, "ambient Zombie left wander state")
	_expect(sheep.brain.state != SheepBrain.State.FLEE, "ambient Sheep entered flee state")
	_expect(bird.brain != null, "ambient Bird lost its normal behavior")
	_expect(skeleton.brain.state == SkeletonBrain.State.ROAM, "ambient Skeleton entered a camera-dependent state")
	_expect(slime.brain.state == SlimeBrain.State.WANDER and not slime.is_attached(), "ambient Slime entered chase or attachment state")
	_expect(watcher.brain.state == WatcherBrain.State.WANDER and not watcher.is_aggressive(), "ambient Watcher became hostile")
	_expect(watcher.get_teleport_sequence() == 0, "ambient Watcher requested a teleport")
	_expect(golem.brain.state == StoneGolemBrain.State.DORMANT, "ambient Stone Golem woke up")
	_expect(golem.global_position.is_equal_approx(initial_positions[golem.runtime_id] as Vector3), "ambient Stone Golem moved")
	for index in runtime_ids.size():
		var actor := runtime.get_actor(runtime_ids[index])
		var mirror_actor := mirror_runtime.get_actor(mirror_runtime_ids[index])
		_expect(actor.global_position.is_equal_approx(mirror_actor.global_position), "%s ambient movement was not deterministic" % actor.definition.id)
		_expect(runtime.try_apply_damage(actor.runtime_id, 1.0) == null, "%s accepted damage in presentation-only mode" % actor.definition.id)
		_expect(not runtime.try_apply_knockback(actor.runtime_id, Vector3.RIGHT, 4.0), "%s accepted knockback in presentation-only mode" % actor.definition.id)
	_expect(slime.attach(0), "ambient attachment guard fixture did not attach the Slime")
	slime.tick_ambient(0.0, Vector3.ZERO, NavigationSearchBudget.new(1))
	_expect(not slime.is_attached(), "ambient Slime retained an attachment")
	_expect(not slime.commit_initial_attachment_contact(), "ambient Slime retained a pending attachment contact")
	_expect(not (bird.animation_driver as BirdAnimationDriver)._wing_flap_audio.playing, "ambient Bird played wing audio while muted")
	var golem_audio := golem._action_audio as StoneGolemAudio
	golem_audio.play_impact()
	_expect(golem_audio.impact_player.stream == null and not golem_audio.impact_player.playing, "ambient Stone Golem played action audio while muted")
	_expect(_melee_contacts == 0, "ambient ticks emitted melee contacts")
	_expect(_radial_contacts == 0, "ambient ticks emitted radial contacts")
	_expect(_defeats == 0, "ambient ticks defeated an entity")
	var overflow := runtime.try_spawn_batch([
		EntitySpawnRequest.new(&"slime_large", Vector3(24.5, FEET_Y, 20.5), 91821),
	])
	_expect(overflow.is_empty(), "ambient runtime exceeded its population-cost bound")
	runtime.shutdown()
	runtime.free()
	mirror_runtime.shutdown()
	mirror_runtime.free()

func _run() -> void:
	var orphan_before := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_test_target_free_species_and_audio()
	await process_frame
	await process_frame
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == orphan_before, "ambient runtime changed orphan count from %d to %d" % [orphan_before, orphan_after])
	if _failures == 0:
		print("ENTITY_AMBIENT_RUNTIME PASS")
		quit(0)
	else:
		print("ENTITY_AMBIENT_RUNTIME FAIL failures=%d" % _failures)
		quit(1)
