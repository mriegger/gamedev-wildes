extends SceneTree

var _errors: Array[String] = []

func _init():
	print("[mining_break_particles] starting")
	call_deferred("_run")

func _expect(condition: bool, message: String):
	if not condition:
		_errors.append(message)
		print("[mining_break_particles] FAIL: %s" % message)

func _finish():
	var orphan_after := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_expect(orphan_after == 0, "orphan leaked %d" % orphan_after)
	if _errors.is_empty():
		print("MINING_BREAK_PARTICLES PASS orphan=%d" % orphan_after)
		quit(0)
	else:
		print("MINING_BREAK_PARTICLES FAIL %s" % str(_errors))
		quit(1)

func _run():
	var particles_scene := load("res://mining/presentation/mining_break_particles.tscn") as PackedScene
	_expect(particles_scene != null, "particle scene load failed")
	var particles := particles_scene.instantiate() as MiningBreakParticles
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
		_expect(emitter.amount == 1, "%s amount expected 1 got %d" % [child.name, emitter.amount])
		_expect(is_equal_approx(emitter.lifetime, 0.3), "%s lifetime expected 0.30 got %f" % [child.name, emitter.lifetime])
		_expect(emitter.direction.is_equal_approx(Vector3.UP), "%s direction was %s" % [child.name, emitter.direction])
		_expect(emitter.gravity.is_equal_approx(Vector3(0, -1.5, 0)), "%s gravity was %s" % [child.name, emitter.gravity])
		_expect(is_equal_approx(emitter.initial_velocity_min, 1.1), "%s minimum velocity changed" % child.name)
		_expect(is_equal_approx(emitter.initial_velocity_max, 1.5), "%s maximum velocity changed" % child.name)
		_expect(emitter.color_ramp.get_color(0).is_equal_approx(Color.WHITE), "%s fade ramp changed" % child.name)
		_expect(emitter.mesh != null, "%s mesh missing" % child.name)
		_expect((emitter.mesh as QuadMesh).size.is_equal_approx(Vector2(1.5, 1.5)), "%s size changed" % child.name)
		var material := emitter.mesh.surface_get_material(0) as StandardMaterial3D
		_expect(material != null and material.albedo_texture != null, "%s texture missing" % child.name)

	var block_catalog := load("res://blocks/block_catalog.tres") as BlockCatalog
	var voxel_world := VoxelWorld.new(20, 36, 5, 100.0, block_catalog)
	var tint_palette := MiningParticleTintPalette.new(block_catalog)
	particles.setup(voxel_world, tint_palette)
	var placement := voxel_world.try_place_block(Vector3i(1, 8, 3), BlockId.Type.DIRT)
	_expect(placement.is_success(), "test placement failed")
	for child in emitters:
		_expect(not (child as CPUParticles3D).emitting, "%s played for placement" % child.name)
	var terrain_pos := Vector3i(4, 5, 4)
	var terrain_column := Vector2i(terrain_pos.x, terrain_pos.z)
	voxel_world.height_map_dict[terrain_column] = terrain_pos.y
	voxel_world.type_map_dict[terrain_column] = BlockId.Type.GRASS
	var terrain_edits := voxel_world.try_mine_block(terrain_pos)
	_expect(terrain_edits.size() == 1 and (terrain_edits[0] as BlockEdit).is_success(), "terrain mining failed")
	var first := particles.get_node("Dirt01") as CPUParticles3D
	_expect(first.emitting, "first emitter did not play")
	_expect(first.global_position.is_equal_approx(Vector3(4.5, 5.5, 4.5)), "removal position was %s" % first.global_position)
	_expect(first.color.is_equal_approx(tint_palette.get_tint(BlockId.Type.GRASS)), "terrain removal tint was %s" % first.color)
	_expect(not (particles.get_node("Dirt02") as CPUParticles3D).emitting, "terrain removal spawned more than one particle")
	_expect(not (particles.get_node("Dirt03") as CPUParticles3D).emitting, "terrain removal spawned more than one particle")

	for child in emitters:
		(child as CPUParticles3D).emitting = false
	var failed_edits := voxel_world.try_mine_block(Vector3i(100, 100, 100))
	_expect(failed_edits.size() == 1 and not (failed_edits[0] as BlockEdit).is_success(), "invalid mining unexpectedly succeeded")
	var torch_pos := Vector3i(2, 8, 3)
	voxel_world.restore_block_edits({torch_pos: BlockId.Type.TORCH}, {})
	var torch_edits := voxel_world.try_mine_block(torch_pos)
	_expect(torch_edits.size() == 1 and (torch_edits[0] as BlockEdit).is_success(), "torch mining failed")
	for child in emitters:
		_expect(not (child as CPUParticles3D).emitting, "%s played for failed or torch mining" % child.name)

	particles.queue_free()
	for _frame_index in range(10):
		await process_frame
	call_deferred("_finish")
