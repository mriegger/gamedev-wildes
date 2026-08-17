extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[mining_hit_particles] starting")
	call_deferred("_run")

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
		print("[mining_hit_particles] FAIL: %s" % message)

func _finish():
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d" % orphan_after)
	if _errors.is_empty():
		print("MINING_HIT_PARTICLES PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("MINING_HIT_PARTICLES FAIL %s" % str(_errors))
		quit(1)

func _average_texture_color(texture: Texture2D) -> Color:
	var image := texture.get_image()
	var rgb_sum := Vector3.ZERO
	var weight: float = 0.0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			rgb_sum += Vector3(pixel.r, pixel.g, pixel.b) * pixel.a
			weight += pixel.a
	return Color(rgb_sum.x / weight, rgb_sum.y / weight, rgb_sum.z / weight, 1.0)

func _run():
	var player_scene := load("res://player/player.tscn") as PackedScene
	var particles_scene := load("res://mining/presentation/mining_hit_particles.tscn") as PackedScene
	_expect(player_scene != null, "player scene load failed")
	_expect(particles_scene != null, "particle scene load failed")
	var player := player_scene.instantiate() as PlayerMotor
	var particles := particles_scene.instantiate() as MiningHitParticles
	root.add_child(player)
	root.add_child(particles)
	await process_frame

	var emitters: Array[Node] = particles.get_children()
	_expect(emitters.size() == 3, "expected three pooled emitters got %d" % emitters.size())
	for child in emitters:
		var emitter := child as CPUParticles3D
		_expect(emitter != null, "%s is not CPUParticles3D" % child.name)
		if emitter == null:
			continue
		_expect(emitter.one_shot, "%s is not one-shot" % child.name)
		_expect(emitter.amount == 8, "%s amount expected 8 got %d" % [child.name, emitter.amount])
		_expect(is_equal_approx(emitter.lifetime, 0.28), "%s lifetime expected 0.28 got %f" % [child.name, emitter.lifetime])
		_expect(emitter.mesh is BoxMesh, "%s does not use voxel flecks" % child.name)
		_expect((emitter.mesh as BoxMesh).size.is_equal_approx(Vector3(0.08, 0.08, 0.08)), "%s size changed" % child.name)

	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var voxel_world := VoxelWorld.new(20, 36, 5, 100.0, block_catalog)
	var dirt_target := Vector3i(1, 2, 3)
	var stone_target := Vector3i(2, 2, 3)
	voxel_world.restore_block_edits({dirt_target: BlockId.Type.DIRT, stone_target: BlockId.Type.STONE}, {})
	var interactor := player.interactor
	interactor.voxel_space = voxel_world
	var tint_palette := MiningParticleTintPalette.new(block_catalog)
	particles.setup(player.animation_driver, interactor, tint_palette)
	player.animation_driver.mining_impact.emit()
	for child in emitters:
		_expect(not (child as CPUParticles3D).emitting, "%s played without an active target" % child.name)

	interactor.is_mining = true
	interactor.target_has = true
	interactor.can_primary_target = true
	interactor.mine_target = dirt_target
	interactor.target_block = interactor.mine_target
	interactor.last_ray_normal = Vector3i.RIGHT
	player.animation_driver.mining_impact.emit()
	var first := particles.get_node("Burst01") as CPUParticles3D
	_expect(first.emitting, "first emitter did not play")
	_expect(first.global_position.is_equal_approx(Vector3(2.06, 2.5, 3.5)), "impact position was %s" % first.global_position)
	_expect(first.direction.is_equal_approx(Vector3.RIGHT), "impact direction was %s" % first.direction)
	_expect(first.color.is_equal_approx(_average_texture_color(block_catalog.get_definition(BlockId.Type.DIRT).bottom_texture)), "dirt tint was %s" % first.color)
	_expect(not (particles.get_node("Burst02") as CPUParticles3D).emitting, "impact used more than one pooled emitter")
	_expect(not (particles.get_node("Burst03") as CPUParticles3D).emitting, "impact used more than one pooled emitter")
	interactor.mine_target = stone_target
	interactor.target_block = interactor.mine_target
	player.animation_driver.mining_impact.emit()
	var second := particles.get_node("Burst02") as CPUParticles3D
	_expect(second.color.is_equal_approx(_average_texture_color(block_catalog.get_definition(BlockId.Type.STONE).bottom_texture)), "stone tint was %s" % second.color)

	particles.queue_free()
	player.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish")
