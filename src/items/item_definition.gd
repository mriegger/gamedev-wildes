extends Resource
class_name ItemDefinition

@export var id: StringName
@export var icon: Texture2D
@export_range(1, 999) var max_stack: int = 99
@export var placed_block: BlockDefinition
