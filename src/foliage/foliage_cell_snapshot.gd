extends RefCounted
class_name FoliageCellSnapshot

const STRIDE: int = 4

static func pack(blocks: Dictionary, origin_x: int, origin_z: int, size_x: int, size_z: int, size_y: int) -> PackedInt32Array:
	var cells_by_order: Dictionary = {}
	for position_value in blocks:
		if not position_value is Vector3i:
			continue
		var position := position_value as Vector3i
		var block_id := int(blocks[position])
		var local_x := position.x - origin_x
		var local_z := position.z - origin_z
		if local_x < 0 or local_x >= size_x or local_z < 0 or local_z >= size_z or position.y < 0 or position.y >= size_y or not BlockId.is_foliage(block_id):
			continue
		var order := (local_x * size_z + local_z) * size_y + position.y
		cells_by_order[order] = Vector4i(position.x, position.y, position.z, block_id)
	var orders := cells_by_order.keys()
	orders.sort()
	var cells := PackedInt32Array()
	cells.resize(orders.size() * STRIDE)
	for cell_index in range(orders.size()):
		var cell := cells_by_order[orders[cell_index]] as Vector4i
		var offset := cell_index * STRIDE
		cells[offset] = cell.x
		cells[offset + 1] = cell.y
		cells[offset + 2] = cell.z
		cells[offset + 3] = cell.w
	return cells
