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

enum FrontierTarget {
	ROOM,
	HALLWAY,
}

class AssemblyState:
	var cells: Dictionary = {}
	var placed_modules: Array[LevelPlacedModule] = []
	var torches: Array[LevelTorchPlacement] = []
	var frontiers: Array[Dictionary] = []
	var remaining_room_counts: Dictionary = {}
	var remaining_hallway_count: int
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
		copied.remaining_room_counts = remaining_room_counts.duplicate()
		copied.remaining_hallway_count = remaining_hallway_count
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
var _target_module_count: int
var _room_candidates_by_direction: Dictionary = {}
var _hallway_candidates_by_direction: Dictionary = {}
var _max_room_branch_capacity: Dictionary = {}
var _max_room_footprint: Dictionary = {}
var _rotated_snapshots_by_key: Dictionary = {}
var _snapshot_catalog_id: int

func generate(catalog: LevelCatalog, level_id: StringName, world_seed: int, entrance_id: StringName, entrance_coordinate: Vector3i) -> LevelGenerationResult:
	if catalog == null or not catalog.validate():
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.INVALID_CATALOG, "Level catalog validation failed")
	if not catalog.has_level(level_id):
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.UNKNOWN_LEVEL, "Unknown level ID: %s" % level_id)
	_catalog = catalog
	_definition = catalog.get_level(level_id)
	_explored_states = 0
	_search_limit = mini(_definition.maximum_explored_states, LevelDefinition.HARD_MAX_EXPLORED_STATES)
	if _snapshot_catalog_id != catalog.get_instance_id():
		_rotated_snapshots_by_key.clear()
		_snapshot_catalog_id = catalog.get_instance_id()
	_build_candidate_tables()
	var seed_value := derive_seed(world_seed, entrance_id, entrance_coordinate)
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	var start_module := _catalog.get_module(_definition.start_module_id)
	var required_hallway_count := _definition.get_hallway_count(start_module.sockets.size())
	_target_module_count = _definition.get_target_module_count(start_module.sockets.size())
	var state := _create_initial_state(start_module)
	if state == null:
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.INVALID_LAYOUT, "Start module exceeds the configured bounds")
	state.remaining_room_counts = _initial_room_counts()
	state.remaining_hallway_count = required_hallway_count
	var assembled := _assemble(state)
	if assembled == null:
		if _explored_states >= _search_limit:
			return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.SEARCH_LIMIT_REACHED, "Level assembly explored %d candidate states" % _explored_states)
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.NO_LAYOUT, "No valid layout satisfied the required room composition")
	if not _validate_finished_state(assembled, _target_module_count):
		return LevelGenerationResult.make_failure(LevelGenerationResult.FailureCode.INVALID_LAYOUT, "Assembled level failed composition or reachability validation")
	return LevelGenerationResult.make_success(_make_layout(assembled, seed_value, _target_module_count))

static func derive_seed(world_seed: int, entrance_id: StringName, entrance_coordinate: Vector3i) -> int:
	var identity := "%d|%s|%d,%d,%d" % [world_seed, entrance_id, entrance_coordinate.x, entrance_coordinate.y, entrance_coordinate.z]
	var hash_value := FNV_OFFSET_BASIS_32
	for byte in identity.to_utf8_buffer():
		hash_value = ((hash_value ^ int(byte)) * FNV_PRIME_32) & UINT32_MASK
	return hash_value

func _create_initial_state(module: LevelModuleDefinition) -> AssemblyState:
	var state := AssemblyState.new()
	var origin := Vector3i(-module.spawn_marker.cell.x, 0, -module.spawn_marker.cell.z)
	var placement := LevelPlacedModule.new(module, origin, 0, &"")
	_write_placement(state, placement, _transformed_cells(placement))
	state.spawn_cell = placement.world_cell(module.spawn_marker.cell)
	state.spawn_facing = placement.world_direction(module.spawn_marker.facing)
	state.return_door_cell = placement.world_cell(module.return_door_marker.cell)
	state.return_door_facing = placement.world_direction(module.return_door_marker.facing)
	if not _fits_extent(state.bounds_min, state.bounds_max):
		return null
	return state

func _initial_room_counts() -> Dictionary:
	var counts: Dictionary = {}
	for requirement in _definition.room_requirements:
		counts[requirement.room_type_id] = requirement.count
	return counts

