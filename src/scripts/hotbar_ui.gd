extends CanvasLayer

# 9-slot hotbar at bottom, selects material if collected
# Shows block color + count, highlights selected slot

@onready var container: HBoxContainer = $MarginContainer/HBoxContainer

var player: Node = null
var slot_nodes: Array = []

var block_colors: Dictionary = {
	0: Color(0.52,0.67,0.40), # GRASS
	1: Color(0.86,0.80,0.62), # SAND
	2: Color(0.66,0.66,0.63), # STONE
	3: Color(0.46,0.38,0.30), # DIRT
	4: Color(0.38,0.29,0.21), # LOG/Wood
	5: Color(0.36,0.52,0.30), # LEAVES
	6: Color(0.94,0.75,0.28), # TORCH
}

func _ready():
	add_to_group("hotbar_ui")
	player = get_tree().get_first_node_in_group("player")
	if player == null:
		# try find after a frame
		call_deferred("_find_player")
	_build_ui()
	refresh()

func _find_player():
	player = get_tree().get_first_node_in_group("player")
	if player:
		refresh()

func _build_ui():
	# if scene already has nodes, keep refs
	if container == null:
		# create fallback UI programmatically
		var margin = MarginContainer.new()
		margin.name = "MarginContainer"
		margin.anchor_left = 0.0
		margin.anchor_top = 1.0
		margin.anchor_right = 1.0
		margin.anchor_bottom = 1.0
		margin.offset_left = 0
		margin.offset_right = 0
		margin.offset_top = -90
		margin.offset_bottom = 0
		var hbox = HBoxContainer.new()
		hbox.name = "HBoxContainer"
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_theme_constant_override("separation", 6)
		margin.add_child(hbox)
		add_child(margin)
		container = hbox
	
	# clear existing
	for c in container.get_children():
		c.queue_free()
	slot_nodes.clear()
	
	for i in range(9):
		var panel = Panel.new()
		panel.custom_minimum_size = Vector2(64,64)
		panel.name = "Slot_%d" % i
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.12,0.12,0.14,0.75)
		style.corner_radius_top_left = 6
		style.corner_radius_top_right = 6
		style.corner_radius_bottom_left = 6
		style.corner_radius_bottom_right = 6
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = Color(0.3,0.3,0.33,0.9)
		panel.add_theme_stylebox_override("panel", style)
		
		# ColorRect for block type
		var color_rect = ColorRect.new()
		color_rect.name = "Color"
		color_rect.custom_minimum_size = Vector2(36,36)
		color_rect.position = Vector2(14,8)
		color_rect.size = Vector2(36,36)
		color_rect.color = Color(0,0,0,0)
		panel.add_child(color_rect)
		
		# Count label
		var lbl = Label.new()
		lbl.name = "Count"
		lbl.position = Vector2(4, 40)
		lbl.size = Vector2(56,18)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.text = ""
		lbl.add_theme_font_size_override("font_size", 14)
		panel.add_child(lbl)
		
		# Key number
		var key_lbl = Label.new()
		key_lbl.name = "Key"
		key_lbl.position = Vector2(2,2)
		key_lbl.text = str(i+1)
		key_lbl.add_theme_font_size_override("font_size", 10)
		key_lbl.modulate = Color(0.7,0.7,0.7,0.8)
		panel.add_child(key_lbl)
		
		container.add_child(panel)
		slot_nodes.append(panel)

func refresh():
	if container == null or slot_nodes.size() == 0:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	
	var hotbar = player.hotbar if "hotbar" in player else []
	var selected = player.selected_slot if "selected_slot" in player else 0
	
	for i in range(9):
		if i >= slot_nodes.size():
			continue
		var panel: Panel = slot_nodes[i]
		var color_rect: ColorRect = panel.get_node_or_null("Color") as ColorRect
		var count_lbl: Label = panel.get_node_or_null("Count") as Label
		var style: StyleBoxFlat = panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			continue
		
		# highlight selected
		if i == selected:
			style.border_color = Color(1,1,0.55,1.0)
			style.bg_color = Color(0.22,0.22,0.18,0.9)
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
		else:
			style.border_color = Color(0.3,0.3,0.33,0.9)
			style.bg_color = Color(0.12,0.12,0.14,0.75)
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
		
		var slot_data = null
		if i < hotbar.size():
			slot_data = hotbar[i]
		
		if slot_data == null:
			if color_rect:
				color_rect.color = Color(0,0,0,0)
			if count_lbl:
				count_lbl.text = ""
		else:
			var t = slot_data["type"]
			var c = slot_data["count"]
			if color_rect:
				color_rect.color = block_colors.get(t, Color(1,0,1,1))
				# add slight shading for top/side distinction visually? keep flat
			if count_lbl:
				count_lbl.text = str(c) if c > 1 else ""
				if c <= 0:
					count_lbl.text = ""

func pop_slot(idx: int):
	if idx <0 or idx >= slot_nodes.size():
		return
	var panel = slot_nodes[idx]
	if not panel:
		return
	# scale pop tween
	var tween = get_tree().create_tween()
	panel.pivot_offset = panel.size * 0.5
	tween.tween_property(panel, "scale", Vector2(1.35,1.35), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "scale", Vector2(1.0,1.0), 0.18).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	refresh()

func _process(_delta):
	pass
