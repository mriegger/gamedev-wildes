extends CanvasLayer
class_name LoadingScreen

@onready var world_name_label: Label = $Control/CenterContainer/FrostedPanel/VBox/WorldNameLabel
@onready var progress_bar: ProgressBar = $Control/CenterContainer/FrostedPanel/VBox/ProgressBar
@onready var status_label: Label = $Control/CenterContainer/FrostedPanel/VBox/StatusLabel

var slot_id: int = -1
var save_data: Dictionary = {}
var game_instance: Game = null

func start_loading(p_slot_id: int, p_save_data: Dictionary):
	slot_id = p_slot_id
	save_data = p_save_data

	world_name_label.text = "Loading %s" % save_data.get("world_name", "World %d" % (slot_id + 1))
	progress_bar.value = 5

	call_deferred("_begin_load_async")

func _begin_load_async() -> void:
	progress_bar.value = 10
	status_label.text = "Loading save data..."

	var seed = int(save_data["seed"]) if save_data.has("seed") else SaveManager.generate_random_seed()
	var session := {
		"slot_id": slot_id,
		"seed": seed,
		"world_name": save_data.get("world_name", ""),
		"time_of_day": save_data.get("time_of_day", 6.0)
	}
	var f = FileAccess.open("user://current_session.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session))
		f.close()

	SaveManager.update_last_played(slot_id, save_data)

	await get_tree().process_frame

	progress_bar.value = 20
	status_label.text = "Creating world (Seed %d)... Random terrain" % session["seed"]

	await get_tree().process_frame

	var game_scene = load("res://game/game.tscn") as PackedScene
	game_instance = game_scene.instantiate() as Game
	game_instance.current_slot_id = slot_id
	game_instance.current_save_data = save_data

	var world_node = game_instance.get_node("World") as WorldController
	world_node.auto_generate_on_ready = false
	world_node.set_pending_save_data(save_data)
	world_node.generation_progress.connect(_on_world_generation_progress)

	var parent = get_parent()
	parent.add_child(game_instance)
	parent.move_child(self, parent.get_child_count() - 1)
	status_label.text = "Generating terrain..."

	await world_node.initialize_world_async()
	world_node.generation_progress.disconnect(_on_world_generation_progress)

	progress_bar.value = 90
	status_label.text = "Setting up player and world..."

	await get_tree().process_frame

	game_instance.finalize_deferred_setup()

	progress_bar.value = 100
	status_label.text = "Ready! Entering world..."

	await get_tree().create_timer(0.4).timeout

	get_tree().current_scene = game_instance
	queue_free()

func _on_world_generation_progress(stage: String, percent: float, details: String):
	var p = percent * 100.0
	if p > progress_bar.value:
		progress_bar.value = p
	status_label.text = "%s: %s" % [stage.capitalize(), details]