func _remaining_room_count(state: AssemblyState) -> int:
	var count := 0
	for remaining in state.remaining_room_counts.values():
		count += int(remaining)
	return count

func _assemble(state: AssemblyState) -> AssemblyState:
	if _remaining_room_count(state) == 0:
		if state.remaining_hallway_count != 0 or _required_frontier_count(state.frontiers) != 0:
			return null
		if not _seal_optional_frontiers(state):
			return null
		return state if _validate_finished_state(state, _target_module_count) else null
	if _explored_states >= _search_limit or not _can_finish_composition(state):
		return null
	for frontier_index in _next_frontier_indices(state):
		var frontier := state.frontiers[frontier_index]
		var required_direction := LevelSocketDefinition.opposite(frontier["direction"] as LevelSocketDefinition.Direction)
		var frontier_profile := frontier["aperture_profile"] as Array[Vector2i]
		if int(frontier["target"]) == FrontierTarget.ROOM:
			var room_candidates := _room_candidates_by_direction[required_direction] as Array[Dictionary]
			for candidate in _ordered_room_candidates(room_candidates, frontier_profile, state.remaining_room_counts):
				if _explored_states >= _search_limit:
					return null
				_explored_states += 1
				var room_type_id := candidate["room_type_id"] as StringName
				var next_state := _try_place(state, frontier_index, candidate, room_type_id)
				if next_state == null:
					continue
				next_state.remaining_room_counts[room_type_id] = int(next_state.remaining_room_counts[room_type_id]) - 1
				var assembled := _assemble(next_state)
				if assembled != null:
					return assembled
		elif state.remaining_hallway_count > 0:
			var hallway_candidates := _hallway_candidates_by_direction[required_direction] as Array[Dictionary]
			for candidate in _weighted_candidate_order(_matching_candidates(hallway_candidates, frontier_profile)):
				if _explored_states >= _search_limit:
					return null
				_explored_states += 1
				var next_state := _try_place(state, frontier_index, candidate, &"")
				if next_state == null:
					continue
				next_state.remaining_hallway_count -= 1
				var assembled := _assemble(next_state)
				if assembled != null:
					return assembled
	return null

func _can_finish_composition(state: AssemblyState) -> bool:
	var remaining_rooms := _remaining_room_count(state)
	var required_room_frontiers := 0
	var optional_hallway_frontiers := 0
	for frontier in state.frontiers:
		if bool(frontier["requires_connection"]):
			if int(frontier["target"]) != FrontierTarget.ROOM:
				return false
			required_room_frontiers += 1
		elif int(frontier["target"]) == FrontierTarget.HALLWAY:
			optional_hallway_frontiers += 1
	if remaining_rooms != required_room_frontiers + state.remaining_hallway_count:
		return false
	var future_branch_capacity := optional_hallway_frontiers
	for room_type_id in state.remaining_room_counts:
		future_branch_capacity += int(state.remaining_room_counts[room_type_id]) * int(_max_room_branch_capacity[room_type_id])
	return future_branch_capacity >= state.remaining_hallway_count

func _next_frontier_indices(state: AssemblyState) -> Array[int]:
	var required: Array[int] = []
	var optional_hallways: Array[int] = []
	for index in state.frontiers.size():
		var frontier := state.frontiers[index]
		if bool(frontier["requires_connection"]):
			required.append(index)
		elif int(frontier["target"]) == FrontierTarget.HALLWAY:
			optional_hallways.append(index)
	if not required.is_empty():
		return _ordered_frontier_indices(state.frontiers, required)
	if state.remaining_hallway_count > 0:
		return _ordered_frontier_indices(state.frontiers, optional_hallways)
	return []

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

