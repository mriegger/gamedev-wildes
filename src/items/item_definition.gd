extends Resource
class_name ItemDefinition

enum StatModifierActivation {
	SELECTED,
	EQUIPPED,
}

@export var id: StringName
@export var icon: Texture2D
@export_range(1, 999) var max_stack: int = 99
@export var primary_action: ItemActionDefinition
@export var secondary_action: ItemActionDefinition
@export var held_scene: PackedScene
@export var stat_modifier_activation: StatModifierActivation = StatModifierActivation.SELECTED
@export var stat_modifiers: Array[StatModifier]
