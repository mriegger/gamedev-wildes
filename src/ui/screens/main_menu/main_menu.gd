extends Control
class_name MainMenu

signal play_requested
signal settings_requested

const REGULAR_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Regular.ttf")
const BOLD_FONT: FontFile = preload("res://assets/fonts/RobotoSlab-Bold.ttf")
const LOADING_BAR_WIDTH_RATIO := 0.34
const LOADING_BAR_MIN_WIDTH := 260.0
const LOADING_BAR_MAX_WIDTH := 460.0
const LOADING_BAR_HORIZONTAL_MARGIN := 32.0
const STARTUP_LOADING_BAR_TOP := 78.0
const STARTUP_LOADING_BAR_BOTTOM := 82.0
const CENTERED_LOADING_BAR_TOP := -2.0
const CENTERED_LOADING_BAR_BOTTOM := 2.0

@onready var logo: TextureRect = $LogoGroup/Logo
@onready var logo_shadow: TextureRect = $LogoGroup/Shadow
@onready var loading_bar: ProgressBar = $LoadingBar
@onready var controls: VBoxContainer = $Controls
@onready var play_button: Button = $Controls/PlayButton
@onready var settings_button: Button = $Controls/SettingsButton
@onready var play_shadow: Label = $Controls/PlayButton/Shadow
@onready var settings_shadow: Label = $Controls/SettingsButton/Shadow
@onready var credits: Label = $Credits

func _ready() -> void:
	resized.connect(_resize_loading_bar)
	play_button.pressed.connect(play_requested.emit)
	settings_button.pressed.connect(settings_requested.emit)
	_setup_text_button(play_button, play_shadow)
	_setup_text_button(settings_button, settings_shadow)
	_resize_loading_bar()

func set_logo_alpha(alpha: float) -> void:
	var clamped := clampf(alpha, 0.0, 1.0)
	logo.modulate.a = clamped
	logo_shadow.modulate.a = clamped

func set_loading_progress(progress: float) -> void:
	loading_bar.value = maxf(loading_bar.value, clampf(progress, 0.0, 1.0) * 100.0)

func set_loading_bar_alpha(alpha: float) -> void:
	var clamped := clampf(alpha, 0.0, 1.0)
	loading_bar.modulate.a = clamped
	loading_bar.visible = clamped > 0.0

func set_loading_bar_centered_overlay(enabled: bool) -> void:
	loading_bar.z_index = 1 if enabled else 0
	loading_bar.offset_top = CENTERED_LOADING_BAR_TOP if enabled else STARTUP_LOADING_BAR_TOP
	loading_bar.offset_bottom = CENTERED_LOADING_BAR_BOTTOM if enabled else STARTUP_LOADING_BAR_BOTTOM
	loading_bar.accessibility_name = "Loading main menu" if enabled else "Loading menu world"

func set_loading_description(description: String) -> void:
	loading_bar.accessibility_description = description

func set_controls_alpha(alpha: float) -> void:
	var clamped := clampf(alpha, 0.0, 1.0)
	controls.modulate.a = clamped
	credits.modulate.a = clamped

func set_interaction_enabled(enabled: bool) -> void:
	play_button.disabled = not enabled
	settings_button.disabled = not enabled
	mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE

func focus_play() -> void:
	play_button.grab_focus()

func focus_settings() -> void:
	settings_button.grab_focus()

func _resize_loading_bar() -> void:
	var available_width := maxf(size.x - LOADING_BAR_HORIZONTAL_MARGIN, 4.0)
	var bar_width := minf(
		clampf(size.x * LOADING_BAR_WIDTH_RATIO, LOADING_BAR_MIN_WIDTH, LOADING_BAR_MAX_WIDTH),
		available_width,
	)
	loading_bar.custom_minimum_size = Vector2(bar_width, loading_bar.custom_minimum_size.y)
	loading_bar.offset_left = bar_width * -0.5
	loading_bar.offset_right = bar_width * 0.5

func _setup_text_button(button: Button, shadow: Label) -> void:
	button.add_theme_font_override(&"font", REGULAR_FONT)
	shadow.add_theme_font_override(&"font", REGULAR_FONT)
	button.mouse_entered.connect(_refresh_button_fonts)
	button.mouse_exited.connect(_refresh_button_fonts)
	button.focus_entered.connect(_refresh_button_fonts)
	button.focus_exited.connect(_refresh_button_fonts)

func _refresh_button_fonts() -> void:
	var any_hovered := play_button.is_hovered() or settings_button.is_hovered()
	for button in [play_button, settings_button]:
		var emphasized: bool = button.is_hovered() or (not any_hovered and button.has_focus())
		var font := BOLD_FONT if emphasized else REGULAR_FONT
		button.add_theme_font_override(&"font", font)
		var shadow := play_shadow if button == play_button else settings_shadow
		shadow.add_theme_font_override(&"font", font)
