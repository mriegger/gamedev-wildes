extends SceneTree

func _init():
	print("[CreateTheme] Creating Wildes theme with Roboto Slab")

	var regular_font_path = "res://assets/fonts/RobotoSlab-Regular.ttf"
	var bold_font_path = "res://assets/fonts/RobotoSlab-Bold.ttf"
	var semibold_font_path = "res://assets/fonts/RobotoSlab-SemiBold.ttf"

	var regular_font = load(regular_font_path) as FontFile
	if regular_font == null:
		print("[CreateTheme] Failed to load regular font at %s, trying via FontFile" % regular_font_path)
		regular_font = FontFile.new()
		# Try to set data? But load should work after import

	var theme = Theme.new()
	if regular_font:
		theme.default_font = regular_font
		theme.default_font_size = 16
		print("[CreateTheme] Set default font to Roboto Slab Regular")

	# Set for common control types
	# Label
	theme.set_font("font", "Label", regular_font)
	theme.set_font_size("font_size", "Label", 16)
	# Button
	theme.set_font("font", "Button", regular_font)
	theme.set_font_size("font_size", "Button", 14)
	# LineEdit
	theme.set_font("font", "LineEdit", regular_font)
	# ProgressBar
	theme.set_font("font", "ProgressBar", regular_font)

	# Save theme
	var save_path = "res://ui/theme/wildes_theme.tres"
	var err = ResourceSaver.save(theme, save_path)
	if err == OK:
		print("[CreateTheme] Theme saved to %s" % save_path)
	else:
		print("[CreateTheme] Failed to save theme, err=%d" % err)

	quit(0)
