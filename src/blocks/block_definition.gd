extends Resource
class_name BlockDefinition

@export var id: BlockId.Type = BlockId.Type.AIR

@export_group("Physical Properties")
@export var is_solid: bool = true
@export var is_opaque: bool = true
@export var is_raycast_solid: bool = true
@export var is_breakable: bool = true
@export var is_replaceable: bool = false

@export_group("Appearance")
@export var top_color: Color = Color(1, 0, 1)
@export var side_color: Color = Color(1, 0, 1)
@export var emissive_enabled: bool = false
@export var emissive_color: Color = Color(0, 0, 0, 0)
@export var emissive_energy: float = 0.0

@export_group("Behavior")
@export var light_range: float = 0.0
@export var light_color: Color = Color(1, 1, 1)

func _init(p_id: BlockId.Type = BlockId.Type.AIR):
	id = p_id
	_apply_defaults()

func _apply_defaults():
	match id:
		BlockId.Type.AIR:
			is_solid = false
			is_opaque = false
			is_raycast_solid = false
			is_breakable = false
			is_replaceable = true
			top_color = Color(0, 0, 0, 0)
			side_color = Color(0, 0, 0, 0)

		BlockId.Type.GRASS:
			is_solid = true
			is_opaque = true
			is_raycast_solid = true
			is_breakable = true
			top_color = Color(0.52, 0.67, 0.40)
			side_color = Color(0.42, 0.36, 0.28)

		BlockId.Type.DIRT:
			is_solid = true
			is_opaque = true
			top_color = Color(0.46, 0.38, 0.30)
			side_color = Color(0.46, 0.38, 0.30)

		BlockId.Type.SAND:
			is_solid = true
			is_opaque = true
			top_color = Color(0.86, 0.80, 0.62)
			side_color = Color(0.86, 0.80, 0.62) * 0.94

		BlockId.Type.STONE:
			is_solid = true
			is_opaque = true
			top_color = Color(0.66, 0.66, 0.63)
			side_color = Color(0.66, 0.66, 0.63) * 0.92

		BlockId.Type.LOG:
			is_solid = true
			is_opaque = true
			top_color = Color(0.42, 0.33, 0.24)
			side_color = Color(0.38, 0.29, 0.21)

		BlockId.Type.LEAVES:
			is_solid = true
			is_opaque = false
			is_raycast_solid = true
			top_color = Color(0.36, 0.52, 0.30)
			side_color = Color(0.32, 0.46, 0.27)

		BlockId.Type.TORCH:
			is_solid = false
			is_opaque = false
			is_raycast_solid = true
			is_breakable = true
			top_color = Color(0.78, 0.62, 0.42)
			side_color = Color(0.78, 0.62, 0.42)
			emissive_enabled = true
			emissive_color = Color(1.0, 0.92, 0.68)
			emissive_energy = 1.2
			light_range = 9.0
			light_color = Color(1.0, 0.96, 0.88)

		BlockId.Type.WATER:
			is_solid = false
			is_opaque = false
			is_raycast_solid = false
			is_breakable = true
			is_replaceable = true
			top_color = Color(0.08, 0.35, 0.65, 0.65)
			side_color = Color(0.06, 0.28, 0.56, 0.60)

static func create_all() -> Dictionary:
	var dict: Dictionary = {}
	for i in range(BlockId.Type.COUNT):
		dict[i] = BlockDefinition.new(i as BlockId.Type)
	return dict
