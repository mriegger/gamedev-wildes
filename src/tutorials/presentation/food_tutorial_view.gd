extends TutorialCalloutView
class_name FoodTutorialView

func show_tip(target_bounds: AABB) -> void:
	show_callout(
		target_bounds,
		"Consume food to recover health",
		"Tip: Craft a Hoe at the Anvil to grow your own food",
	)

func hide_tip() -> void:
	hide_callout()
