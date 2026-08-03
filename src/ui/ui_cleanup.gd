extends RefCounted
class_name UiCleanup

const STRAY_CANVAS_NAMES: Array[String] = ["HUD", "DebugClockPanel", "SaveStatusLayer", "LoadingScreen", "Hotbar"]
const STRAY_CANVAS_LAYERS: Array[int] = [1, 20, 100, 200]

static func is_stray_canvas_layer(node: Node) -> bool:
	if node is CanvasLayer:
		var cl = node as CanvasLayer
		if cl.name in STRAY_CANVAS_NAMES:
			return true
		if cl.layer in STRAY_CANVAS_LAYERS:
			return true
	return false

static func free_stray_canvas_layers(root: Node, exclude: Node = null) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child == exclude:
			continue
		if is_stray_canvas_layer(child):
			if is_instance_valid(child):
				child.visible = false
				child.queue_free()
