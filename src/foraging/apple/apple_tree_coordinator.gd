extends HarvestSource
class_name AppleTreeCoordinator

signal state_changed

const DECORATIVE_DROP_PERCENT: int = 50
const APPLE_TREE_CROP_ID: StringName = &"apple_tree"
const GROWTH_STAGE_DURATION_HOURS: float = AppleTreeState.GROWTH_DURATION_HOURS / 4.0
const TREE_TRUNK_HEIGHT: int = 4
const GROUND_OFFSETS: Array[Vector2] = [
	Vector2(0.78, 0.18),
	Vector2(-0.72, 0.28),
	Vector2(0.22, 0.82),
	Vector2(-0.18, -0.76),
	Vector2(0.65, -0.58),
	Vector2(-0.62, -0.55),
]
const DECORATIVE_OFFSETS: Array[Vector3] = [
	Vector3(1.50, 0.10, 0.18),
	Vector3(-1.50, 0.22, -0.12),
	Vector3(0.16, 0.36, 1.50),
	Vector3(-0.18, 0.05, -1.50),
	Vector3(1.50, 0.52, -0.48),
	Vector3(-1.50, 0.08, 0.52),
	Vector3(0.52, 0.62, 1.50),
	Vector3(-0.54, 0.28, -1.50),
	Vector3(1.50, 0.42, 1.50),
	Vector3(-1.50, 0.58, -1.50),
	Vector3(1.50, 0.16, -1.50),
	Vector3(-1.50, 0.34, 1.50),
	Vector3(1.50, 0.78, 0.72),
	Vector3(-1.50, 0.88, -0.70),
	Vector3(0.72, 0.72, -1.50),
	Vector3(1.50, 0.20, -0.95),
	Vector3(-1.50, 0.40, 0.98),
	Vector3(-0.96, 0.12, 1.50),
	Vector3(0.94, 0.56, -1.50),
	Vector3(1.50, 0.66, 1.05),
]

@export var definition: AppleTreeDefinition

var _voxel_world: VoxelWorld
var _chunk_manager: ChunkManager
var _clock: GameClock
var _world_seed: int
var _state := AppleTreeState.new()
var _model_bounds: AABB
var _foliage_mesh: BoxMesh
var _chunk_roots: Dictionary = {}
var _targets: Dictionary = {}
var _decorations_by_leaf: Dictionary = {}
var _new_fallen_sources: Dictionary = {}
var _fallen_by_chunk: Dictionary = {}
var _retained_by_chunk: Dictionary = {}
var _planted_by_chunk: Dictionary = {}
var _rendered_tree_records_by_chunk: Dictionary = {}
var _next_target_id: int = 1
var _revision: int = 0
var _committing_growth_tree: bool = false

func setup(
	voxel_world: VoxelWorld,
	chunk_manager: ChunkManager,
	world_seed: int,
	saved_state: Variant,
	item_catalog: ItemCatalog,
	clock: GameClock,
) -> bool:
	assert(voxel_world != null and chunk_manager != null and item_catalog != null and clock != null)
	assert(_voxel_world == null and _chunk_manager == null and _clock == null)
	_voxel_world = voxel_world
	_chunk_manager = chunk_manager
	_clock = clock
	_world_seed = world_seed
	if definition == null or not definition.validate(item_catalog) or not _state.restore(saved_state) or not _prepare_model_bounds() or not _prepare_foliage_mesh() or not _validate_planted_world_state():
		return false
	for tree_position in _state.get_retained_trees():
		if not _is_apple_tree(tree_position):
			return false
	_rebuild_fallen_index()
	_rebuild_retained_index()
	_rebuild_planted_index()
	_chunk_manager.chunk_loaded.connect(_on_chunk_loaded)
	_chunk_manager.chunk_unloaded.connect(_on_chunk_unloaded)
	_voxel_world.block_edit_committed.connect(_on_block_edit_committed)
	_clock.time_advanced.connect(_on_time_advanced)
	if _try_mature_ready_trees():
		_revision += 1
		_rebuild_planted_index()
	for coord in _chunk_manager.visible_chunks:
		_render_chunk(coord)
	return true

func snapshot() -> Dictionary:
	return _state.snapshot()

func supports_crop(crop_id: StringName) -> bool:
	return crop_id == APPLE_TREE_CROP_ID

func uses_world(voxel_world: VoxelWorld) -> bool:
	return _voxel_world == voxel_world

func prepare_plant(soil_position: Vector3i, crop_id: StringName) -> PreparedApplePlantChange:
	if not supports_crop(crop_id) or not _can_plant_at(soil_position):
		return null
	var expected_block_revisions: Dictionary = {soil_position: _voxel_world.get_revision(soil_position)}
	for position in _get_tree_cells(soil_position):
		expected_block_revisions[position] = _voxel_world.get_revision(position)
	return PreparedApplePlantChange.new(self, _revision, soil_position, expected_block_revisions)

