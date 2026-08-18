extends Resource
class_name ItemDefinition

enum StatModifierActivation {
	SELECTED,
	EQUIPPED,
}

@export var id: StringName
@export var display_name: String
@export var icon: Texture2D
@export_range(1, 999) var max_stack: int = 99
@export var primary_action: ItemActionDefinition
@export var secondary_action: ItemActionDefinition
@export var held_scene: PackedScene
@export var equip_audio: ItemEquipAudioProfile
@export var consume_audio: ItemConsumeAudioProfile
@export var rarity: ItemRarityDefinition
@export var proficiency: ProficiencyDefinition
@export var stat_modifier_activation: StatModifierActivation = StatModifierActivation.SELECTED
@export var stat_modifiers: Array[StatModifier]