func _ordered_frontier_indices(frontiers: Array[Dictionary], source_indices: Array[int]) -> Array[int]:
	var indices := source_indices.duplicate()
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
	_room_candidates_by_direction.clear()
	_hallway_candidates_by_direction.clear()
	_max_room_branch_capacity.clear()
	_max_room_footprint.clear()
	for requirement in _definition.room_requirements:
		var maximum_capacity := 0
		var maximum_footprint := 0
		for module_id in requirement.module_ids:
			var module := _catalog.get_module(module_id)
			maximum_capacity = maxi(maximum_capacity, module.sockets.size() - 1)
			maximum_footprint = maxi(maximum_footprint, module.size.x * module.size.z)
		_max_room_branch_capacity[requirement.room_type_id] = maximum_capacity
		_max_room_footprint[requirement.room_type_id] = maximum_footprint
	for required_direction in range(LevelSocketDefinition.Direction.size()):
		var direction := required_direction as LevelSocketDefinition.Direction
		_hallway_candidates_by_direction[direction] = _build_candidates(_definition.hallway_module_ids, direction)
		var room_candidates: Array[Dictionary] = []
		for requirement in _definition.room_requirements:
			for candidate in _build_candidates(requirement.module_ids, direction):
				var annotated := candidate.duplicate()
				annotated["room_type_id"] = requirement.room_type_id
				annotated["key"] = "%s:%s" % [requirement.room_type_id, candidate["key"]]
				room_candidates.append(annotated)
		room_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["key"]) < String(b["key"])
		)
		_room_candidates_by_direction[direction] = room_candidates

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
		if candidate["aperture_profile"] == profile:
			matching.append(candidate)
	return matching

func _matching_room_candidates(candidates: Array[Dictionary], profile: Array[Vector2i], remaining_counts: Dictionary) -> Array[Dictionary]:
	var matching: Array[Dictionary] = []
	for candidate in candidates:
		var room_type_id := candidate["room_type_id"] as StringName
		var remaining := int(remaining_counts.get(room_type_id, 0))
		if remaining <= 0 or candidate["aperture_profile"] != profile:
			continue
		var weighted := candidate.duplicate()
		weighted["weight"] = float(candidate["weight"]) * remaining
		matching.append(weighted)
	return matching

func _ordered_room_candidates(candidates: Array[Dictionary], profile: Array[Vector2i], remaining_counts: Dictionary) -> Array[Dictionary]:
	var ordered := _weighted_candidate_order(_matching_room_candidates(candidates, profile, remaining_counts))
	for index in ordered.size():
		ordered[index]["random_rank"] = index
	ordered.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_type := a["room_type_id"] as StringName
		var b_type := b["room_type_id"] as StringName
		var a_capacity := int(_max_room_branch_capacity[a_type])
		var b_capacity := int(_max_room_branch_capacity[b_type])
		if a_capacity != b_capacity:
			return a_capacity > b_capacity
		var a_footprint := int(_max_room_footprint[a_type])
		var b_footprint := int(_max_room_footprint[b_type])
		if a_footprint != b_footprint:
			return a_footprint > b_footprint
		return int(a["random_rank"]) < int(b["random_rank"])
	)
	return ordered

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

func _try_place(state: AssemblyState, frontier_index: int, candidate: Dictionary, room_type_id: StringName) -> AssemblyState:
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
	var placement := LevelPlacedModule.new(module, origin, rotation, room_type_id)
	var rotated_snapshot := _rotated_snapshot(module, rotation)
	var candidate_min: Vector3i = state.bounds_min.min(origin + (rotated_snapshot["bounds_min"] as Vector3i))
	var candidate_max: Vector3i = state.bounds_max.max(origin + (rotated_snapshot["bounds_max"] as Vector3i))
	if not _fits_extent(candidate_min, candidate_max):
		return null
	for rotated_cell_variant in rotated_snapshot["occupied_cells"] as Array[Vector3i]:
		if state.cells.has(origin + (rotated_cell_variant as Vector3i)):
			return null
	if not _has_only_connected_air_adjacency(state, rotated_snapshot, origin, frontier_aperture, frontier_direction):
		return null
	var transformed_cells := _transformed_cells(placement, rotated_snapshot)
	var next_state := state.copy()
	next_state.frontiers.remove_at(frontier_index)
	_write_placement(next_state, placement, transformed_cells, socket.socket_id)
	return next_state

func _transformed_cells(placement: LevelPlacedModule, rotated_snapshot: Dictionary = {}) -> Dictionary:
	var transformed: Dictionary = {}
	if rotated_snapshot.is_empty():
		rotated_snapshot = _rotated_snapshot(placement.definition, placement.rotation)
	var rotated_cells := rotated_snapshot["cells"] as Dictionary
	for rotated_cell_variant in rotated_cells:
		var rotated_cell := rotated_cell_variant as Vector3i
		transformed[placement.origin + rotated_cell] = rotated_cells[rotated_cell]
	return transformed