func can_commit_prepared_plant(prepared: PreparedApplePlantChange) -> bool:
	if prepared == null or not prepared._is_for(self) or not prepared._is_prepared() or prepared._get_expected_revision() != _revision:
		return false
	var expected_block_revisions := prepared._get_expected_block_revisions()
	for position in expected_block_revisions:
		if _voxel_world.get_revision(position) != int(expected_block_revisions[position]):
			return false
	return _can_plant_at(prepared._get_soil_position())

func _commit_prepared_plant(prepared: PreparedApplePlantChange, emit_signal: bool = true) -> bool:
	if not can_commit_prepared_plant(prepared) or not _state.add_planted_seed(prepared._get_soil_position()):
		return false
	_revision += 1
	var marked := prepared._mark_committed(self)
	assert(marked)
	if emit_signal:
		var notified := _notify_prepared_plant(prepared)
		assert(notified)
	return true

func _notify_prepared_plant(prepared: PreparedApplePlantChange) -> bool:
	if prepared == null or not prepared._mark_notified(self):
		return false
	_rebuild_planted_index()
	_render_visible_chunk(ChunkCoord.world_to_chunk_vec3i(prepared._get_soil_position(), _voxel_world.chunk_size))
	state_changed.emit()
	return true

func validate_harvest_items(item_catalog: ItemCatalog) -> bool:
	return definition != null and definition.validate(item_catalog)

func find_harvest_target(ray_origin: Vector3, ray_direction: Vector3, max_distance: float) -> Dictionary:
	if ray_direction.is_zero_approx() or max_distance <= 0.0:
		return {}
	var nearest_id := -1
	var nearest_distance := max_distance
	for target_id in _targets:
		var record := _targets[target_id] as Dictionary
		var hit = (record["bounds"] as AABB).intersects_ray(ray_origin, ray_direction)
		if not hit is Vector3:
			continue
		var distance := ray_origin.distance_to(hit)
		if distance <= nearest_distance:
			nearest_id = target_id
			nearest_distance = distance
	if nearest_id < 0:
		return {}
	return {"target_id": nearest_id, "distance": nearest_distance}

func get_harvest_target_bounds(target_id: int) -> AABB:
	assert(_targets.has(target_id))
	return (_targets[target_id] as Dictionary)["bounds"] as AABB

func get_harvest_target_ids() -> Array[int]:
	var target_ids: Array[int] = []
	for target_id in _targets:
		target_ids.append(int(target_id))
	return target_ids

func can_harvest_target(target_id: int) -> bool:
	return _targets.has(target_id)

func get_harvest_item_ids(target_id: int) -> Array[StringName]:
	assert(_targets.has(target_id))
	return [definition.apple_item_id]

func prepare_harvest_target(target_id: int) -> PreparedHarvestChange:
	if not can_harvest_target(target_id):
		return null
	var record := _targets[target_id] as Dictionary
	return PreparedAppleHarvestChange.new(
		self,
		_revision,
		target_id,
		record["tree_position"] as Vector3i,
		int(record["slot_index"]),
		int(record["decorative_index"]),
		get_harvest_item_ids(target_id),
	)

func can_commit_prepared_harvest(prepared: PreparedHarvestChange) -> bool:
	var apple_change := prepared as PreparedAppleHarvestChange
	if (
		apple_change == null
		or not apple_change._is_for(self)
		or not apple_change._is_prepared()
		or apple_change._get_expected_revision() != _revision
		or not _targets.has(apple_change._get_target_id())
	):
		return false
	var record := _targets[apple_change._get_target_id()] as Dictionary
	var tree_position := apple_change._get_tree_position()
	var slot_index := apple_change._get_slot_index()
	var decorative_index := apple_change._get_decorative_index()
	return (
		record["tree_position"] as Vector3i == tree_position
		and int(record["slot_index"]) == slot_index
		and int(record["decorative_index"]) == decorative_index
		and (
			_state.has_fallen_apple(tree_position, decorative_index)
			if decorative_index >= 0
			else not _state.is_collected(tree_position, slot_index)
		)
		and get_harvest_item_ids(apple_change._get_target_id()) == apple_change.get_harvest_item_ids()
	)

func _commit_prepared_harvest(
	prepared: PreparedHarvestChange,
	emit_signal: bool = true,
) -> bool:
	if not can_commit_prepared_harvest(prepared):
		return false
	var apple_change := prepared as PreparedAppleHarvestChange
	var record := _targets[apple_change._get_target_id()] as Dictionary
	var tree_position := apple_change._get_tree_position()
	var decorative_index := apple_change._get_decorative_index()
	var collected := (
		_state.collect_fallen_apple(tree_position, decorative_index)
		if decorative_index >= 0
		else _state.collect(tree_position, apple_change._get_slot_index())
	)
	assert(collected)
	if decorative_index >= 0:
		_remove_fallen_from_index(record["chunk"] as Vector2i, tree_position, decorative_index)
	var apple := record["node"] as Node3D
	_targets.erase(apple_change._get_target_id())
	apple.queue_free()
	_revision += 1
	var marked := apple_change._mark_committed(self)
	assert(marked)
	if emit_signal:
		var notified := _notify_prepared_harvest(apple_change)
		assert(notified)
	return true

