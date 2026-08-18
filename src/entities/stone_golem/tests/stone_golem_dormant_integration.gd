extends SceneTree
const StoneGolemActorType := preload("res://entities/stone_golem/stone_golem_actor.gd")
const StoneGolemAnimationDriverType := preload("res://entities/stone_golem/stone_golem_animation_driver.gd")
const StoneGolemBrainType := preload("res://entities/stone_golem/stone_golem_brain.gd")

const FEET_Y: float = 2.0

var _failures: int = 0

func _init() -> void:
	call_deferred(&"_run")

func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("[stone_golem_dormant_integration] FAIL: %s" % message)

func _make_world() -> VoxelWorld:
	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var world := VoxelWorld.new(8, 16, 3, 4.0, block_catalog)
	for x in range(-8, 9):
		for z in range(-8, 9):
			world.height_map_dict[Vector2i(x, z)] = 1
			world.type_map_dict[Vector2i(x, z)] = BlockId.Type.GRASS
	return world

func _observation(player_position: Vector3) -> EntityTargetObservation:
	return EntityTargetObservation.create(
		player_position,
		player_position + Vector3(8.0, 10.0, 8.0),
		Vector3(-0.5, -0.5, -0.5),
		Vector3(1.0, 0.0, -1.0),
	)

func _run() -> void:
	var definition := load("res://entities/definitions/stone_golem.tres") as EntityDefinition
	_expect(definition != null and definition.validate(definition.resource_path), "Stone Golem definition was invalid")
	_expect(definition.id == &"stone_golem", "stable Stone Golem ID changed")
	_expect(is_equal_approx(definition.body_width, 1.2) and is_equal_approx(definition.body_height, 2.4), "Stone Golem body dimensions changed")
	_expect(definition.experience_reward == 30 and definition.ambient_max_active == 2, "Stone Golem reward or active cap changed")
	var actor := definition.actor_scene.instantiate() as StoneGolemActorType
	get_root().add_child(actor)
	actor.global_position = Vector3(0.5, FEET_Y, 0.5)
	actor.setup(81, definition, _make_world(), 8101, EntityNavigationLimits.new(32, 512, 2))
	actor.set_process(false)
	actor.on_ground = true
	actor.advance_visual_fade(actor.visual_fader.fade_in_seconds)
	_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "Stone Golem did not start dormant")
	var initial_position := actor.global_position
	for player_position in [Vector3(1.5, FEET_Y, 0.5), Vector3(16.5, FEET_Y, 0.5)]:
		actor.tick(0.5, _observation(player_position), Vector3(4.0, 0.0, 0.0), NavigationSearchBudget.new(2))
		_expect(actor.brain.state == StoneGolemBrainType.State.DORMANT, "player observation woke the dormant Stone Golem")
		_expect(actor.global_position.is_equal_approx(initial_position), "dormant Stone Golem moved")
	var animation := actor.animation_driver as StoneGolemAnimationDriverType
	animation.advance(0.1)
	_expect(animation.get_current_state() == StoneGolemAnimationDriverType.IDLE, "dormant Stone Golem did not present idle")
	actor.queue_free()
	for _frame_index in range(8):
		await process_frame
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_count == 0, "dormant integration ended with %d orphan nodes" % orphan_count)
	if _failures == 0:
		print("STONE_GOLEM_DORMANT PASS orphan=%d" % orphan_count)
		quit(0)
	else:
		print("STONE_GOLEM_DORMANT FAIL failures=%d" % _failures)
		quit(1)
