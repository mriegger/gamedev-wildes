extends Control
class_name MainMenu

@onready var play_button: WildesButton = $SplitContainer/RightSide/CenterContainer/PlayButton

var save_slot_scene: PackedScene = preload("res://ui/main_menu/save_slot_screen.tscn")

func _ready():
	SaveManager.ensure_save_dir()

	if play_button:
		if not play_button.pressed.is_connected(_on_play_pressed):
			play_button.pressed.connect(_on_play_pressed)
		play_button.button_text = "PLAY"
		play_button.call_deferred("focus_button")

func _on_play_pressed():
	_open_save_slots()

func _open_save_slots():
	var slot_screen = save_slot_scene.instantiate() as SaveSlotScreen
	var parent = get_parent()
	if parent == null:
		parent = get_tree().root
	UiCleanup.free_stray_canvas_layers(parent, self)
	for child in parent.get_children():
		if child is Game:
			child.queue_free()
	parent.add_child(slot_screen)
	get_tree().current_scene = slot_screen
	queue_free()
