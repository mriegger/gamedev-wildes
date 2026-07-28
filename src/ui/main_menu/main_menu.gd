extends Control
class_name MainMenu

## MainMenu - Split screen: logo left centered, buttons right centered
## Single PLAY button -> SaveSlotScreen with 3 local save slots + random terrain

@onready var play_button: WildesButton = $SplitContainer/RightSide/CenterContainer/PlayButton

var save_slot_scene: PackedScene = preload("res://ui/main_menu/save_slot_screen.tscn")

func _ready():
	print("[MainMenu] Ready - save dir: %s" % SaveManager.SAVE_DIR)
	SaveManager.ensure_save_dir()

	if play_button:
		if not play_button.pressed.is_connected(_on_play_pressed):
			play_button.pressed.connect(_on_play_pressed)
		play_button.button_text = "PLAY"
		play_button.text = "PLAY"
		print("[MainMenu] Play button wired: %s" % play_button.pressed.get_connections())
		play_button.call_deferred("focus_button")

	var slots = SaveManager.get_all_slots()
	var found = 0
	for s in slots:
		if s.get("exists", false):
			found += 1
	print("[MainMenu] Existing saves: %d / %d" % [found, SaveManager.SLOT_COUNT])

func _on_play_pressed():
	print("[MainMenu] PLAY pressed -> opening save slot selection (3 slots)")
	_open_save_slots()

func _open_save_slots():
	var slot_screen = save_slot_scene.instantiate() as SaveSlotScreen
	var parent = get_parent()
	if parent == null:
		parent = get_tree().root
	# Clean any stray game HUD layers that could cause MainMenu+hotbar glitch if Game was not fully freed yet
	for child in parent.get_children():
		if child is CanvasLayer and child != self:
			if child.name in ["HUD", "DebugClockPanel", "SaveStatusLayer", "LoadingScreen"] or child.layer in [1, 20, 100, 200]:
				child.visible = false
				child.queue_free()
		if child is Game:
			child.queue_free()
	parent.add_child(slot_screen)
	get_tree().current_scene = slot_screen
	print("[MainMenu] SaveSlotScreen added, freeing MainMenu - stray HUD cleaned")
	queue_free()
