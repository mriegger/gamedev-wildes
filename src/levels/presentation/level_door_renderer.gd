extends Node3D
class_name LevelDoorRenderer

const TRANSITION_SECONDS: float = 0.35
const BAR_WIDTH: float = 0.18
const BAR_DEPTH: float = 0.14
const CROSSBAR_HEIGHT: float = 0.14

var _roots_by_id: Dictionary = {}
var _open_offsets: Dictionary = {}
var _tweens: Dictionary = {}

func setup(doorways: Array[LevelDoorway], door_locks: Dictionary, block_catalog: BlockCatalog) -> bool:
	if not _roots_by_id.is_empty() or doorways.is_empty() or block_catalog == null:
		return false
	var material := StandardMaterial3D.new()
	material.albedo_texture = block_catalog.get_definition(BlockId.Type.WOOD_PLANKS).side_texture
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 0.9
	for doorway in doorways:
		if doorway == null or not door_locks.has(doorway.door_id):
			return false
		var root := Node3D.new()
		root.name = "Door%d" % doorway.door_id
		add_child(root)
		_build_gate(root, doorway, material)
		var minimum_y := doorway.aperture_cells[0].y
		var maximum_y := minimum_y
		for cell in doorway.aperture_cells:
			minimum_y = mini(minimum_y, cell.y)
			maximum_y = maxi(maximum_y, cell.y)
		var open_offset := float(maximum_y - minimum_y + 1) + 0.5
		_open_offsets[doorway.door_id] = open_offset
		root.position.y = 0.0 if bool(door_locks[doorway.door_id]) else open_offset
		_roots_by_id[doorway.door_id] = root
	return true

func apply_door_locks(changes: Dictionary) -> void:
	for door_id in changes:
		assert(_roots_by_id.has(door_id) and changes[door_id] is bool)
		var root := _roots_by_id[door_id] as Node3D
		var target_y := 0.0 if bool(changes[door_id]) else float(_open_offsets[door_id])
		var previous := _tweens.get(door_id) as Tween
		if previous != null and previous.is_valid():
			previous.kill()
		var tween := create_tween()
		tween.set_trans(Tween.TRANS_QUAD)
		tween.set_ease(Tween.EASE_OUT)
		tween.tween_property(root, "position:y", target_y, TRANSITION_SECONDS)
		_tweens[door_id] = tween

func _build_gate(root: Node3D, doorway: LevelDoorway, material: StandardMaterial3D) -> void:
	var normal_uses_z := doorway.direction in [LevelSocketDefinition.Direction.NORTH, LevelSocketDefinition.Direction.SOUTH]
	for cell in doorway.aperture_cells:
		var vertical := MeshInstance3D.new()
		var vertical_mesh := BoxMesh.new()
		vertical_mesh.size = Vector3(BAR_WIDTH, 1.0, BAR_DEPTH) if normal_uses_z else Vector3(BAR_DEPTH, 1.0, BAR_WIDTH)
		vertical.mesh = vertical_mesh
		vertical.position = Vector3(cell) + Vector3(0.5, 0.5, 0.5)
		vertical.material_override = material
		vertical.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(vertical)
		var crossbar := MeshInstance3D.new()
		var crossbar_mesh := BoxMesh.new()
		crossbar_mesh.size = Vector3(1.0, CROSSBAR_HEIGHT, BAR_DEPTH) if normal_uses_z else Vector3(BAR_DEPTH, CROSSBAR_HEIGHT, 1.0)
		crossbar.mesh = crossbar_mesh
		crossbar.position = Vector3(cell) + Vector3(0.5, 0.72, 0.5)
		crossbar.material_override = material
		crossbar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(crossbar)