func _notify_prepared_harvest(prepared: PreparedHarvestChange) -> bool:
	if prepared == null or not prepared._mark_notified(self):
		return false
	state_changed.emit()
	return true

func get_harvest_prompt() -> String:
	return "Left Click  Pick Up Apple"

func _prepare_model_bounds() -> bool:
	if definition == null or definition.apple_scene == null:
		return false
	var model := definition.apple_scene.instantiate() as Node3D
	if model == null:
		return false
	var bounds: Array[AABB] = []
	_collect_mesh_bounds(model, Transform3D.IDENTITY, bounds)
	model.free()
	if bounds.is_empty():
		return false
	_model_bounds = bounds[0]
	for index in range(1, bounds.size()):
		_model_bounds = _model_bounds.merge(bounds[index])
	return maxf(_model_bounds.size.x, maxf(_model_bounds.size.y, _model_bounds.size.z)) > 0.0

func _collect_mesh_bounds(node: Node, parent_transform: Transform3D, output: Array[AABB]) -> void:
	for child in node.get_children():
		var child_transform := parent_transform
		if child is Node3D:
			child_transform = parent_transform * (child as Node3D).transform
		if child is MeshInstance3D:
			output.append(child_transform * (child as MeshInstance3D).get_aabb())
		_collect_mesh_bounds(child, child_transform, output)

func _prepare_foliage_mesh() -> bool:
	var leaves := _voxel_world.block_catalog.get_definition(BlockId.Type.LEAVES)
	if leaves == null or leaves.side_texture == null:
		return false
	var material := StandardMaterial3D.new()
	material.albedo_texture = leaves.side_texture
	material.albedo_color = definition.foliage_tint
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	_foliage_mesh = BoxMesh.new()
	_foliage_mesh.size = Vector3.ONE * 1.004
	_foliage_mesh.material = material
	return true

func _on_chunk_loaded(coord: Vector2i) -> void:
	_render_chunk(coord)

func _on_chunk_unloaded(coord: Vector2i) -> void:
	_unload_chunk(coord)

func _on_block_edit_committed(edit: BlockEdit) -> void:
	if _committing_growth_tree:
		return
	var planted_state_changed := false
	for soil_position in _state.get_planted_soil_positions():
		if _state.is_tree_mature(soil_position) or edit.pos not in [soil_position, soil_position + Vector3i.UP]:
			continue
		if _voxel_world.get_block_id_at(soil_position) == BlockId.Type.FARMLAND_DRY and _voxel_world.get_block_id_at(soil_position + Vector3i.UP) == BlockId.Type.AIR:
			continue
		planted_state_changed = _state.remove_planted_seed(soil_position) or planted_state_changed
	var coord := ChunkCoord.world_to_chunk_vec3i(edit.pos, _voxel_world.chunk_size)
	var rerender_coords: Dictionary = {coord: true}
	if edit.is_mine() and edit.old_id in [BlockId.Type.LOG, BlockId.Type.LEAVES]:
		_retain_edited_trees(edit.pos, coord)
	if edit.is_mine() and edit.old_id == BlockId.Type.LEAVES:
		for affected_coord in _try_drop_decorative_apple(edit.pos):
			rerender_coords[affected_coord] = true
	var matured := _try_mature_ready_trees()
	if planted_state_changed or matured:
		_revision += 1
		_rebuild_planted_index()
		for planted_coord in _planted_by_chunk:
			rerender_coords[planted_coord] = true
		state_changed.emit()
	for affected_coord in rerender_coords:
		_render_visible_chunk(affected_coord)

func _render_chunk(coord: Vector2i) -> void:
	_unload_chunk(coord)
	var generated_tree_blocks := _get_nearby_generated_tree_blocks(coord)
	var tree_blocks := _get_nearby_tree_blocks(coord)
	if tree_blocks.is_empty() and not _fallen_by_chunk.has(coord) and not _retained_by_chunk.has(coord) and not _planted_by_chunk.has(coord):
		return
	var root := Node3D.new()
	root.name = "AppleTrees_%d_%d" % [coord.x, coord.y]
	add_child(root)
	_chunk_roots[coord] = root
	var tree_positions: Dictionary = {}
	for tree_position in _find_tree_positions(generated_tree_blocks):
		if ChunkCoord.world_to_chunk_vec3i(tree_position, _voxel_world.chunk_size) == coord:
			tree_positions[tree_position] = true
	for tree_position in _retained_by_chunk.get(coord, []) as Array:
		tree_positions[tree_position] = true
	for soil_position in _planted_by_chunk.get(coord, []) as Array:
		if _state.is_tree_mature(soil_position):
			tree_positions[soil_position + Vector3i.UP] = true
		else:
			_render_growing_tree(root, soil_position)
	var sorted_tree_positions: Array = tree_positions.keys()
	sorted_tree_positions.sort()
	var rendered_records: Array = []
	for tree_position in sorted_tree_positions:
		if _is_apple_tree(tree_position) or _state.has_planted_tree(tree_position):
			var top_log_y := _get_top_log_y(tree_position, tree_blocks)
			_render_apple_tree(root, coord, tree_position, top_log_y, tree_blocks)
			rendered_records.append({"tree_position": tree_position, "top_log_y": top_log_y})
	if not rendered_records.is_empty():
		_rendered_tree_records_by_chunk[coord] = rendered_records
	_render_fallen_apples(root, coord)
	if root.get_child_count() == 0:
		_chunk_roots.erase(coord)
		root.queue_free()

