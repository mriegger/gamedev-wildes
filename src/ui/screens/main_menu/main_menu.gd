extends Control
class_name MainMenu

signal play_requested

@onready var play_button: WildesButton = $SplitContainer/RightSide/CenterContainer/PlayButton

func _ready():
	play_button.pressed.connect(_on_play_pressed)
	play_button.call_deferred("focus_button")

func _on_play_pressed():
	play_requested.emit()
