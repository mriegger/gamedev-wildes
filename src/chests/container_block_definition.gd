extends Resource
class_name ContainerBlockDefinition

const MAX_SLOT_COUNT: int = 144

@export_range(1, 12) var rows: int = 3
@export_range(1, 12) var columns: int = 5

func get_slot_count() -> int:
	return rows * columns

func validate(source: String) -> bool:
	if rows > 0 and columns > 0 and get_slot_count() <= MAX_SLOT_COUNT:
		return true
	push_error("[ContainerBlockDefinition] Invalid dimensions at %s" % source)
	return false
