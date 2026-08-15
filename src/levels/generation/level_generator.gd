extends RefCounted
class_name LevelGenerator

const FNV_OFFSET_BASIS_32: int = 2166136261
const FNV_PRIME_32: int = 16777619
const UINT32_MASK: int = 0xffffffff
const NEIGHBORS: Array[Vector3i] = [
	Vector3i.LEFT,
	Vector3i.RIGHT,
	Vector3i.DOWN,
	Vector3i.UP,
	Vector3i.FORWARD,
	Vector3i.BACK,
]

class AssemblyState:
	var cells: Dictionary = {}
	var placed_modules: Array[LevelPlacedModule] = []
	var torches: Array[LevelTorchPlacement] = []
	var frontiers: Array[Dictionary] = []
	var spawn_cell: Vector3i
	var spawn_facing: LevelSocketDefinition.Direction
	var return_door_cell: Vector3i
	var return_door_facing: LevelSocketDefinition.Direction
	var bounds_min: Vector3i
	var bounds_max: Vector3i

	func copy() -> AssemblyState:
		var copied := AssemblyState.new()
		copied.cells = cells.duplicate()
		copied.placed_modules.assign(placed_modules)
		copied.torches.assign(torches)
		copied.frontiers.assign(frontiers)
		copied.spawn_cell = spawn_cell
		copied.spawn_facing = spawn_facing
		copied.return_door_cell = return_door_cell
		copied.return_door_facing = return_door_facing
		copied.bounds_min = bounds_min
		copied.bounds_max = bounds_max
		return copied

var _catalog: LevelCatalog
var _definition: LevelDefinition
var _rng: RandomNumberGenerator
var _explored_states: int
var _search_limit: int
var _expansion_candidates_by_direction: Dictionary = {}
var _cap_candidates_by_direction: Dictionary = {}

func generate(catalog: LevelCatalog, level_id: StringName, world_seed: int, entrance_id: StringName, entrance_coordinate: Vector3i) -> LevelGenerationResult:
	if catalog == null or not catalog.validate():
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.INVALID_CATALOG, "Level catalog validation failed")
	if not catalog.has_level(level_id):
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.UNKNOWN_LEVEL, "Unknown level ID: %s" % level_id)
	_catalog = catalog
	_definition = catalog.get_level(level_id)
	_explored_states = 0
	_search_limit = mini(_definition.maximum_explored_states, LevelDefinition.HARD_MAX_EXPLORED_STATES)
	_build_candidate_tables()
	var seed_value := derive_seed(world_seed, entrance_id, entrance_coordinate)
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	var target_module_count := _rng.randi_range(_definition.minimum_module_count, _definition.maximum_module_count)
	var state := _create_initial_state(_catalog.get_module(_definition.start_module_id))
	if state == null:
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.INVALID_LAYOUT, "Start module exceeds the configured bounds")
	var assembled := _assemble(state, target_module_count)
	if assembled == null:
		if _explored_states >= _search_limit:
			return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.SEARCH_LIMIT_REACHED, "Level assembly explored %d candidate states" % _explored_states)
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.NO_LAYOUT, "No valid %d-module layout was found" % target_module_count)
	if not _validate_finished_state(assembled, target_module_count):
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.INVALID_LAYOUT, "Assembled level failed reachability validation")
	return LevelGenerationResult.make_success(_make_layout(assembled, seed_value, target_module_count))

static func derive_seed(world_seed: int, entrance_id: StringName, entrance_coordinate: Vector3i) -> int:
	var identity := "%d|%s|%d,%d,%d" % [world_seed, entrance_id, entrance_coordinate.x, entrance_coordinate.y, entrance_coordinate.z]
	var hash_value := FNV_OFFSET_BASIS_32
	for byte in identity.to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * FNV_PRIME_32) & UINT32_MASK
	return hash_value

func _create_initial_state(module: LevelModuleDefinition) -> AssemblyState:
	var state := AssemblyState.new()
	var origin := Vector3i(-module.spawn_marker.cell.x, 0, -module.spawn_marker.cell.z)
	var placement := LevelPlacedModule.new(module, origin, 0)
	_write_placement(state, placement, _transformed_cells(placement))
	state.spawn_cell = placement.world_cell(module.spawn_marker.cell)
	state.spawn_facing = placement.world_direction(module.spawn_marker.facing)
	state.return_door_cell = placement.world_cell(module.return_door_marker.cell)
	state.return_door_facing = placement.world_direction(module.return_door_marker.facing)
	if not _fits_extent(state.bounds_min, state.bounds_max):
		return null
	return state

