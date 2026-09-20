class_name TopAppBar
extends Control

signal settings_pressed

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")

@onready var bar: PanelContainer = %Bar
@onready var shell_margin: MarginContainer = %ShellMargin
@onready var bar_margin: MarginContainer = $ShellMargin/Bar/BarMargin
@onready var brand_row: HBoxContainer = $ShellMargin/Bar/BarMargin/BarRow/Brand
@onready var logo_texture: TextureRect = %LogoTexture
@onready var wordmark_texture: TextureRect = %WordmarkTexture
@onready var title_label: Label = %TitleLabel
@onready var settings_button: Button = %SettingsButton


var _base_top_pad: int = 0


func _ready() -> void:
	clip_contents = false
	custom_minimum_size.y = UiTokens.HEADER_SHELL_HEIGHT
	shell_margin.add_theme_constant_override("margin_left", UiTokens.HEADER_SHELL_MARGIN_H)
	shell_margin.add_theme_constant_override("margin_right", UiTokens.HEADER_SHELL_MARGIN_H)
	shell_margin.add_theme_constant_override("margin_top", UiTokens.HEADER_SHELL_MARGIN_TOP)
	shell_margin.add_theme_constant_override("margin_bottom", UiTokens.HEADER_SHELL_MARGIN_BOTTOM)
	bar.custom_minimum_size.y = UiTokens.HEADER_BANNER_HEIGHT
	bar.add_theme_stylebox_override("panel", UiStyle.header_bar())
	var vertical_pad := int(round((UiTokens.HEADER_BANNER_HEIGHT - UiTokens.HEADER_LOGO_SIZE) * 0.5))
	vertical_pad = maxi(vertical_pad, 0)
	var side_pad := int(UiTokens.HEADER_SIDE_PADDING)
	bar_margin.add_theme_constant_override("margin_left", side_pad)
	bar_margin.add_theme_constant_override("margin_right", side_pad)
	bar_margin.add_theme_constant_override("margin_top", vertical_pad)
	bar_margin.add_theme_constant_override("margin_bottom", vertical_pad)
	_configure_brand_row()
	_configure_logo()
	_configure_wordmark()
	_configure_title()
	_configure_settings_button()
	_apply_translations()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	PressScaleUtil.wire(settings_button, self)
	_base_top_pad = bar_margin.get_theme_constant("margin_top")
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()


## The bar keeps its colour under the status bar / notch; only its content moves down.
func _apply_safe_area() -> void:
	custom_minimum_size.y = UiTokens.HEADER_SHELL_HEIGHT + SafeArea.top
	bar.custom_minimum_size.y = UiTokens.HEADER_BANNER_HEIGHT + SafeArea.top
	bar_margin.add_theme_constant_override("margin_top", _base_top_pad + int(SafeArea.top))


func _configure_brand_row() -> void:
	brand_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	brand_row.add_theme_constant_override("separation", UiTokens.HEADER_BRAND_SEPARATION)
	brand_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar_row: HBoxContainer = bar_margin.get_node("BarRow") as HBoxContainer
	if bar_row != null:
		bar_row.alignment = BoxContainer.ALIGNMENT_CENTER
		bar_row.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _configure_logo() -> void:
	var logo_size := Vector2.ONE * UiTokens.HEADER_LOGO_SIZE
	logo_texture.custom_minimum_size = logo_size
	logo_texture.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	logo_texture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	logo_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(UiTokens.APP_LOGO_PATH):
		logo_texture.texture = load(UiTokens.APP_LOGO_PATH)
		logo_texture.visible = true
	else:
		logo_texture.visible = false


func _configure_wordmark() -> void:
	wordmark_texture.custom_minimum_size = Vector2(
		UiTokens.HEADER_WORDMARK_WIDTH,
		UiTokens.HEADER_WORDMARK_HEIGHT
	)
	wordmark_texture.size_flags_horizontal = Control.SIZE_FILL
	wordmark_texture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wordmark_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wordmark_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wordmark_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	wordmark_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wordmark_texture.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	if ResourceLoader.exists(UiTokens.APP_WORDMARK_PATH):
		wordmark_texture.texture = load(UiTokens.APP_WORDMARK_PATH)
		wordmark_texture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		wordmark_texture.visible = true
	else:
		wordmark_texture.visible = false


func _configure_title() -> void:
	## Name/tagline come from the BrainUp wordmark asset.
	title_label.visible = false
	title_label.text = ""


func _configure_settings_button() -> void:
	var tile_size := Vector2.ONE * UiTokens.HEADER_SETTINGS_SIZE
	settings_button.custom_minimum_size = tile_size
	settings_button.size = tile_size
	settings_button.text = ""
	settings_button.flat = true
	settings_button.expand_icon = true
	settings_button.icon = load(UiTokens.APP_SETTINGS_ICON_PATH)
	settings_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_button.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	settings_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	settings_button.focus_mode = Control.FOCUS_ALL
	settings_button.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_button.add_theme_constant_override("icon_max_width", UiTokens.HEADER_SETTINGS_ICON_SIZE)
	settings_button.add_theme_constant_override("h_separation", 0)
	settings_button.add_theme_color_override("icon_normal_color", Color.WHITE)
	settings_button.add_theme_color_override("icon_hover_color", Color(1, 1, 1, 0.85))
	settings_button.add_theme_color_override("icon_pressed_color", Color(1, 1, 1, 0.7))
	var empty := StyleBoxEmpty.new()
	settings_button.add_theme_stylebox_override("normal", empty)
	settings_button.add_theme_stylebox_override("hover", empty)
	settings_button.add_theme_stylebox_override("pressed", empty)
	settings_button.add_theme_stylebox_override("focus", empty)
	if not settings_button.pressed.is_connected(_on_settings_pressed):
		settings_button.pressed.connect(_on_settings_pressed)


func _apply_translations() -> void:
	settings_button.tooltip_text = tr("UI_SETTINGS")


func release_settings_focus() -> void:
	settings_button.release_focus()


func _on_settings_pressed() -> void:
	settings_pressed.emit()


func _on_locale_changed(_locale: String) -> void:
	_apply_translations()
