extends Resource
class_name ItemRarityDefinition

@export var id: StringName
@export var display_name: String
@export var display_color: Color = Color.WHITE

func validate() -> bool:
	return (
		not id.is_empty()
		and not display_name.is_empty()
		and is_finite(display_color.r)
		and is_finite(display_color.g)
		and is_finite(display_color.b)
		and is_finite(display_color.a)
		and display_color.r >= 0.0
		and display_color.r <= 1.0
		and display_color.g >= 0.0
		and display_color.g <= 1.0
		and display_color.b >= 0.0
		and display_color.b <= 1.0
		and display_color.a > 0.0
		and display_color.a <= 1.0
	)