func _render_apple_tree(root: Node3D, coord: Vector2i, tree_position: Vector3i, top_log_y: int, tree_blocks: Dictionary) -> void:
	var random := RandomNumberGenerator.new()
	random.seed = _stable_seed(tree_position, 17)
	var ground_offsets := GROUND_OFFSETS.duplicate()
	_shuffle(ground_offsets, random)
	var ground_count := random.randi_range(definition.minimum_ground_apples, definition.maximum_ground_apples)
	for slot_index in range(ground_count):
		if _state.is_collected(tree_position, slot_index):
			continue
		var offset := ground_offsets[slot_index] as Vector2
		var apple_position := Vector3(tree_position.x + 0.5 + offset.x, 0.0, tree_position.z + 0.5 + offset.y)
		var ground_height := _voxel_world.get_terrain_height(floori(apple_position.x), floori(apple_position.z))
		if ground_height < 0:
			ground_height = tree_position.y - 1
		apple_position.y = float(ground_height + 1)
		_spawn_ground_apple(root, coord, tree_position, slot_index, apple_position)
	_spawn_foliage(root, tree_position, top_log_y, tree_blocks)
	var decorative_offsets := DECORATIVE_OFFSETS.duplicate()
	_shuffle(decorative_offsets, random)
	for index in range(definition.decorative_apple_count):
		var offset := decorative_offsets[index] as Vector3
		var position := Vector3(tree_position.x + 0.5, top_log_y + 1.45, tree_position.z + 0.5) + offset
		var supporting_leaf := _get_supporting_leaf(tree_position, top_log_y, offset)
		if int(tree_blocks.get(supporting_leaf, BlockId.Type.AIR)) != BlockId.Type.LEAVES:
			continue
		var apple_radius := definition.decorative_apple_size * 0.5
		position.y = clampf(position.y, supporting_leaf.y + apple_radius, supporting_leaf.y + 1.0 - apple_radius)
		var apple := _spawn_apple_model(root, position, definition.decorative_apple_size, false)
		apple.name = "DecorativeApple_%d" % index
		if not _decorations_by_leaf.has(supporting_leaf):
			_decorations_by_leaf[supporting_leaf] = []
		(_decorations_by_leaf[supporting_leaf] as Array).append({
			"chunk": coord,
			"tree_position": tree_position,
			"decorative_index": index,
			"position": position,
		})

func _spawn_foliage(root: Node3D, tree_position: Vector3i, top_log_y: int, tree_blocks: Dictionary) -> void:
	for raw_position in tree_blocks:
		var position := raw_position as Vector3i
		if int(tree_blocks[position]) != BlockId.Type.LEAVES:
			continue
		if absi(position.x - tree_position.x) > 1 or absi(position.z - tree_position.z) > 1:
			continue
		if position.y < top_log_y + 1 or position.y > top_log_y + 3:
			continue
		var foliage := MeshInstance3D.new()
		foliage.name = "AppleFoliage_%d_%d_%d" % [position.x, position.y, position.z]
		foliage.mesh = _foliage_mesh
		foliage.position = Vector3(position) + Vector3.ONE * 0.5
		foliage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(foliage)

func _spawn_ground_apple(root: Node3D, coord: Vector2i, tree_position: Vector3i, slot_index: int, position: Vector3) -> void:
	var holder := _spawn_apple_model(root, position, definition.ground_apple_size, true)
	holder.name = "GroundApple_%d" % slot_index
	_register_harvest_target(root, holder, coord, tree_position, slot_index, -1)

func _render_fallen_apples(root: Node3D, coord: Vector2i) -> void:
	for record in _fallen_by_chunk.get(coord, []) as Array:
		var position := record["position"] as Vector3
		var tree_position := record["tree_position"] as Vector3i
		var decorative_index := int(record["decorative_index"])
		var holder := _spawn_apple_model(root, position, definition.ground_apple_size, true)
		holder.name = "FallenApple_%d_%d_%d_%d" % [tree_position.x, tree_position.y, tree_position.z, decorative_index]
		_register_harvest_target(root, holder, coord, tree_position, -1, decorative_index)
		var key := _fallen_key(tree_position, decorative_index)
		if _new_fallen_sources.has(key):
			var target_position := holder.position
			holder.position = _new_fallen_sources[key] as Vector3
			var tween := holder.create_tween()
			tween.set_trans(Tween.TRANS_QUAD)
			tween.set_ease(Tween.EASE_IN)
			tween.tween_property(holder, ^"position", target_position, 0.45)
			tween.finished.connect(_play_fall_impact.bind(holder, tree_position, decorative_index))
			_new_fallen_sources.erase(key)

