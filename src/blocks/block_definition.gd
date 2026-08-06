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
@export var top_texture: Texture2D
@export var side_texture: Texture2D
@export var bottom_texture: Texture2D
@export var emissive_enabled: bool = false
@export var emissive_color: Color = Color(0, 0, 0, 0)
@export var emissive_energy: float = 0.0

@export_group("Behavior")
@export var light_range: float = 0.0
@export var light_color: Color = Color(1, 1, 1)