func _assemble(state: AssemblyState, target_module_count: int) -> AssemblyState:
	while _explored_states < _search_limit:
		var explored_before_attempt := _explored_states
		var assembled := _assemble_attempt(state.copy(), target_module_count)
		if assembled != null:
			return assembled
		if _explored_states == explored_before_attempt:
			return null
	return null

func _assemble_attempt(state: AssemblyState, target_module_count: int) -> AssemblyState:
	while not state.frontiers.is_empty():
		var required_frontier_count := _required_frontier_count(state.frontiers)
		var minimum_finished_count := state.placed_modules.size() + required_frontier_count
		if minimum_finished_count > target_module_count:
			return null
		if state.placed_modules.size() == target_module_count:
			if required_frontier_count > 0 or not _seal_optional_frontiers(state):
				return null
			break
		var use_caps := minimum_finished_count == target_module_count
		var placed := false
		for frontier_index in _ordered_frontier_indices(state.frontiers):
			var frontier := state.frontiers[frontier_index]
			var required_direction := LevelSocketDefinition.opposite(frontier["direction"] as LevelSocketDefinition.Direction)
			var candidates_by_direction := _cap_candidates_by_direction if use_caps else _expansion_candidates_by_direction
			var candidates := candidates_by_direction[required_direction] as Array[Dictionary]
			var frontier_profile := frontier["aperture_profile"] as Array[Vector2i]
			for candidate in _weighted_candidate_order(_matching_candidates(candidates, frontier_profile)):
				if _explored_states >= _search_limit:
					return null
				_explored_states += 1
				var module := candidate["module"] as LevelModuleDefinition
				var next_required_count := required_frontier_count
				if bool(frontier["requires_connection"]):
					next_required_count -= 1
				var connected_socket := candidate["socket"] as LevelSocketDefinition
				for next_socket in module.sockets:
					if next_socket.socket_id != connected_socket.socket_id and next_socket.requires_connection():
						next_required_count += 1
				var next_minimum_count := state.placed_modules.size() + 1 + next_required_count
				if next_minimum_count > target_module_count:
					continue
				var next_state := _try_place(state, frontier_index, candidate)
				if next_state == null:
					continue
				state = next_state
				placed = true
				break
			if placed:
				break
		if not placed:
			return null
	if state.placed_modules.size() == target_module_count:
		return state
	return null

func _required_frontier_count(frontiers: Array[Dictionary]) -> int:
	var count := 0
	for frontier in frontiers:
		if bool(frontier["requires_connection"]):
			count += 1
	return count

func _seal_optional_frontiers(state: AssemblyState) -> bool:
	for frontier in state.frontiers:
		if bool(frontier["requires_connection"]):
			return false
		var fill_block_id := int(frontier["unused_fill_block_id"])
		if not StructureCell.is_structure_solid(fill_block_id):
			return false
		for cell in frontier["aperture_cells"] as Array[Vector3i]:
			if not state.cells.has(cell) or int(state.cells[cell]) != StructureCell.AIR:
				return false
	for frontier in state.frontiers:
		var fill_block_id := int(frontier["unused_fill_block_id"])
		for cell in frontier["aperture_cells"] as Array[Vector3i]:
			state.cells[cell] = fill_block_id
	state.frontiers.clear()
	return true

func _ordered_frontier_indices(frontiers: Array[Dictionary]) -> Array[int]:
	var indices: Array[int] = []
	indices.resize(frontiers.size())
	for index in indices.size():
		indices[index] = index
	indices.sort_custom(func(a: int, b: int) -> bool:
		return _frontier_key(frontiers[a]) < _frontier_key(frontiers[b])
	)
	if indices.size() > 1:
		var offset := _rng.randi_range(0, indices.size() - 1)
		var rotated: Array[int] = []
		for index in indices.size():
			rotated.append(indices[(index + offset) % indices.size()])
		return rotated
	return indices

func _frontier_key(frontier: Dictionary) -> String:
	var cell := frontier["cell"] as Vector3i
	return "%+05d:%+03d:%+05d:%d:%s:%s" % [cell.x, cell.y, cell.z, int(frontier["direction"]), frontier["module_id"], frontier["socket_id"]]

func _build_candidate_tables() -> void:
	_expansion_candidates_by_direction.clear()
	_cap_candidates_by_direction.clear()
	for required_direction in range(LevelSocketDefinition.Direction.size()):
		_expansion_candidates_by_direction[required_direction] = _build_candidates(_definition.expansion_module_ids, required_direction as LevelSocketDefinition.Direction)
		_cap_candidates_by_direction[required_direction] = _build_candidates(_definition.cap_module_ids, required_direction as LevelSocketDefinition.Direction)

