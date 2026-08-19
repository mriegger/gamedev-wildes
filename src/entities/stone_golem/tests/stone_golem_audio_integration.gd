extends SceneTree

const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAudioType := preload("res://entities/stone_golem/stone_golem_audio.gd")

const FEET_Y: float = 2.0

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_audio_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(8, 16, 3, 4.0, block_catalog)
	for x in range(-8, 9):
		for z in range(-8, 9):
			world.height_map_dict[Vector2i(x, z)] = 1
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _spawn_actor(definition: EntityDefinition, world: VoxelWorld, runtime_id: int) -> StoneGolemActorType:
	var actor := definition.actor_scene.instantiate() as StoneGolemActorType
	get_root().add_child(actor)
	actor.global_position = Vector3(float(runtime_id) * 3.0 + 0.5, FEET_Y, 0.5)
	actor.setup(runtime_id, definition, world, 9100 + runtime_id, EntityNavigationLimits.new(32, 512, 2))
	actor.set_process(false)
	actor.on_ground = true
	return actor

func _run() -> void:
	var definition := load("res://entities/definitions/stone_golem.tres") as EntityDefinition
	var world := _make_world()
	var actor := _spawn_actor(definition, world, 1)
	var audio := actor.get_node(actor.action_audio_path) as StoneGolemAudioType
	_expect(actor.has_valid_presentation(), "production Stone Golem rejected its audio presentation")
	_expect(audio != null and audio.profile != null and audio.profile.validate(), "Stone Golem audio profile was invalid")
	_expect(audio.profile.walk_streams.size() == 1, "Stone Golem did not register its walking sound")
	_expect(audio.profile.impact_streams.size() == 4, "Stone Golem did not register four hit impacts")
	_expect(audio.profile.death_streams.size() == 1, "Stone Golem did not register its death sound")
	_expect(audio.walk_player.bus == &"SFX" and audio.impact_player.bus == &"SFX" and audio.death_player.bus == &"SFX", "Stone Golem audio did not use the SFX bus")
	_expect(audio.walk_player is AudioStreamPlayer3D and audio.impact_player is AudioStreamPlayer3D and audio.death_player is AudioStreamPlayer3D, "Stone Golem audio was not positional")
	_expect(audio.walk_player.stream == null and audio.impact_player.stream == null and audio.death_player.stream == null, "Stone Golem audio began before an event")

	var animation := actor._stone_golem_animation
	var animator := animation.animator
	var walk_cycle := animator.profile.walk_cycle_seconds
	actor.velocity = Vector3(0.0, 0.0, actor.max_speed)
	animation.advance(walk_cycle * 0.49)
	_expect(audio.walk_player.stream == null, "walking sound played before the animated foot contact")
	animation.advance(walk_cycle * 0.02)
	_expect(audio.profile.walk_streams.has(audio.walk_player.stream), "gait contact did not select the walking sound")
	_expect(audio.walk_player.pitch_scale >= audio.profile.walk_pitch_min and audio.walk_player.pitch_scale <= audio.profile.walk_pitch_max, "walking pitch was outside its profile")
	animation.advance(walk_cycle * 0.2)
	audio.walk_player.stop()
	audio.walk_player.stream = null
	var paused_gait_position := animator.get_gait_cycle_position()
	actor.velocity = Vector3.ZERO
	animation.advance(walk_cycle * 2.0)
	_expect(audio.walk_player.stream == null, "stationary Stone Golem played a walking sound")
	_expect(is_equal_approx(animator.get_gait_cycle_position(), paused_gait_position), "stationary animation discarded its gait phase")
	actor.velocity = Vector3(0.0, 0.0, actor.max_speed)
	actor.on_ground = false
	animation.advance(walk_cycle * 2.0)
	_expect(audio.walk_player.stream == null, "airborne Stone Golem played a walking sound")
	_expect(is_equal_approx(animator.get_gait_cycle_position(), paused_gait_position), "airborne animation discarded its gait phase")
	actor.on_ground = true
	animation.advance(walk_cycle * 0.28)
	_expect(audio.walk_player.stream == null, "resumed walking sound played before the preserved foot contact")
	animation.advance(walk_cycle * 0.02)
	_expect(audio.profile.walk_streams.has(audio.walk_player.stream), "preserved foot contact did not resume walking audio")

	actor.record_melee_contact(Vector3.RIGHT)
	_expect(audio.profile.impact_streams.has(audio.impact_player.stream), "confirmed hit did not select a Stone Golem impact")
	_expect(audio.impact_player.pitch_scale >= audio.profile.impact_pitch_min and audio.impact_player.pitch_scale <= audio.profile.impact_pitch_max, "impact pitch was outside its profile")
	var first_impact := audio.impact_player.stream
	actor.record_melee_contact(Vector3.LEFT)
	_expect(audio.impact_player.stream != first_impact, "consecutive Stone Golem hits repeated the same impact")

	actor.begin_death_retirement()
	_expect(audio.profile.death_streams.has(audio.death_player.stream), "death retirement did not select the Stone Golem death sound")
	_expect(audio.death_player.pitch_scale >= audio.profile.death_pitch_min and audio.death_player.pitch_scale <= audio.profile.death_pitch_max, "death pitch was outside its profile")
	_expect(audio.walk_player.stream == null and audio.impact_player.stream == null, "death retained walking or hit audio")
	var death_pitch := audio.death_player.pitch_scale
	actor.begin_death_retirement()
	_expect(is_equal_approx(audio.death_player.pitch_scale, death_pitch), "repeated death restarted the Stone Golem death sound")
	actor.record_melee_contact(Vector3.FORWARD)
	_expect(audio.impact_player.stream == null, "dying Stone Golem accepted another hit impact")

	var despawning_actor := _spawn_actor(definition, world, 2)
	var despawning_audio := despawning_actor.get_node(despawning_actor.action_audio_path) as StoneGolemAudioType
	despawning_actor.velocity = Vector3(0.0, 0.0, despawning_actor.max_speed)
	despawning_actor._stone_golem_animation.advance(walk_cycle * 0.51)
	despawning_audio.play_impact()
	despawning_actor.begin_despawn_fade()
	_expect(
		despawning_audio.walk_player.stream == null
		and despawning_audio.impact_player.stream == null
		and despawning_audio.death_player.stream == null,
		"ordinary despawn retained Stone Golem audio",
	)

	var runtime := EntityRuntime.new()
	get_root().add_child(runtime)
	var catalog := load("res://entities/entity_catalog.tres") as EntityCatalog
	runtime.setup(catalog, world, 4, 4, EntityNavigationLimits.new(32, 512, 2))
	var suspend_requests: Array[EntitySpawnRequest] = [
		EntitySpawnRequest.new(&"stone_golem", Vector3(6.5, FEET_Y, 0.5), 9300),
	]
	var suspended_ids := runtime.try_spawn_batch(suspend_requests)
	_expect(suspended_ids == [1], "suspension fixture did not spawn its Stone Golem")
	var suspended_actor := runtime.get_actor(suspended_ids[0]) as StoneGolemActorType
	var suspended_animation := suspended_actor._stone_golem_animation
	var suspended_audio := suspended_actor.get_node(suspended_actor.action_audio_path) as StoneGolemAudioType
	suspended_actor.velocity = Vector3(0.0, 0.0, suspended_actor.max_speed)
	suspended_animation.advance(walk_cycle * 0.71)
	suspended_audio.walk_player.stop()
	suspended_audio.walk_player.stream = null
	var suspended_gait_position := suspended_animation.animator.get_gait_cycle_position()
	runtime.suspend()
	_expect(runtime.is_suspended() and not suspended_actor.is_processing(), "runtime suspension left Stone Golem presentation active")
	await process_frame
	await process_frame
	_expect(is_equal_approx(suspended_animation.animator.get_gait_cycle_position(), suspended_gait_position), "runtime suspension advanced the hidden Stone Golem gait")
	_expect(suspended_audio.walk_player.stream == null, "runtime suspension emitted a hidden Stone Golem footstep")
	runtime.resume()
	_expect(not runtime.is_suspended() and suspended_actor.is_processing(), "runtime resume did not reactivate Stone Golem presentation")
	suspended_actor.set_process(false)
	suspended_animation.advance(walk_cycle * 0.28)
	_expect(suspended_audio.walk_player.stream == null, "runtime resume emitted before the preserved foot contact")
	suspended_animation.advance(walk_cycle * 0.02)
	_expect(suspended_audio.profile.walk_streams.has(suspended_audio.walk_player.stream), "runtime resume did not preserve foot-contact timing")
	runtime.shutdown()
	runtime.queue_free()

	await create_timer(1.4).timeout
	audio.stop_audio()
	actor.free()
	despawning_actor.free()
	await process_frame
	await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "audio integration ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("STONE_GOLEM_AUDIO_INTEGRATION PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("STONE_GOLEM_AUDIO_INTEGRATION FAIL failures=%d" % _failures)
		quit(1)
