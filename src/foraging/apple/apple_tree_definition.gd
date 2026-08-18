extends Resource
class_name AppleTreeDefinition

@export_range(0.0, 1.0, 0.001) var tree_fraction: float = 0.05
@export_range(1, 3, 1) var minimum_ground_apples: int = 1
@export_range(1, 3, 1) var maximum_ground_apples: int = 3
@export_range(1, 4, 1) var minimum_decorative_apples: int = 1
@export_range(1, 4, 1) var maximum_decorative_apples: int = 4
@export var apple_item_id: StringName = &"apple"
@export var apple_scene: PackedScene
@export_range(0.01, 1.0, 0.01) var ground_apple_size: float = 0.28
@export_range(0.01, 1.0, 0.01) var decorative_apple_size: float = 0.24

func validate(item_catalog: ItemCatalog) -> bool:
	return (
		is_finite(tree_fraction)
		and tree_fraction > 0.0
		and tree_fraction <= 1.0
		and minimum_ground_apples >= 1
		and minimum_ground_apples <= maximum_ground_apples
		and maximum_ground_apples <= AppleTreeState.MAXIMUM_GROUND_APPLES
		and minimum_decorative_apples >= 1
		and minimum_decorative_apples <= maximum_decorative_apples
		and maximum_decorative_apples <= 4
		and not apple_item_id.is_empty()
		and item_catalog.has_definition(apple_item_id)
		and apple_scene != null
		and is_finite(ground_apple_size)
		and ground_apple_size > 0.0
		and is_finite(decorative_apple_size)
		and decorative_apple_size > 0.0
	)
