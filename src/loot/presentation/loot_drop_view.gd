extends Node3D
class_name LootDropView

func setup(icon: Texture2D) -> void:
	assert(icon != null)
	var icon_sprite := get_node("Icon") as Sprite3D
	icon_sprite.texture = icon