func _build_candidates(module_ids: Array[StringName], required_direction: LevelSocketDefinition.Direction) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for module_id in module_ids:
		var module := _catalog.get_module(module_id)
		for rotation in range(4):
			for socket in module.sockets:
				var rotated_direction := LevelSocketDefinition.rotate(socket.direction, rotation)
				if rotated_direction != required_direction:
					continue
				var rotated_aperture: Array[Vector3i] = []
				for cell in module.socket_aperture_cells(socket):
					rotated_aperture.append(module.rotate_cell(cell, rotation))
				candidates.append({
					"module": module,
					"rotation": rotation,
					"socket": socket,
					"aperture_cells": rotated_aperture,
					"aperture_profile": LevelSocketAperture.normalized_profile(rotated_aperture, rotated_direction),
					"key": "%s:%d:%s" % [module.module_id, rotation, socket.socket_id],
					"weight": module.weight,
				})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["key"]) < String(b["key"])
	)
	return candidates

func _matching_candidates(candidates: Array[Dictionary], profile: Array[Vector2i]) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for candidate in candidates:
		if candidate["aperture_profile"] as Array[Vector2i] == profile:
			matching.append(candidate)
	return matching

func _weighted_candidate_order(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = []
	remaining.assign(candidates)
	var ordered: Array[Dictionary] = []
	while not remaining.is_empty():
		var total_weight := 0.0
		for candidate in remaining:
			total_weight += float(candidate["weight"])
		var selection := _rng.randf() * total_weight
		var selected_index := remaining.size() - 1
		for index in remaining.size():
			selection -= float(remaining[index]["weight"])
			if selection <= 0.0:
				selected_index = index
				break
		ordered.append(remaining[selected_index])
		remaining.remove_at(selected_index)
	return ordered

func _try_place(state: AssemblyState, frontier_index: int, candidate: Dictionary) -> AssemblyState:
	var frontier := state.frontiers[frontier_index]
	var module := candidate["module"] as LevelModuleDefinition
	var socket := candidate["socket"] as LevelSocketDefinition
	var rotation := int(candidate["rotation"])
	var frontier_direction := frontier["direction"] as LevelSocketDefinition.Direction
	var frontier_aperture := frontier["aperture_cells"] as Array[Vector3i]
	var rotated_aperture := candidate["aperture_cells"] as Array[Vector3i]
	var target_aperture: Array[Vector3i] = []
	for cell in frontier_aperture:
		target_aperture.append(cell + LevelSocketDefinition.vector_for(frontier_direction))
	var origin := _minimum_cell(target_aperture) - _minimum_cell(rotated_aperture)
	var connected_aperture: Array[Vector3i] = []
	for cell in rotated_aperture:
		connected_aperture.append(origin + cell)
	if not _same_cell_set(target_aperture, connected_aperture):
		return null
	var placement := LevelPlacedModule.new(module, origin, rotation)
	var transformed_cells := _transformed_cells(placement)
	for cell in transformed_cells:
		if state.cells.has(cell):
			return null
	if not _has_only_connected_air_adjacency(state, transformed_cells, frontier_aperture, frontier_direction):
		return null
	var candidate_min := state.bounds_min
	var candidate_max := state.bounds_max
	for cell in transformed_cells:
		candidate_min = candidate_min.min(cell)
		candidate_max = candidate_max.max(cell)
	if not _fits_extent(candidate_min, candidate_max):
		return null
	state.frontiers.remove_at(frontier_index)
	_write_placement(state, placement, transformed_cells, socket.socket_id)
	return state

func _transformed_cells(placement: LevelPlacedModule) -> Dictionary:
	var transformed: Dictionary = {}
	var module := placement.definition
	for y in module.size.y:
		for z in module.size.z:
			for x in module.size.x:
				var local_cell := Vector3i(x, y, z)
				var value := module.cell_at(local_cell)
				if value == StructureCell.VOID:
					continue
				transformed[placement.world_cell(local_cell)] = value
	return transformed

func _has_only_connected_air_adjacency(
	state: AssemblyState,
	transformed_cells: Dictionary,
	frontier_aperture: Array[Vector3i],
	frontier_direction: LevelSocketDefinition.Direction,
) -> bool:
	var connected_neighbors: Dictionary = {}
	var outward := LevelSocketDefinition.vector_for(frontier_direction)
	for frontier_cell in frontier_aperture:
		connected_neighbors[frontier_cell + outward] = frontier_cell
	for cell in transformed_cells:
		if int(transformed_cells[cell]) != StructureCell.AIR:
			continue
		var transformed_cell := cell as Vector3i
		for offset in NEIGHBORS:
			var neighbor: Vector3i = transformed_cell + offset
			if int(state.cells.get(neighbor, StructureCell.VOID)) != StructureCell.AIR:
				continue
			if not connected_neighbors.has(transformed_cell) or connected_neighbors[transformed_cell] != neighbor:
				return false
	return true

func _write_placement(state: AssemblyState, placement: LevelPlacedModule, transformed_cells: Dictionary, connected_socket_id: StringName = &"") -> void:
	if state.placed_modules.is_empty():
		var first_cell := transformed_cells.keys()[0] as Vector3i
		state.bounds_min = first_cell
		state.bounds_max = first_cell
	for cell in transformed_cells:
		state.cells[cell] = transformed_cells[cell]
		state.bounds_min = state.bounds_min.min(cell)
		state.bounds_max = state.bounds_max.max(cell)
	state.placed_modules.append(placement)
	for socket in placement.definition.sockets:
		if socket.socket_id == connected_socket_id:
			continue
		var world_aperture := placement.world_socket_aperture(socket)
		var world_direction := placement.world_direction(socket.direction)
		state.frontiers.append({
			"module_id": placement.definition.module_id,
			"socket_id": socket.socket_id,
			"cell": placement.world_cell(socket.cell),
			"direction": world_direction,
			"aperture_cells": world_aperture,
			"aperture_profile": LevelSocketAperture.normalized_profile(world_aperture, world_direction),
			"requires_connection": socket.requires_connection(),
			"unused_fill_block_id": socket.unused_fill_block_id,
		})
	for torch in placement.definition.torches:
		state.torches.append(LevelTorchPlacement.new(
			placement.world_cell(torch.cell),
			placement.world_direction(torch.wall_direction),
			placement.definition.module_id
		))

func _fits_extent(bounds_min: Vector3i, bounds_max: Vector3i) -> bool:
	var span := bounds_max - bounds_min + Vector3i.ONE
	return span.x <= _definition.maximum_extent.x and span.y <= _definition.maximum_extent.y and span.z <= _definition.maximum_extent.z

func _minimum_cell(cells: Array[Vector3i]) -> Vector3i:
	assert(not cells.is_empty())
	var minimum := cells[0]
	for cell in cells:
		minimum = minimum.min(cell)
	return minimum

func _same_cell_set(first: Array[Vector3i], second: Array[Vector3i]) -> bool:
	if first.size() != second.size():
		return false
	var first_cells: Dictionary = {}
	for cell in first:
		first_cells[cell] = true
	for cell in second:
		if not first_cells.has(cell):
			return false
	return true

func _validate_finished_state(state: AssemblyState, target_module_count: int) -> bool:
	if not state.frontiers.is_empty() or state.placed_modules.size() != target_module_count:
		return false
	if not _fits_extent(state.bounds_min, state.bounds_max):
		return false
	if int(state.cells.get(state.spawn_cell, StructureCell.VOID)) != StructureCell.AIR:
		return false
	var reachable: Dictionary = {state.spawn_cell: true}
	var pending: Array[Vector3i] = [state.spawn_cell]
	var pending_index := 0
	while pending_index < pending.size():
		var cell := pending[pending_index]
		pending_index += 1
		for offset in NEIGHBORS:
			var neighbor := cell + offset
			if reachable.has(neighbor) or int(state.cells.get(neighbor, StructureCell.VOID)) != StructureCell.AIR:
				continue
			reachable[neighbor] = true
			pending.append(neighbor)
	for cell in state.cells:
		if int(state.cells[cell]) == StructureCell.AIR and not reachable.has(cell):
			return false
	return true

func _make_layout(state: AssemblyState, seed_value: int, target_module_count: int) -> LevelLayout:
	var layout := LevelLayout.new()
	layout.seed_value = seed_value
	layout.cells = state.cells.duplicate()
	layout.placed_modules.assign(state.placed_modules)
	layout.torches.assign(state.torches)
	layout.spawn_cell = state.spawn_cell
	layout.spawn_facing = state.spawn_facing
	layout.return_door_cell = state.return_door_cell
	layout.return_door_facing = state.return_door_facing
	layout.bounds_min = state.bounds_min
	layout.bounds_max = state.bounds_max
	layout.target_module_count = target_module_count
	layout.explored_state_count = _explored_states
	return layout
