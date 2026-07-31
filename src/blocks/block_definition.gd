extends Resource
class_name BlockDefinition

## Schema for a block's properties, appearance, and behavior.
## Data-driven definition so world, rendering, and player don't hardcode per-type logic.
## Used by future BlockRegistry to create a lookup table.

# --- Identity ---
@export var id: BlockId.Type = BlockId.Type.AIR
@export var display_name: String = ""
@export var internal_name: String = ""
@export var description: String = ""

@export_group("Physical Properties")
## Does block have collision for player movement / physics?
@export var is_solid: bool = true
## Does block block light propagation (sun / torch BFS)?
@export var is_opaque: bool = true
## Does block occupy the voxel for placement rejection (includes torches)?
@export var is_occupying: bool = true
## Is block selectable via raycast (torches are selectable though not solid)?
@export var is_raycast_solid: bool = true
## Can player mine it? (bedrock would be false)
@export var is_breakable: bool = true
## Can another block replace it (AIR is replaceable)
@export var is_replaceable: bool = false
## Hardness controls mine_hold_time multiplier (0 = instant, 1 = baseline)
@export var hardness: float = 1.0
## Does placement require adjacent support (torches)
@export var requires_support: bool = false
## Can it be placed on world border (usually false)
@export var allowed_on_border: bool = false
## Friction / jump? future
@export var friction: float = 1.0

@export_group("Appearance")
@export var top_color: Color = Color(1, 0, 1)
@export var side_color: Color = Color(1, 0, 1)
@export var bottom_color: Color = Color(1, 0, 1)
## Optional secondary top color for variation
@export var top_color_alt: Color = Color(1, 0, 1)
@export var side_color_alt: Color = Color(1, 0, 1)
## Tint randomness range
@export var color_variation: float = 0.08
@export var emissive_enabled: bool = false
@export var emissive_color: Color = Color(0, 0, 0, 0)
@export var emissive_energy: float = 0.0
@export var transparency: float = 0.0
@export var rough_material: bool = true

## Future texture slots - keep optional
@export var top_texture: Texture2D
@export var side_texture: Texture2D
@export var bottom_texture: Texture2D

@export_group("Behavior")
@export var emits_light: bool = false
@export var light_level: int = 0 # 0..15
@export var light_range: float = 0.0
@export var light_color: Color = Color(1, 1, 1)
@export var flammable: bool = false
@export var fuel_value: float = 0.0
@export var drops_self: bool = true
@export var drop_id: BlockId.Type = BlockId.Type.AIR # if not self, what it drops; AIR = self
@export var stack_size: int = 64

@export_group("Audio/Effects (Future)")
@export var place_sound: AudioStream
@export var break_sound: AudioStream
@export var step_sound: AudioStream


func _init(p_id: BlockId.Type = BlockId.Type.AIR):
	id = p_id
	if display_name == "":
		display_name = BlockId.get_display_name(id)
	if internal_name == "":
		internal_name = BlockId.get_internal_name(id)
	# apply sane defaults per id
	_apply_defaults()