func _rotated_snapshot(module: LevelModuleDefinition, rotation: int) -> Dictionary:
	var key := "%s:%d" % [module.module_id, posmod(rotation, 4)]
	if _rotated_snapshots_by_key.has(key):
		return _rotated_snapshots_by_key[key] as Dictionary
	var rotated_cells: Dictionary = {}
	var occupied_cells: Array[Vector3i] = []
	for y in module.size.y:
		for z in module.size.z:
			for x in module.size.x:
				var local_cell := Vector3i(x, y, z)
				var value := module.cell_at(local_cell)
				if value != StructureCell.VOID:
					var rotated_cell := module.rotate_cell(local_cell, rotation)
					rotated_cells[rotated_cell] = value
					occupied_cells.append(rotated_cell)
	var exposed_air_cells: Array[Vector3i] = []
	for rotated_cell in occupied_cells:
		if int(rotated_cells[rotated_cell]) != StructureCell.AIR:
			continue
		for offset in NEIGHBORS:
			if not rotated_cells.has(rotated_cell + offset):
				exposed_air_cells.append(rotated_cell)
				break
	var bounds_min := occupied_cells[0]
	var bounds_max := occupied_cells[0]
	for rotated_cell in occupied_cells:
		bounds_min = bounds_min.min(rotated_cell)
		bounds_max = bounds_max.max(rotated_cell)
	var snapshot := {
		"cells": rotated_cells,
		"occupied_cells": occupied_cells,
		"exposed_air_cells": exposed_air_cells,
		"bounds_min": bounds_min,
		"bounds_max": bounds_max,
	}
	_rotated_snapshots_by_key[key] = snapshot
	return snapshot

func _has_only_connected_air_adjacency(
	state: AssemblyState,
	rotated_snapshot: Dictionary,
	origin: Vector3i,
	frontier_aperture: Array[Vector3i],
	frontier_direction: LevelSocketDefinition.Direction,
) -> bool:
	var connected_neighbors: Dictionary = {}
	var outward := LevelSocketDefinition.vector_for(frontier_direction)
	for frontier_cell in frontier_aperture:
		connected_neighbors[frontier_cell + outward] = frontier_cell
	var rotated_cells := rotated_snapshot["cells"] as Dictionary
	for rotated_cell in rotated_snapshot["exposed_air_cells"] as Array[Vector3i]:
		var transformed_cell := origin + rotated_cell
		for offset in NEIGHBORS:
			if rotated_cells.has(rotated_cell + offset):
				continue
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
	var frontier_target := FrontierTarget.ROOM if placement.room_type_id.is_empty() else FrontierTarget.HALLWAY
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
			"target": frontier_target,
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
	if not _has_exact_composition(state):
		return false
	if not _fits_extent(state.bounds_min, state.bounds_max):
		return false
	if int(state.cells.get(state.spawn_cell, StructureCell.VOID)) != StructureCell.AIR:
		return false
	return true

func _has_exact_composition(state: AssemblyState) -> bool:
	if state.placed_modules.is_empty() or state.placed_modules[0].definition.module_id != _definition.start_module_id:
		return false
	var room_counts: Dictionary = {}
	var requirements_by_type: Dictionary = {}
	for requirement in _definition.room_requirements:
		room_counts[requirement.room_type_id] = 0
		requirements_by_type[requirement.room_type_id] = requirement
	var hallway_count := 0
	for index in range(1, state.placed_modules.size()):
		var placement := state.placed_modules[index]
		if placement.room_type_id.is_empty():
			if not _definition.hallway_module_ids.has(placement.definition.module_id):
				return false
			hallway_count += 1
			continue
		if not requirements_by_type.has(placement.room_type_id):
			return false
		var requirement := requirements_by_type[placement.room_type_id] as LevelRoomRequirement
		if not requirement.module_ids.has(placement.definition.module_id):
			return false
		room_counts[placement.room_type_id] = int(room_counts[placement.room_type_id]) + 1
	for requirement in _definition.room_requirements:
		if int(room_counts[requirement.room_type_id]) != requirement.count:
			return false
	return hallway_count == _definition.get_hallway_count(_catalog.get_module(_definition.start_module_id).sockets.size())

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
