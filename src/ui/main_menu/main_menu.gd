extends Control
class_name MainMenu

@onready var play_button: WildesButton = $SplitContainer/RightSide/CenterContainer/PlayButton

var save_slot_scene: PackedScene = preload("res://ui/main_menu/save_slot_screen.tscn")

func _ready():
	play_button.pressed.connect(_open_save_slots)
	play_button.button_text = "PLAY"
	play_button.call_deferred("focus_button")

func _open_save_slots():
	var slot_screen = save_slot_scene.instantiate() as SaveSlotScreen
	var parent = get_parent()
	UiCleanup.free_stray_canvas_layers(parent, self)
	parent.add_child(slot_screen)
	get_tree().current_scene = slot_screen
	queue_free()
