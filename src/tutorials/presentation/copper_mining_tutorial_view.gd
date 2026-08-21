extends TutorialCalloutView
class_name CopperMiningTutorialView

func show_tip(block_position: Vector3i) -> void:
	show_callout(
		AABB(Vector3(block_position), Vector3.ONE),
		"Copper is too hard to mine by hand. Craft a Pickaxe.",
	)

func hide_tip() -> void:
	hide_callout()