func _play_fall_impact(holder: Node3D, tree_position: Vector3i, decorative_index: int) -> void:
	if not is_instance_valid(holder):
		return
	var player := AudioStreamPlayer3D.new()
	var stream_index := _stable_seed(tree_position, 3000 + decorative_index) % definition.fall_impact_streams.size()
	player.stream = definition.fall_impact_streams[stream_index]
	player.bus = &"SFX"
	player.volume_db = -8.0
	player.unit_size = 3.5
	player.max_distance = 18.0
	holder.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

func _register_harvest_target(root: Node3D, holder: Node3D, coord: Vector2i, tree_position: Vector3i, slot_index: int, decorative_index: int) -> void:
	var target_id := _next_target_id
	_next_target_id += 1
	var coordinator_transform := global_transform if is_inside_tree() else transform
	var bounds := coordinator_transform * root.transform * holder.transform * _calculate_holder_bounds(holder)
	_targets[target_id] = {
		"bounds": bounds.grow(0.08),
		"chunk": coord,
		"tree_position": tree_position,
		"slot_index": slot_index,
		"decorative_index": decorative_index,
		"node": holder,
	}

func _try_drop_decorative_apple(leaf_position: Vector3i) -> Array[Vector2i]:
	if not _decorations_by_leaf.has(leaf_position):
		return []
	var records := (_decorations_by_leaf[leaf_position] as Array).duplicate()
	records.sort_custom(func(first: Dictionary, second: Dictionary): return int(first["decorative_index"]) < int(second["decorative_index"]))
	var affected_coords: Dictionary = {}
	for record in records:
		affected_coords[(record as Dictionary)["chunk"] as Vector2i] = true
		var tree_position := record["tree_position"] as Vector3i
		var decorative_index := int(record["decorative_index"])
		if not _should_drop_decorative_apple(tree_position, decorative_index):
			continue
		var source_position := record["position"] as Vector3
		var drop_position := _get_drop_position(tree_position, source_position)
		if _state.add_fallen_apple(tree_position, decorative_index, drop_position):
			var drop_coord := ChunkCoord.world_to_chunk(drop_position, _voxel_world.chunk_size)
			_add_fallen_to_index(drop_coord, tree_position, decorative_index, drop_position)
			affected_coords[drop_coord] = true
			if _chunk_manager.visible_chunks.has(drop_coord):
				_new_fallen_sources[_fallen_key(tree_position, decorative_index)] = source_position
			_revision += 1
			state_changed.emit()
			break
	var coords: Array[Vector2i] = []
	for affected_coord in affected_coords:
		coords.append(affected_coord as Vector2i)
	return coords

func _rebuild_fallen_index() -> void:
	_fallen_by_chunk.clear()
	for record in _state.get_fallen_apples():
		var position := record["position"] as Vector3
		var coord := ChunkCoord.world_to_chunk(position, _voxel_world.chunk_size)
		_add_fallen_to_index(coord, record["tree_position"] as Vector3i, int(record["decorative_index"]), position)

func _rebuild_retained_index() -> void:
	_retained_by_chunk.clear()
	for tree_position in _state.get_retained_trees():
		_add_retained_to_index(tree_position)

func _rebuild_planted_index() -> void:
	_planted_by_chunk.clear()
	for soil_position in _state.get_planted_soil_positions():
		var coord := ChunkCoord.world_to_chunk_vec3i(soil_position, _voxel_world.chunk_size)
		if not _planted_by_chunk.has(coord):
			_planted_by_chunk[coord] = []
		(_planted_by_chunk[coord] as Array).append(soil_position)

func _on_time_advanced(hours: float) -> void:
	var previous_stages: Dictionary = {}
	for soil_position in _state.get_planted_soil_positions():
		if not _state.is_tree_mature(soil_position):
			previous_stages[soil_position] = _get_growth_stage(_state.get_growth_hours(soil_position))
	var advanced := _state.advance_planted_trees(hours)
	var matured := _try_mature_ready_trees()
	if not advanced and not matured:
		return
	var affected_coords: Dictionary = {}
	for soil_position in _state.get_planted_soil_positions():
		if _state.is_tree_mature(soil_position):
			if matured:
				affected_coords[ChunkCoord.world_to_chunk_vec3i(soil_position, _voxel_world.chunk_size)] = true
			continue
		var previous_stage := int(previous_stages.get(soil_position, -1))
		if previous_stage != _get_growth_stage(_state.get_growth_hours(soil_position)):
			affected_coords[ChunkCoord.world_to_chunk_vec3i(soil_position, _voxel_world.chunk_size)] = true
	if affected_coords.is_empty():
		return
	_revision += 1
	for coord in affected_coords:
		_render_visible_chunk(coord)
	state_changed.emit()

