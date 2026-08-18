extends Resource
class_name AppleTreeDefinition

@export_range(0.0, 1.0, 0.001) var tree_fraction: float = 0.05
@export_range(2, 6, 1) var minimum_ground_apples: int = 2
@export_range(2, 6, 1) var maximum_ground_apples: int = 6
@export_range(20, 20, 1) var decorative_apple_count: int = 20
@export var apple_item_id: StringName = &"apple"
@export var apple_scene: PackedScene
@export_range(0.01, 1.0, 0.01) var ground_apple_size: float = 0.28
@export_range(0.01, 1.0, 0.01) var decorative_apple_size: float = 0.24
@export var foliage_tint: Color = Color(0.92, 1.08, 0.72, 1.0)

func validate(item_catalog: ItemCatalog) -> bool:
	return (
		is_finite(tree_fraction)
		and tree_fraction > 0.0
		and tree_fraction <= 1.0
		and minimum_ground_apples >= 2
		and minimum_ground_apples <= maximum_ground_apples
		and maximum_ground_apples <= AppleTreeState.MAXIMUM_GROUND_APPLES
		and decorative_apple_count == 20
		and not apple_item_id.is_empty()
		and item_catalog.has_definition(apple_item_id)
		and apple_scene != null
		and is_finite(ground_apple_size)
		and ground_apple_size > 0.0
		and is_finite(decorative_apple_size)
		and decorative_apple_size > 0.0
		and foliage_tint.r > 0.0
		and foliage_tint.g > 0.0
		and foliage_tint.b > 0.0
		and foliage_tint.a == 1.0
	)
