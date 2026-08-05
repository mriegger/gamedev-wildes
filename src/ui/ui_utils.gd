extends RefCounted
class_name UiUtils

static func is_pointer_over_ui(viewport: Viewport) -> bool:
	if viewport == null:
		return false
	var hovered = viewport.gui_get_hovered_control()
	return hovered != null and hovered.mouse_filter == Control.MOUSE_FILTER_STOP
