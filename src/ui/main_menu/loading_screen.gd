extends CanvasLayer
class_name LoadingScreen

@onready var world_name_label: Label = $Control/CenterContainer/FrostedPanel/VBox/WorldNameLabel
@onready var progress_bar: ProgressBar = $Control/CenterContainer/FrostedPanel/VBox/ProgressBar
@onready var status_label: Label = $Control/CenterContainer/FrostedPanel/VBox/StatusLabel

var slot_id: int = -1
var save_data: Dictionary = {}
var game_instance: Game = null

var _game_scene: PackedScene = preload("res://game/game.tscn")

func _ready():
	layer = 200
	if progress_bar:
		progress_bar.value = 0
		progress_bar.min_value = 0
		progress_bar.max_value = 100
		progress_bar.show_percentage = true
	if status_label:
		status_label.text = "Preparing..."

func start_loading(p_slot_id: int, p_save_data: Dictionary):
	slot_id = p_slot_id
	save_data = p_save_data

	if world_name_label:
		world_name_label.text = "Loading %s" % save_data.get("world_name", "World %d" % (slot_id + 1))
		world_name_label.visible = true

	if progress_bar:
		progress_bar.value = 5

	call_deferred("_begin_load_async")

func _begin_load_async() -> void:
	if progress_bar:
		progress_bar.value = 10
	if status_label:
		status_label.text = "Loading save data..."

	SaveManager.ensure_save_dir()

	var session := {
		"slot_id": slot_id,
		"seed": save_data.get("seed", SaveManager.generate_random_seed()),
		"world_name": save_data.get("world_name", ""),
		"time_of_day": save_data.get("time_of_day", 6.0)
	}
	var f = FileAccess.open("user://current_session.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(session))
		f.close()

	SaveManager.touch_last_played(slot_id)

	await get_tree().process_frame

	if progress_bar:
		progress_bar.value = 20
	if status_label:
		status_label.text = "Creating world (Seed %d)... Random terrain" % session["seed"]

	await get_tree().process_frame

	game_instance = _game_scene.instantiate() as Game
	game_instance.current_slot_id = slot_id
	game_instance.current_save_data = save_data

	var world_node = game_instance.get_node_or_null("World") as WorldController
	if world_node:
		world_node.auto_generate_on_ready = false
		world_node.set_pending_save_data(save_data)
		if not world_node.generation_progress.is_connected(_on_world_generation_progress):
			world_node.generation_progress.connect(_on_world_generation_progress)

	var parent = get_parent()
	if parent == null:
		parent = get_tree().root
	parent.add_child(game_instance)

	if parent:
		parent.move_child(self, parent.get_child_count() - 1)

	if status_label:
		status_label.text = "Generating terrain..."

	if world_node:
		await world_node.initialize_world_async()
		world_node.generation_progress.disconnect(_on_world_generation_progress)

	if progress_bar:
		progress_bar.value = 90
	if status_label:
		status_label.text = "Setting up player and world..."

	await get_tree().process_frame

	if game_instance.has_method("finalize_deferred_setup"):
		game_instance.finalize_deferred_setup()

	if progress_bar:
		progress_bar.value = 100
	if status_label:
		status_label.text = "Ready! Entering world..."

	await get_tree().create_timer(0.4).timeout

	get_tree().current_scene = game_instance
	queue_free()

func _on_world_generation_progress(stage: String, percent: float, details: String):
	if progress_bar:
		var p = percent * 100.0
		if p > progress_bar.value:
			progress_bar.value = p
	if status_label:
		status_label.text = "%s: %s" % [stage.capitalize(), details]
