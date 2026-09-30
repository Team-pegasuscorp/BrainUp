class_name ShopPage
extends Control

## Full-screen shop opened from the top bar. Catalogue is still empty: each
## section (avatars, frames) shows a "coming soon" card until items exist.

signal closed

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")

const ACCENT := UiTokens.PODIUM_GOLD
const SECTIONS: Array[Dictionary] = [
	{"id": "avatars", "title": "UI_SHOP_AVATARS", "icon": "🙂"},
	{"id": "frames", "title": "UI_SHOP_FRAMES", "icon": "✨"},
]

var _margin: MarginContainer
var _content: VBoxContainer
var _back_button: Button


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tab_page_bg.gdshader") as Shader
	mat.set_shader_parameter("accent", ACCENT)
	mat.set_shader_parameter("deep", UiTokens.BG_CREAM)
	bg.material = mat
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	_margin.add_child(column)

	_back_button = Button.new()
	_back_button.focus_mode = Control.FOCUS_ALL
	_back_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_back_button.pressed.connect(close)
	column.add_child(_back_button)
	PressScaleUtil.wire(_back_button, self)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 16)
	scroll.add_child(_content)

	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()
	LocaleManager.locale_changed.connect(func(_locale: String) -> void: _rebuild())
	_rebuild()


func open() -> void:
	_rebuild()
	visible = true
	move_to_front()
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _apply_safe_area() -> void:
	_margin.add_theme_constant_override("margin_left", 20)
	_margin.add_theme_constant_override("margin_right", 20)
	_margin.add_theme_constant_override("margin_top", 16 + int(SafeArea.top))
	_margin.add_theme_constant_override("margin_bottom", 16 + int(SafeArea.bottom))


func _rebuild() -> void:
	_back_button.text = "‹  " + tr("UI_BACK")
	for child in _content.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = tr("UI_SHOP")
	title.add_theme_font_size_override("font_size", UiScale.font(34))
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	_content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = tr("UI_SHOP_SUBTITLE")
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", UiScale.font(17))
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	_content.add_child(subtitle)

	for section in SECTIONS:
		_content.add_child(_build_section(section))

	ScrollTouch.let_drags_through(_content)


func _build_section(section: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var heading := Label.new()
	heading.text = tr(str(section["title"])).to_upper()
	heading.add_theme_font_size_override("font_size", UiScale.font(15))
	heading.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	box.add_child(heading)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiStyle.profile_surface(ACCENT, false, 22))
	box.add_child(card)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	inner.add_theme_constant_override("separation", 6)
	inner.custom_minimum_size.y = 150
	card.add_child(inner)

	var icon := Label.new()
	icon.text = str(section["icon"])
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", UiScale.font(36))
	inner.add_child(icon)

	var empty := Label.new()
	empty.text = tr("UI_SHOP_EMPTY")
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.add_theme_font_size_override("font_size", UiScale.font(20))
	empty.add_theme_color_override("font_color", ACCENT)
	inner.add_child(empty)

	var hint := Label.new()
	hint.text = tr("UI_SHOP_EMPTY_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UiScale.font(15))
	hint.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	inner.add_child(hint)
	return box