func _try_mature_ready_trees() -> bool:
	var matured := false
	for soil_position in _state.get_planted_soil_positions():
		if _state.is_tree_mature(soil_position) or not is_equal_approx(_state.get_growth_hours(soil_position), AppleTreeState.GROWTH_DURATION_HOURS):
			continue
		if not _try_place_mature_tree(soil_position):
			continue
		var marked := _state.mark_tree_mature(soil_position)
		assert(marked)
		matured = true
	return matured

func _try_place_mature_tree(soil_position: Vector3i) -> bool:
	var prepared_changes: Array[PreparedVoxelWorldChange] = []
	var cells := _get_tree_cells(soil_position)
	for position in cells:
		var prepared := _voxel_world.prepare_place_block(position, int(cells[position]))
		if prepared == null:
			return false
		prepared_changes.append(prepared)
	_committing_growth_tree = true
	var committed := _voxel_world.commit_prepared_changes(prepared_changes)
	_committing_growth_tree = false
	return committed

func _can_plant_at(soil_position: Vector3i) -> bool:
	if _voxel_world == null or _state.has_planted_seed(soil_position) or _voxel_world.is_edit_protected(soil_position):
		return false
	if _voxel_world.get_block_id_at(soil_position) != BlockId.Type.FARMLAND_DRY:
		return false
	var cells := _get_tree_cells(soil_position)
	if cells.is_empty():
		return false
	for position in cells:
		if _voxel_world.is_edit_protected(position) or _voxel_world.get_block_id_at(position) != BlockId.Type.AIR:
			return false
	for planted_soil_position in _state.get_planted_soil_positions():
		for position in _get_tree_cells(planted_soil_position):
			if cells.has(position):
				return false
	return true

func _get_tree_cells(soil_position: Vector3i) -> Dictionary:
	var root_position := soil_position + Vector3i.UP
	if root_position.y + TREE_TRUNK_HEIGHT + 2 >= _voxel_world.max_build_y:
		return {}
	var cells: Dictionary = {}
	for y_offset in range(TREE_TRUNK_HEIGHT):
		cells[root_position + Vector3i(0, y_offset, 0)] = BlockId.Type.LOG
	var leaves_y := root_position.y + TREE_TRUNK_HEIGHT
	for y_offset in range(2):
		for x_offset in range(-1, 2):
			for z_offset in range(-1, 2):
				cells[Vector3i(root_position.x + x_offset, leaves_y + y_offset, root_position.z + z_offset)] = BlockId.Type.LEAVES
	cells[Vector3i(root_position.x, leaves_y + 2, root_position.z)] = BlockId.Type.LEAVES
	return cells

func _get_growth_stage(growth_hours: float) -> int:
	return mini(floori(growth_hours / GROWTH_STAGE_DURATION_HOURS), 3)

func _render_growing_tree(root: Node3D, soil_position: Vector3i) -> void:
	var stage := _get_growth_stage(_state.get_growth_hours(soil_position))
	var holder := Node3D.new()
	holder.name = "AppleSapling_%d_%d_%d" % [soil_position.x, soil_position.y, soil_position.z]
	holder.position = Vector3(soil_position) + Vector3(0.5, 1.0, 0.5)
	root.add_child(holder)
	if stage == 0:
		_add_growth_box(holder, "Seed", Vector3(0.12, 0.06, 0.08), Vector3(0.0, 0.03, 0.0), Color(0.34, 0.20, 0.10))
		return
	var heights: Array[float] = [0.0, 0.28, 0.62, 1.18]
	var crown_sizes: Array[float] = [0.0, 0.22, 0.48, 0.82]
	var height := heights[stage]
	_add_growth_box(holder, "Trunk", Vector3(0.10 + stage * 0.035, height, 0.10 + stage * 0.035), Vector3(0.0, height * 0.5, 0.0), Color(0.42, 0.25, 0.12))
	var crown_size := crown_sizes[stage]
	_add_growth_box(holder, "Leaves", Vector3(crown_size, crown_size * 0.72, crown_size), Vector3(0.0, height, 0.0), Color(0.33, 0.68, 0.25))

func _add_growth_box(parent: Node3D, node_name: String, size: Vector3, position: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	mesh.material = material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)

func _validate_planted_world_state() -> bool:
	for soil_position in _state.get_planted_soil_positions():
		if not _state.is_tree_mature(soil_position) and _voxel_world.get_block_id_at(soil_position) != BlockId.Type.FARMLAND_DRY:
			return false
	return true

func _render_visible_chunk(coord: Vector2i) -> void:
	if _chunk_manager.visible_chunks.has(coord):
		_render_chunk(coord)

