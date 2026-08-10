extends Control
class_name SettingsScreen

signal settings_changed(settings: GameSettings)
signal back_requested

@onready var frame_rate: OptionButton = $VBox/SettingsGrid/FrameRate
@onready var render_scale: OptionButton = $VBox/SettingsGrid/RenderScale
@onready var anti_aliasing: OptionButton = $VBox/SettingsGrid/AntiAliasing
@onready var volumetric_fog: CheckButton = $VBox/SettingsGrid/VolumetricFog
@onready var sun_shadows: CheckButton = $VBox/SettingsGrid/SunShadows
@onready var shadow_range: OptionButton = $VBox/SettingsGrid/ShadowRange
@onready var torch_shadows: OptionButton = $VBox/SettingsGrid/TorchShadows
@onready var ambient_volume: HSlider = $VBox/SettingsGrid/AmbientVolume
@onready var birds_enabled: CheckButton = $VBox/SettingsGrid/BirdsEnabled
@onready var back_button: WildesButton = $VBox/BackButton

var _settings: GameSettings
var _syncing := false

func _ready():
	_populate_options()
	_style_options()
	frame_rate.item_selected.connect(_on_frame_rate_selected)
	render_scale.item_selected.connect(_on_render_scale_selected)
	anti_aliasing.item_selected.connect(_on_anti_aliasing_selected)
	volumetric_fog.toggled.connect(_on_volumetric_fog_toggled)
	sun_shadows.toggled.connect(_on_sun_shadows_toggled)
	shadow_range.item_selected.connect(_on_shadow_range_selected)
	torch_shadows.item_selected.connect(_on_torch_shadows_selected)
	ambient_volume.value_changed.connect(_on_ambient_volume_changed)
	birds_enabled.toggled.connect(_on_birds_enabled_toggled)
	back_button.pressed.connect(back_requested.emit)

func setup(settings: GameSettings):
	_settings = settings
	_sync_controls()

func focus_first_control():
	frame_rate.grab_focus()

func _populate_options():
	_add_option(frame_rate, "60 FPS", 60)
	_add_option(frame_rate, "90 FPS", 90)
	_add_option(frame_rate, "120 FPS", 120)
	_add_option(frame_rate, "Unlimited", 0)
	_add_option(render_scale, "75%", 0.75)
	_add_option(render_scale, "85%", 0.85)
	_add_option(render_scale, "100%", 1.0)
	_add_option(anti_aliasing, "Off", GameSettings.ANTI_ALIASING_OFF)
	_add_option(anti_aliasing, "FXAA", GameSettings.ANTI_ALIASING_FXAA)
	_add_option(anti_aliasing, "TAA", GameSettings.ANTI_ALIASING_TAA)
	_add_option(shadow_range, "Low", GameSettings.SHADOW_RANGE_LOW)
	_add_option(shadow_range, "Medium", GameSettings.SHADOW_RANGE_MEDIUM)
	_add_option(shadow_range, "High", GameSettings.SHADOW_RANGE_HIGH)
	_add_option(torch_shadows, "Off", 0)
	_add_option(torch_shadows, "Nearest 1", 1)
	_add_option(torch_shadows, "Nearest 2", 2)
	_add_option(torch_shadows, "Nearest 4", 4)

func _style_options():
	for option in [frame_rate, render_scale, anti_aliasing, shadow_range, torch_shadows]:
		option.add_theme_stylebox_override("normal", WildesStyle.make_panel(Color(0.20, 0.22, 0.24, 0.52), 8, Color(1, 1, 1, 0.18), 1))
		option.add_theme_stylebox_override("hover", WildesStyle.make_panel(Color(1, 1, 1, 0.10), 8, Color(1, 1, 1, 0.24), 1))

func _add_option(option: OptionButton, label: String, value: Variant):
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, value)

func _sync_controls():
	if _settings == null or not is_node_ready():
		return
	_syncing = true
	_select_value(frame_rate, _settings.frame_rate_limit)
	_select_value(render_scale, _settings.render_scale)
	_select_value(anti_aliasing, _settings.anti_aliasing)
	volumetric_fog.set_pressed_no_signal(_settings.volumetric_fog_enabled)
	sun_shadows.set_pressed_no_signal(_settings.sun_shadows_enabled)
	_select_value(shadow_range, _settings.shadow_range)
	_select_value(torch_shadows, _settings.torch_shadow_count)
	ambient_volume.set_value_no_signal(_settings.ambient_volume)
	birds_enabled.set_pressed_no_signal(_settings.birds_enabled)
	_syncing = false

func _select_value(option: OptionButton, value: Variant):
	for index in range(option.item_count):
		if option.get_item_metadata(index) == value:
			option.select(index)
			return

func _emit_change():
	if not _syncing:
		settings_changed.emit(_settings)

func _on_frame_rate_selected(index: int):
	_settings.frame_rate_limit = int(frame_rate.get_item_metadata(index))
	_emit_change()

func _on_render_scale_selected(index: int):
	_settings.render_scale = float(render_scale.get_item_metadata(index))
	_emit_change()

func _on_anti_aliasing_selected(index: int):
	_settings.anti_aliasing = int(anti_aliasing.get_item_metadata(index))
	_emit_change()

func _on_volumetric_fog_toggled(enabled: bool):
	_settings.volumetric_fog_enabled = enabled
	_emit_change()

func _on_sun_shadows_toggled(enabled: bool):
	_settings.sun_shadows_enabled = enabled
	_emit_change()

func _on_shadow_range_selected(index: int):
	_settings.shadow_range = int(shadow_range.get_item_metadata(index))
	_emit_change()

func _on_torch_shadows_selected(index: int):
	_settings.torch_shadow_count = int(torch_shadows.get_item_metadata(index))
	_emit_change()

func _on_ambient_volume_changed(value: float):
	_settings.ambient_volume = value
	_emit_change()

func _on_birds_enabled_toggled(enabled: bool):
	_settings.birds_enabled = enabled
	_emit_change()