func _apply_defaults():
	# Set defaults based on id matching original wildes constants
	match id:
		BlockId.Type.AIR:
			is_solid = false
			is_opaque = false
			is_occupying = false
			is_raycast_solid = false
			is_breakable = false
			is_replaceable = true
			hardness = 0.0
			top_color = Color(0, 0, 0, 0)
			side_color = Color(0, 0, 0, 0)
			bottom_color = Color(0, 0, 0, 0)

		BlockId.Type.GRASS:
			is_solid = true
			is_opaque = true
			is_occupying = true
			is_raycast_solid = true
			is_breakable = true
			hardness = 0.9
			top_color = Color(0.52, 0.67, 0.40)   # COL_GRASS_TOP
			side_color = Color(0.42, 0.36, 0.28)  # COL_GRASS_SIDE
			bottom_color = Color(0.46, 0.38, 0.30) # DIRT
			color_variation = 0.08
			flammable = false

		BlockId.Type.DIRT:
			is_solid = true
			is_opaque = true
			hardness = 0.8
			top_color = Color(0.46, 0.38, 0.30)
			side_color = Color(0.46, 0.38, 0.30)
			bottom_color = Color(0.46, 0.38, 0.30)

		BlockId.Type.SAND:
			is_solid = true
			is_opaque = true
			hardness = 0.7
			top_color = Color(0.86, 0.80, 0.62)
			side_color = Color(0.86, 0.80, 0.62) * 0.94
			bottom_color = Color(0.86, 0.80, 0.62) * 0.94

		BlockId.Type.STONE:
			is_solid = true
			is_opaque = true
			hardness = 1.6
			top_color = Color(0.66, 0.66, 0.63)
			side_color = Color(0.66, 0.66, 0.63) * 0.92
			bottom_color = Color(0.66, 0.66, 0.63) * 0.92

		BlockId.Type.LOG:
			is_solid = true
			is_opaque = true
			hardness = 1.2
			top_color = Color(0.42, 0.33, 0.24) # COL_LOG_TOP
			side_color = Color(0.38, 0.29, 0.21) # COL_LOG
			bottom_color = Color(0.42, 0.33, 0.24)
			flammable = true
			fuel_value = 1.5

		BlockId.Type.LEAVES:
			is_solid = true
			is_opaque = false # semi - lets light through for torch simplicity
			is_raycast_solid = true
			hardness = 0.3
			top_color = Color(0.36, 0.52, 0.30)
			side_color = Color(0.32, 0.46, 0.27) # dark
			bottom_color = Color(0.32, 0.46, 0.27)
			flammable = true
			fuel_value = 0.3
			transparency = 0.0

		BlockId.Type.TORCH:
			is_solid = false
			is_opaque = false
			is_occupying = true
			is_raycast_solid = true
			is_breakable = true
			requires_support = true
			hardness = 0.1
			top_color = Color(0.78, 0.62, 0.42) # COL_TORCH
			side_color = Color(0.78, 0.62, 0.42)
			bottom_color = Color(0.78, 0.62, 0.42)
			emissive_enabled = true
			emissive_color = Color(1.0, 0.92, 0.68) # COL_TORCH_FLAME
			emissive_energy = 1.2
			emits_light = true
			light_level = 12
			light_range = 9.0 # TORCH_OMNI_RANGE
			light_color = Color(1.0, 0.96, 0.88)

		BlockId.Type.WATER:
			is_solid = false # player can swim through, not collide
			is_opaque = false # light passes, transparent
			is_occupying = true # occupies voxel, but replaceable
			is_raycast_solid = false # not targeted by raycast for mining (optional)
			is_breakable = true
			is_replaceable = true
			hardness = 100.0 
			# Deeper blue - synced with WaterProfile.tint_color Vector4(0.08, 0.35, 0.65, 0.88)
			top_color = Color(0.08, 0.35, 0.65, 0.65) # translucent blue
			side_color = Color(0.06, 0.28, 0.56, 0.60)
			bottom_color = Color(0.05, 0.24, 0.50, 0.65)
			transparency = 0.55
			color_variation = 0.02
			flammable = false

func get_effective_top_color(var_offset: float = 0.0) -> Color:
	if is_air():
		return Color(0, 0, 0, 0)
	return top_color + Color(var_offset, var_offset, var_offset)

func get_effective_side_color(var_offset: float = 0.0) -> Color:
	if is_air():
		return Color(0, 0, 0, 0)
	return side_color + Color(var_offset * 0.6, var_offset * 0.6, var_offset * 0.6)

func get_drop_id() -> BlockId.Type:
	if drop_id == BlockId.Type.AIR:
		return id
	return drop_id

func is_air() -> bool:
	return id == BlockId.Type.AIR

func can_support_torch() -> bool:
	# any opaque / solid can support
	return is_opaque or is_solid

func to_dictionary() -> Dictionary:
	return {
		"id": id,
		"internal": internal_name,
		"display": display_name,
		"solid": is_solid,
		"opaque": is_opaque,
		"occupying": is_occupying,
		"raycast": is_raycast_solid,
		"breakable": is_breakable,
		"hardness": hardness,
		"requires_support": requires_support,
		"emits_light": emits_light,
		"light_level": light_level,
		"light_range": light_range,
		"top_color": top_color,
		"side_color": side_color,
	}

static func create(id: BlockId.Type) -> BlockDefinition:
	return BlockDefinition.new(id)

static func create_all() -> Dictionary:
	# Returns Dictionary BlockId.Type -> BlockDefinition for all valid ids
	var dict: Dictionary = {}
	for i in range(BlockId.Type.COUNT):
		if i == BlockId.Type.AIR:
			continue
		var def = BlockDefinition.new(i as BlockId.Type)
		dict[i] = def
	# include AIR
	dict[BlockId.Type.AIR] = BlockDefinition.new(BlockId.Type.AIR)
	return dict