func _add_retained_to_index(tree_position: Vector3i) -> void:
	var coord := ChunkCoord.world_to_chunk_vec3i(tree_position, _voxel_world.chunk_size)
	if not _retained_by_chunk.has(coord):
		_retained_by_chunk[coord] = []
	(_retained_by_chunk[coord] as Array).append(tree_position)

func _retain_edited_trees(position: Vector3i, coord: Vector2i) -> void:
	var retained := false
	for x_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			for record in _rendered_tree_records_by_chunk.get(coord + Vector2i(x_offset, z_offset), []) as Array:
				var tree_position := (record as Dictionary)["tree_position"] as Vector3i
				var top_log_y := int((record as Dictionary)["top_log_y"])
				if _state.has_planted_tree(tree_position) or not _tree_contains_block(tree_position, top_log_y, position) or not _state.retain_tree(tree_position):
					continue
				_add_retained_to_index(tree_position)
				retained = true
	if retained:
		state_changed.emit()

func _tree_contains_block(tree_position: Vector3i, top_log_y: int, position: Vector3i) -> bool:
	if position.x == tree_position.x and position.z == tree_position.z and position.y >= tree_position.y and position.y <= top_log_y:
		return true
	return absi(position.x - tree_position.x) <= 1 and absi(position.z - tree_position.z) <= 1 and position.y >= top_log_y + 1 and position.y <= top_log_y + 3

func _add_fallen_to_index(coord: Vector2i, tree_position: Vector3i, decorative_index: int, position: Vector3) -> void:
	if not _fallen_by_chunk.has(coord):
		_fallen_by_chunk[coord] = []
	(_fallen_by_chunk[coord] as Array).append({
		"tree_position": tree_position,
		"decorative_index": decorative_index,
		"position": position,
	})

func _remove_fallen_from_index(coord: Vector2i, tree_position: Vector3i, decorative_index: int) -> void:
	var records := _fallen_by_chunk.get(coord, []) as Array
	for index in range(records.size() - 1, -1, -1):
		var record := records[index] as Dictionary
		if record["tree_position"] == tree_position and int(record["decorative_index"]) == decorative_index:
			records.remove_at(index)
	if records.is_empty():
		_fallen_by_chunk.erase(coord)

func _should_drop_decorative_apple(tree_position: Vector3i, decorative_index: int) -> bool:
	return _stable_seed(tree_position, 1000 + decorative_index) % 100 < DECORATIVE_DROP_PERCENT

func _get_drop_position(tree_position: Vector3i, source_position: Vector3) -> Vector3:
	var tree_center := Vector2(tree_position.x + 0.5, tree_position.z + 0.5)
	var source_planar := Vector2(source_position.x, source_position.z)
	var support_sample := source_planar.move_toward(tree_center, definition.ground_apple_size * 0.5)
	var ground_y := _voxel_world.get_terrain_surface_top(floori(support_sample.x), floori(support_sample.y))
	if ground_y == VoxelSpace.NO_SURFACE_Y:
		ground_y = float(tree_position.y)
	return Vector3(source_position.x, ground_y, source_position.z)

func _get_nearby_tree_blocks(coord: Vector2i) -> Dictionary:
	var tree_blocks := _get_nearby_generated_tree_blocks(coord)
	for x_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			var nearby_coord := coord + Vector2i(x_offset, z_offset)
			for soil_position in _planted_by_chunk.get(nearby_coord, []) as Array:
				if not _state.is_tree_mature(soil_position):
					continue
				var planted_cells := _get_tree_cells(soil_position)
				for position in planted_cells:
					var block_id := int(planted_cells[position])
					if _voxel_world.get_block_id_at(position) == block_id:
						tree_blocks[position] = block_id
	return tree_blocks

func _get_nearby_generated_tree_blocks(coord: Vector2i) -> Dictionary:
	var tree_blocks: Dictionary = {}
	for x_offset in range(-1, 2):
		for z_offset in range(-1, 2):
			tree_blocks.merge(_voxel_world.get_tree_blocks_for_chunk(coord + Vector2i(x_offset, z_offset)))
	return tree_blocks

func _find_tree_positions(tree_blocks: Dictionary) -> Array[Vector3i]:
	var positions: Dictionary = {}
	var canopy_candidates: Dictionary = {}
	for raw_position in tree_blocks:
		var position := raw_position as Vector3i
		var block_id := int(tree_blocks[position])
		if block_id == BlockId.Type.LOG:
			var surface_y := _voxel_world.get_terrain_surface_top(position.x, position.z)
			if surface_y != VoxelSpace.NO_SURFACE_Y:
				positions[Vector3i(position.x, roundi(surface_y), position.z)] = true
		elif block_id == BlockId.Type.LEAVES:
			for x_offset in range(-1, 2):
				for z_offset in range(-1, 2):
					var candidate := Vector3i(position.x + x_offset, position.y, position.z + z_offset)
					canopy_candidates[candidate] = int(canopy_candidates.get(candidate, 0)) + 1
	for raw_candidate in canopy_candidates:
		if int(canopy_candidates[raw_candidate]) < 7:
			continue
		var candidate := raw_candidate as Vector3i
		var surface_y := _voxel_world.get_terrain_surface_top(candidate.x, candidate.z)
		if surface_y != VoxelSpace.NO_SURFACE_Y:
			positions[Vector3i(candidate.x, roundi(surface_y), candidate.z)] = true
	var sorted_positions: Array[Vector3i] = []
	for position in positions:
		sorted_positions.append(position as Vector3i)
	sorted_positions.sort()
	return sorted_positions

