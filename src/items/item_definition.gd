extends Resource
class_name ItemDefinition

enum StatModifierActivation {
	SELECTED,
	EQUIPPED,
}

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var icon: Texture2D
@export var world_model: Mesh
@export var world_material: Material
@export_range(0.01, 10.0, 0.01) var world_presentation_scale: float = 1.0
@export_range(0.1, 4.0, 0.1) var world_pickup_radius_multiplier: float = 1.0
@export_range(1, 999) var max_stack: int = 99
@export var primary_action: ItemActionDefinition
@export var secondary_action: ItemActionDefinition
@export var held_scene: PackedScene
@export var equip_audio: ItemEquipAudioProfile
@export var consume_audio: ItemConsumeAudioProfile
@export var rarity: ItemRarityDefinition
@export var proficiency: ProficiencyDefinition
@export var equipment_type: EquipmentTypeDefinition
@export var stat_modifier_activation: StatModifierActivation = StatModifierActivation.SELECTED
@export var stat_modifiers: Array[StatModifier]
