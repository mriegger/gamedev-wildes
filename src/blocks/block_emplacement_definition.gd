extends Resource
class_name BlockEmplacementDefinition

@export var occupied_offsets: Array[Vector3i] = []
@export var solid_offsets: Array[Vector3i] = []
@export var support_offsets: Array[Vector3i] = []

func validate(source: String) -> bool:
	if occupied_offsets.is_empty() or not occupied_offsets.has(Vector3i.ZERO):
		push_error("[BlockEmplacementDefinition] Missing anchor occupancy at %s" % source)
		return false
	if _has_duplicates(occupied_offsets) or _has_duplicates(solid_offsets) or _has_duplicates(support_offsets):
		push_error("[BlockEmplacementDefinition] Duplicate offsets at %s" % source)
		return false
	for offset in solid_offsets:
		if not occupied_offsets.has(offset):
			push_error("[BlockEmplacementDefinition] Solid offset is not occupied at %s" % source)
			return false
	if support_offsets.is_empty():
		push_error("[BlockEmplacementDefinition] Missing support offsets at %s" % source)
		return false
	return true

func is_solid_offset(offset: Vector3i) -> bool:
	return solid_offsets.has(offset)

func _has_duplicates(offsets: Array[Vector3i]) -> bool:
	var seen: Dictionary = {}
	for offset in offsets:
		if seen.has(offset):
			return true
		seen[offset] = true
	return false
