extends CanvasLayer
class_name LoadingScreen

func setup(slot_id: int, save_data: Dictionary):
	var world_name_label = get_node("Control/CenterContainer/FrostedPanel/VBox/WorldNameLabel") as Label
	var progress_bar = get_node("Control/CenterContainer/FrostedPanel/VBox/ProgressBar") as ProgressBar
	var status_label = get_node("Control/CenterContainer/FrostedPanel/VBox/StatusLabel") as Label
	world_name_label.text = "Loading %s" % save_data.get("world_name", "World %d" % (slot_id + 1))
	progress_bar.value = 5
	status_label.text = "Preparing world..."

func update_progress(stage: String, percent: float, details: String):
	var progress_bar = get_node("Control/CenterContainer/FrostedPanel/VBox/ProgressBar") as ProgressBar
	var status_label = get_node("Control/CenterContainer/FrostedPanel/VBox/StatusLabel") as Label
	var value = clamp(percent, 0.0, 1.0) * 100.0
	if value > progress_bar.value:
		progress_bar.value = value
	status_label.text = "%s: %s" % [stage.capitalize(), details]