func _get_top_log_y(tree_position: Vector3i, tree_blocks: Dictionary) -> int:
	var top_log_y := tree_position.y
	var lowest_canopy_y := _voxel_world.max_build_y
	for raw_position in tree_blocks:
		var position := raw_position as Vector3i
		if absi(position.x - tree_position.x) > 1 or absi(position.z - tree_position.z) > 1:
			continue
		var block_id := int(tree_blocks[position])
		if block_id == BlockId.Type.LEAVES:
			lowest_canopy_y = mini(lowest_canopy_y, position.y)
		elif block_id == BlockId.Type.LOG and position.x == tree_position.x and position.z == tree_position.z:
			top_log_y = maxi(top_log_y, position.y)
	return lowest_canopy_y - 1 if lowest_canopy_y < _voxel_world.max_build_y else top_log_y

func _get_supporting_leaf(tree_position: Vector3i, top_log_y: int, offset: Vector3) -> Vector3i:
	return Vector3i(tree_position.x + clampi(roundi(offset.x), -1, 1), top_log_y + 1, tree_position.z + clampi(roundi(offset.z), -1, 1))

func _fallen_key(tree_position: Vector3i, decorative_index: int) -> String:
	return "%d,%d,%d,%d" % [tree_position.x, tree_position.y, tree_position.z, decorative_index]

func _spawn_apple_model(root: Node3D, position: Vector3, target_size: float, rest_on_surface: bool) -> Node3D:
	var holder := Node3D.new()
	holder.position = position
	root.add_child(holder)
	var model := definition.apple_scene.instantiate() as Node3D
	var source_size := maxf(_model_bounds.size.x, maxf(_model_bounds.size.y, _model_bounds.size.z))
	var model_scale := target_size / source_size
	model.scale = Vector3.ONE * model_scale
	var center := _model_bounds.get_center()
	model.position = Vector3(-center.x * model_scale, -center.y * model_scale, -center.z * model_scale)
	if rest_on_surface:
		model.position.y = -_model_bounds.position.y * model_scale
	holder.add_child(model)
	return holder

func _calculate_holder_bounds(holder: Node3D) -> AABB:
	var bounds: Array[AABB] = []
	_collect_mesh_bounds(holder, Transform3D.IDENTITY, bounds)
	var combined := bounds[0]
	for index in range(1, bounds.size()):
		combined = combined.merge(bounds[index])
	return combined

func _unload_chunk(coord: Vector2i) -> void:
	_rendered_tree_records_by_chunk.erase(coord)
	if _chunk_roots.has(coord):
		(_chunk_roots[coord] as Node3D).queue_free()
		_chunk_roots.erase(coord)
	for target_id in _targets.keys():
		if (_targets[target_id] as Dictionary)["chunk"] == coord:
			_targets.erase(target_id)
	for leaf_position in _decorations_by_leaf.keys():
		var retained: Array = []
		for record in _decorations_by_leaf[leaf_position] as Array:
			if (record as Dictionary)["chunk"] != coord:
				retained.append(record)
		if retained.is_empty():
			_decorations_by_leaf.erase(leaf_position)
		else:
			_decorations_by_leaf[leaf_position] = retained

func _is_apple_tree(tree_position: Vector3i) -> bool:
	return _stable_seed(tree_position, 5) % 10000 < roundi(definition.tree_fraction * 10000.0)

func _stable_seed(tree_position: Vector3i, salt: int) -> int:
	return absi(("%d:%d:%d:%d:%d" % [_world_seed, tree_position.x, tree_position.y, tree_position.z, salt]).hash())

func _shuffle(values: Array, random: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := random.randi_range(0, index)
		var value = values[index]
		values[index] = values[swap_index]
		values[swap_index] = value

func _exit_tree() -> void:
	if _clock != null and _clock.time_advanced.is_connected(_on_time_advanced):
		_clock.time_advanced.disconnect(_on_time_advanced)
	if _chunk_manager != null:
		if _chunk_manager.chunk_loaded.is_connected(_on_chunk_loaded):
			_chunk_manager.chunk_loaded.disconnect(_on_chunk_loaded)
		if _chunk_manager.chunk_unloaded.is_connected(_on_chunk_unloaded):
			_chunk_manager.chunk_unloaded.disconnect(_on_chunk_unloaded)
	if _voxel_world != null and _voxel_world.block_edit_committed.is_connected(_on_block_edit_committed):
		_voxel_world.block_edit_committed.disconnect(_on_block_edit_committed)
