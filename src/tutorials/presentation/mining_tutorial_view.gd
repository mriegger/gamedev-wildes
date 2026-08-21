extends TutorialCalloutView
class_name MiningTutorialView

func show_tip(block_position: Vector3i) -> void:
	show_callout(
		AABB(Vector3(block_position), Vector3.ONE),
		"Hold left mouse button to mine blocks",
	)

func hide_tip() -> void:
	hide_callout()
