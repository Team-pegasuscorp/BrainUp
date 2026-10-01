extends Control

signal back_requested

const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const DailyChallenge = preload("res://scripts/profile/daily_challenge.gd")
const UiFonts = preload("res://scripts/config/ui_fonts.gd")

@export var embedded_mode: bool = false
## The Quiz tab only launches ranked duels: pick a mode, Play searches an opponent and
## the category is drafted in the match. The standalone scene keeps the old solo list.
var _duel_only: bool:
	get:
		return embedded_mode

@onready var background: ColorRect = $Background
@onready var title_label: Label = %TitleLabel
@onready var category_list: VBoxContainer = %CategoryList
@onready var back_button: Button = %BackButton
@onready var description_label: Label = %DescriptionLabel
@onready var start_button: Button = %StartButton

var categories: Array[Dictionary] = []
var _selected_index: int = 0
var _tile_buttons: Array[Button] = []
var _daily: Dictionary = {}
var _daily_card: PanelContainer
var _daily_fetching: bool = false
var _daily_board: Dictionary = {}
var _daily_board_failed: bool = false
var _daily_resubmitted: bool = false
var _board_overlay: Control
var _scroll_content: VBoxContainer
var _mode_buttons: Dictionary = {}
var _mode_icon_labels: Dictionary = {} ## mode_id -> Label
var _mode_name_labels: Dictionary = {} ## mode_id -> Label
var _mode_hint: Label
var _mode_section_label: Label
var _mode_row: HBoxContainer
var _duel_tiles: VBoxContainer

## Mode chips: [mode, label key, hint key, icon].
const MODES := [
	[0, "UI_MODE_CLASSIC", "UI_MODE_CLASSIC_HINT", "🎯"],
	[1, "UI_MODE_SURVIVAL", "UI_MODE_SURVIVAL_HINT", "❤️"],
	[2, "UI_MODE_TIME_ATTACK", "UI_MODE_TIME_ATTACK_HINT", "⏱️"],
]
## Room inside ScrollContainer so selected-tile neon isn't clipped.
const TILE_GLOW_PAD := 12
const PRIMARY_CATEGORY_ID := "general"


func _ready() -> void:
	_wrap_list_in_scroll()
	_build_mode_picker()
	_apply_embedded_layout()
	_apply_translations()
	_load_categories()
	if embedded_mode:
		_setup_daily_card()
	if _duel_only:
		_build_duel_tiles()
	back_button.pressed.connect(_on_back_pressed)
	start_button.pressed.connect(_on_start_pressed)
	LocaleManager.locale_changed.connect(_on_locale_changed)
	PressScaleUtil.wire(start_button, self)
	if not embedded_mode:
		PressScaleUtil.wire(back_button, self)


## The list (and daily card) scroll when they do not fit; the Play button stays pinned.
func _wrap_list_in_scroll() -> void:
	var column := category_list.get_parent()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	column.add_child(scroll)
	column.move_child(scroll, category_list.get_index())

	## Outer page margin is reduced by the same amount so tile width stays stable.
	var glow_pad := MarginContainer.new()
	glow_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glow_pad.add_theme_constant_override("margin_left", TILE_GLOW_PAD)
	glow_pad.add_theme_constant_override("margin_right", TILE_GLOW_PAD)
	glow_pad.add_theme_constant_override("margin_top", TILE_GLOW_PAD)
	glow_pad.add_theme_constant_override("margin_bottom", TILE_GLOW_PAD)
	scroll.add_child(glow_pad)

	_scroll_content = VBoxContainer.new()
	_scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_content.add_theme_constant_override("separation", 16)
	glow_pad.add_child(_scroll_content)
	category_list.reparent(_scroll_content)
	category_list.size_flags_vertical = Control.SIZE_FILL


## Mode chips and a hint line (rules + personal record), pinned above Play.
func _build_mode_picker() -> void:
	var column := start_button.get_parent()

	_mode_section_label = Label.new()
	_mode_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_section_label.add_theme_font_size_override("font_size", UiScale.font(20))
	_mode_section_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	column.add_child(_mode_section_label)
	column.move_child(_mode_section_label, start_button.get_index())

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	column.move_child(row, start_button.get_index())
	_mode_row = row
	for entry in MODES:
		var mode_id := int(entry[0])
		var chip := Button.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.custom_minimum_size.y = 72
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(_on_mode_selected.bind(mode_id))
		PressScaleUtil.wire(chip, self)
		row.add_child(chip)
		_mode_buttons[mode_id] = chip

		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 4)
		col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(col)

		var icon := Label.new()
		icon.text = str(entry[3])
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_theme_font_size_override("font_size", UiScale.font(26))
		var emoji_font := UiFonts.emoji_font()
		if emoji_font != null:
			icon.add_theme_font_override("font", emoji_font)
		col.add_child(icon)
		_mode_icon_labels[mode_id] = icon

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", UiScale.font(17))
		col.add_child(name_label)
		_mode_name_labels[mode_id] = name_label

	_mode_hint = Label.new()
	_mode_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mode_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_hint.add_theme_font_size_override("font_size", UiScale.font(18))
	_mode_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	column.add_child(_mode_hint)
	column.move_child(_mode_hint, start_button.get_index())


func _on_mode_selected(mode: int) -> void:
	GameManager.selected_mode = mode
	_refresh_mode_picker()


func _refresh_mode_picker() -> void:
	if _mode_section_label != null:
		_mode_section_label.text = tr("UI_MODE_PICKER_TITLE").to_upper()
	for entry in MODES:
		var mode_id := int(entry[0])
		var chip: Button = _mode_buttons[mode_id]
		var selected := mode_id == GameManager.selected_mode
		var accent: Color = UiTokens.MODE_ACCENTS[mode_id]
		var name_label: Label = _mode_name_labels[mode_id]
		name_label.text = tr(str(entry[1]))
		for state in ["normal", "hover", "pressed", "focus"]:
			chip.add_theme_stylebox_override(state, _mode_chip_style(accent, selected))
		## Hide default button caption — labels are owned by the inner VBox.
		chip.text = ""
		chip.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		chip.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
		chip.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))
		chip.add_theme_color_override("font_focus_color", Color(0, 0, 0, 0))
		name_label.add_theme_color_override(
			"font_color",
			Color(0.08, 0.06, 0.12, 1) if selected else Color(1, 1, 1, 0.88)
		)
		if selected:
			var hint_key := str(entry[2]).replace("UI_MODE_", "UI_DUEL_") if _duel_only else str(entry[2])
			_mode_hint.text = tr(hint_key) + _record_text()
			_mode_hint.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.95))
	_sync_play_button_to_mode()


func _mode_chip_style(accent: Color, selected: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = accent
		style.set_border_width_all(3)
		style.border_color = Color(1, 1, 1, 0.92)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.45)
		style.shadow_size = 12
	else:
		style.bg_color = Color(accent.r, accent.g, accent.b, 0.16)
		style.set_border_width_all(2)
		style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
		style.shadow_size = 4
	style.set_corner_radius_all(16)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.shadow_offset = Vector2(0, 3)
	return style


func _sync_play_button_to_mode() -> void:
	var accent: Color = UiTokens.MODE_ACCENTS[GameManager.selected_mode]
	var deep := accent.darkened(0.22)
	var hover := accent.lightened(0.12)
	for state_accent in [
		["normal", accent],
		["hover", hover],
		["focus", hover],
		["pressed", deep],
	]:
		var style := UiStyle.filled(state_accent[1] as Color, 22)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.28 if state_accent[0] != "pressed" else 0.12)
		style.shadow_size = 10
		style.shadow_offset = Vector2(0, 4)
		start_button.add_theme_stylebox_override(str(state_accent[0]), style)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		start_button.add_theme_color_override(slot, Color(0.08, 0.06, 0.12, 1))


## " · Record: 1 234 pts (12 ✓)" for survival / time attack in the selected category.
func _record_text() -> String:
	if _duel_only or GameManager.selected_mode == GameManager.Mode.CLASSIC:
		return ""
	if _selected_index < 0 or _selected_index >= categories.size():
		return ""
	var mode_key := str(GameManager.MODE_KEYS[GameManager.selected_mode])
	var record: Dictionary = SaveManager.get_mode_record(mode_key, str(categories[_selected_index].get("id", "")))
	if record.is_empty():
		return "\n" + tr("UI_MODE_NO_RECORD")
	return "\n" + tr("UI_MODE_RECORD").format({"score": int(record.get("score", 0)), "correct": int(record.get("correct", 0))})


func _apply_embedded_layout() -> void:
	if not embedded_mode:
		return
	background.visible = false
	## The embedded page sits on the dark shell, so the title must be light.
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	back_button.visible = false
	description_label.visible = false
	## Keep Play above the floating Quiz FAB (shell safe-zone still overlaps that band).
	var page_margin := $MarginContainer as MarginContainer
	if page_margin != null:
		page_margin.add_theme_constant_override(
			"margin_bottom",
			8 + int(UiTokens.BOTTOM_NAV_FAB_CLEARANCE * 0.55)
		)


func _apply_translations() -> void:
	title_label.visible = false
	title_label.text = tr("UI_CHOOSE_CATEGORY")
	back_button.text = tr("UI_BACK")
	start_button.text = tr("UI_PLAY").to_upper()
	if _mode_hint != null:
		_refresh_mode_picker()


func refresh() -> void:
	_apply_translations()
	_load_categories()
	if _daily_card != null:
		_render_daily()
	if _duel_only:
		_build_duel_tiles()


# --- Duel tiles (Quiz tab) --------------------------------------------------

## Rank strip, one tile per duel mode (tap = search an opponent), then the daily
## challenge tile. Replaces the old mode chips + Play button.
func _build_duel_tiles() -> void:
	for node in [_mode_section_label, _mode_row, _mode_hint, start_button]:
		if node != null:
			node.visible = false
	if _duel_tiles != null and is_instance_valid(_duel_tiles):
		_duel_tiles.queue_free()
	_duel_tiles = VBoxContainer.new()
	_duel_tiles.add_theme_constant_override("separation", 14)
	_scroll_content.add_child(_duel_tiles)
	_scroll_content.move_child(_duel_tiles, 0)

	_duel_tiles.add_child(_rank_strip())
	_duel_tiles.add_child(_pass_strip())
	_duel_tiles.add_child(_section_title(tr("UI_DUEL_TILES_TITLE")))
	_duel_tiles.add_child(_mode_tile(GameManager.Mode.CLASSIC, 250.0, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_duel_tiles.add_child(row)
	row.add_child(_mode_tile(GameManager.Mode.SURVIVAL, 250.0, false))
	row.add_child(_mode_tile(GameManager.Mode.TIME_ATTACK, 250.0, false))
	_duel_tiles.add_child(_section_title(tr("UI_DAILY_CHALLENGE_TITLE")))

	if _daily_card != null:
		## The daily card becomes the last tile, under the modes.
		_scroll_content.move_child(_daily_card, _scroll_content.get_child_count() - 1)
		_daily_card.custom_minimum_size.y = 104
		_daily_card.add_theme_stylebox_override("panel", _aurore_chrome_style(UiTokens.PODIUM_GOLD))
		_wire_aurore_fill(_daily_card, UiTokens.PODIUM_GOLD)
	ScrollTouch.let_drags_through(_duel_tiles)


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", UiScale.font(16))
	## Quiz page canvas is brand navy — keep section labels light.
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	return label


## Dark ink for labels sitting on light pastel tile fills.
func _pastel_ink() -> Color:
	return Color(0.10, 0.12, 0.15, 1)


func _pastel_ink_muted() -> Color:
	return Color(0.28, 0.30, 0.34, 1)


## Accent-tinted ink deep enough to read on a soft wash of the same hue.
func _pastel_accent_ink(accent: Color) -> Color:
	return accent.darkened(0.45).lerp(Color(0.08, 0.09, 0.12, 1), 0.40)


func _wire_aurore_fill(host: Control, accent: Color, theme_override: String = "") -> AuroreTile:
	## Aurora wash behind tile content — closest palette to `accent` (or forced theme).
	var bg := host.get_node_or_null("AuroreFill") as AuroreTile
	if bg == null:
		bg = AuroreTile.new()
		bg.name = "AuroreFill"
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.add_child(bg)
		host.move_child(bg, 0)
	if theme_override.is_empty():
		bg.aurore_theme = AuroreTile.theme_closest_to(accent)
	else:
		bg.aurore_theme = theme_override
	return bg


func _aurore_chrome_style(accent: Color, selected: bool = false) -> StyleBoxFlat:
	## Transparent fill so AuroreTile shows through; white ring when selected.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(22)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	if selected:
		style.set_border_width_all(3)
		style.border_color = Color(1, 1, 1, 0.92)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.28)
		style.shadow_size = 10
		style.shadow_offset = Vector2(0, 2)
	else:
		style.set_border_width_all(0)
		style.shadow_size = 0
	return style


## League badge, trophies and the way to the next league.
func _rank_strip() -> Control:
	var trophies := SaveManager.trophies
	var league := TrophyLeagues.for_trophies(trophies)
	var next_min := -1
	var next_key := ""
	for tier in TrophyLeagues.TIERS:
		if int(tier.get("min_trophies", 0)) > trophies:
			next_min = int(tier["min_trophies"])
			next_key = str(tier.get("title_key", ""))
			break

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _aurore_chrome_style(UiTokens.ACCENT_QUIZ))
	_wire_aurore_fill(panel, UiTokens.ACCENT_QUIZ)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 14)
	pad.add_theme_constant_override("margin_top", 14)
	pad.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pad.add_child(row)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(76, 76)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = GameAssets.load_texture("res://assets/leagues/%s.png" % str(league.get("id", "bronze")))
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)
	var title := Label.new()
	title.text = "%s  ·  🏆 %d" % [tr(str(league.get("title_key", ""))), trophies]
	title.add_theme_font_size_override("font_size", UiScale.font(22))
	title.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(title)
	if next_min > 0:
		var floor_min := int(league.get("min_trophies", 0))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.max_value = float(next_min - floor_min)
		bar.value = float(trophies - floor_min)
		bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
		bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(UiTokens.PODIUM_GOLD))
		info.add_child(bar)
		var hint := Label.new()
		hint.text = tr("UI_DUEL_NEXT_LEAGUE").format({"league": tr(next_key), "trophies": next_min - trophies})
		hint.add_theme_font_size_override("font_size", UiScale.font(14))
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
		info.add_child(hint)
	return panel


## Battle pass progress; a tap opens the Pass tab of the shop.
func _pass_strip() -> Control:
	var state: Dictionary = NetworkManager.pass_state
	if state.is_empty():
		NetworkManager.fetch_pass()
		if not NetworkManager.pass_received.is_connected(_on_pass_state):
			NetworkManager.pass_received.connect(_on_pass_state)
	var button := Button.new()
	button.custom_minimum_size.y = 84
	button.focus_mode = Control.FOCUS_NONE
	var gold := Color(1.0, 0.78, 0.2, 1)
	var style := _aurore_chrome_style(gold)
	for button_state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(button_state, style)
	_wire_aurore_fill(button, gold)
	button.pressed.connect(func() -> void:
		var shell := get_tree().current_scene
		if shell != null and shell.has_method("open_shop_tab"):
			shell.call("open_shop_tab", "pass")
	)
	PressScaleUtil.wire(button, self)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 14)
	button.add_child(pad)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)
	var title := Label.new()
	var active := bool(state.get("active", false))
	title.text = (tr("UI_PASS_STRIP").format({"tier": int(state.get("tier", 0))}) if active else tr("UI_PASS_TAB")) + "  ›"
	title.add_theme_font_size_override("font_size", UiScale.font(18))
	title.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(title)
	if active:
		var tier_xp := int(state.get("tier_xp", 800))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.max_value = float(tier_xp)
		bar.value = float(int(state.get("xp", 0)) % tier_xp)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
		bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(gold))
		column.add_child(bar)
	return button


func _on_pass_state(_state: Dictionary) -> void:
	if _duel_only and is_inside_tree():
		_build_duel_tiles()


## Big tile for one duel mode; a tap goes straight to matchmaking.
func _mode_tile(mode: int, height: float, wide: bool) -> Button:
	var entry: Array = MODES[mode]
	var accent: Color = UiTokens.MODE_ACCENTS[mode]
	var tile := Button.new()
	tile.custom_minimum_size.y = height
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.focus_mode = Control.FOCUS_NONE
	var style := _aurore_chrome_style(accent)
	for state in ["normal", "hover", "pressed", "focus"]:
		tile.add_theme_stylebox_override(state, style)
	## Survival keeps the red fruits aurora regardless of closest-match.
	var theme_override := "fruits" if mode == GameManager.Mode.SURVIVAL else ""
	_wire_aurore_fill(tile, accent, theme_override)
	tile.pressed.connect(_on_mode_tile_pressed.bind(mode))
	PressScaleUtil.wire(tile, self)

	var emoji_font := UiFonts.emoji_font()
	var big_icon := Label.new()
	big_icon.text = str(entry[3])
	big_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_icon.modulate.a = 0.85
	big_icon.add_theme_font_size_override("font_size", UiScale.font(76 if wide else 58))
	if emoji_font != null:
		big_icon.add_theme_font_override("font", emoji_font)
	big_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	big_icon.offset_left = -(150.0 if wide else 110.0)
	big_icon.offset_top = 18.0
	tile.add_child(big_icon)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 20)
	tile.add_child(pad)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)
	var chip := Label.new()
	chip.text = tr("UI_DUEL_RANKED_CHIP").to_upper()
	chip.add_theme_font_size_override("font_size", UiScale.font(13))
	chip.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	column.add_child(chip)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var name_label := Label.new()
	name_label.text = tr(str(entry[1])).to_upper()
	name_label.add_theme_font_size_override("font_size", UiScale.font(34 if wide else 26))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(name_label)
	var hint := Label.new()
	hint.text = tr(str(entry[2]).replace("UI_MODE_", "UI_DUEL_TILE_"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", UiScale.font(15))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	column.add_child(hint)
	var play := Label.new()
	play.text = tr("UI_DUEL_TILE_PLAY") + "  ›"
	play.add_theme_font_size_override("font_size", UiScale.font(17))
	play.add_theme_color_override("font_color", Color(1, 1, 1, 0.92))
	column.add_child(play)
	return tile


func _on_mode_tile_pressed(mode: int) -> void:
	GameManager.selected_mode = mode
	AudioManager.play("click")
	GameManager.shell_tab_index = ScenePaths.Tab.QUIZ
	get_tree().change_scene_to_file(ScenePaths.LIVE_MATCH)


func _load_categories() -> void:
	categories = QuestionLoaderScript.get_categories(LocaleManager.get_content_locale())
	_pin_primary_category()
	for child in category_list.get_children():
		child.queue_free()
	_tile_buttons.clear()

	if categories.is_empty():
		description_label.text = tr("UI_NO_CATEGORIES")
		start_button.disabled = true
		return

	category_list.visible = not _duel_only
	if _duel_only:
		start_button.disabled = false
		_refresh_mode_picker()
		return
	for index in range(categories.size()):
		var category: Dictionary = categories[index]
		var tile := _make_category_tile(index, category)
		category_list.add_child(tile)
		_tile_buttons.append(tile)

	_selected_index = _primary_category_index()
	_on_category_selected(_selected_index)


func _pin_primary_category() -> void:
	for i in range(categories.size()):
		if str(categories[i].get("id", "")) == PRIMARY_CATEGORY_ID:
			var primary: Dictionary = categories[i]
			categories.remove_at(i)
			categories.insert(0, primary)
			return


func _primary_category_index() -> int:
	for i in range(categories.size()):
		if str(categories[i].get("id", "")) == PRIMARY_CATEGORY_ID:
			return i
	return 0


## Shared daily challenge card, pinned above the category list.
func _setup_daily_card() -> void:
	_daily_card = PanelContainer.new()
	_daily_card.add_theme_stylebox_override("panel", _aurore_chrome_style(UiTokens.PODIUM_GOLD))
	_wire_aurore_fill(_daily_card, UiTokens.PODIUM_GOLD)
	_scroll_content.add_child(_daily_card)
	_scroll_content.move_child(_daily_card, 0)
	NetworkManager.daily_challenge_received.connect(_on_daily_received)
	NetworkManager.daily_challenge_failed.connect(_on_daily_failed)
	NetworkManager.daily_leaderboard_received.connect(_on_daily_board_received)
	NetworkManager.daily_leaderboard_failed.connect(_on_daily_board_failed)
	NetworkManager.daily_result_submitted.connect(func(_data: Dictionary) -> void: NetworkManager.fetch_daily_leaderboard())
	_render_daily()
	_daily_fetching = true
	NetworkManager.fetch_daily_challenge()


func _on_daily_received(data: Dictionary) -> void:
	_daily_fetching = false
	_daily = data
	_render_daily()
	## Only players who already played see their rank and the ranking.
	if not DailyChallenge.result_for(str(data.get("date", ""))).is_empty():
		NetworkManager.fetch_daily_leaderboard()


func _on_daily_board_received(data: Dictionary) -> void:
	_daily_board = data
	_daily_board_failed = false
	## Played offline earlier? The server keeps the first result, so resending is safe.
	var stored := DailyChallenge.result_for(str(data.get("date", "")))
	if data.get("player_rank") == null and not stored.is_empty() and not _daily_resubmitted:
		_daily_resubmitted = true
		NetworkManager.submit_daily_result(
			int(stored.get("score", 0)), int(stored.get("correct_count", 0)),
			int(stored.get("total_count", 0)), int(stored.get("max_combo", 0))
		)
	_render_daily()
	if _board_overlay != null:
		_open_daily_board()


func _on_daily_board_failed() -> void:
	_daily_board_failed = true
	if _board_overlay != null:
		_open_daily_board()


## Offline: mirror the server rotation so the mode still works.
func _on_daily_failed() -> void:
	_daily_fetching = false
	_daily = DailyChallenge.offline_today()
	_render_daily()


func _render_daily() -> void:
	for child in _daily_card.get_children():
		if child.name == "AuroreFill":
			continue
		child.queue_free()

	var accent := UiTokens.PODIUM_GOLD
	var category_id_preview := str(_daily.get("category_id", ""))
	if not category_id_preview.is_empty():
		accent = UiTokens.accent_for_category(category_id_preview)
	_daily_card.add_theme_stylebox_override("panel", _aurore_chrome_style(accent))
	_wire_aurore_fill(_daily_card, accent)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	_daily_card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)

	var category_id := str(_daily.get("category_id", ""))
	var date := str(_daily.get("date", ""))
	var result := DailyChallenge.result_for(date) if not date.is_empty() else {}
	var known := false
	var category_name := ""
	for category in categories:
		if str(category.get("id", "")) == category_id:
			known = true
			category_name = str(category.get("name", category_id))

	row.add_child(GameAssets.make_circular_icon_display(
		GameAssets.category_texture(category_id) if known else null, "🌍", 64.0
	))

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(labels)

	var tag := Label.new()
	tag.text = "%s · +%d XP" % [tr("UI_DAILY_CHALLENGE_TITLE").to_upper(), DailyChallenge.BONUS_XP]
	if not result.is_empty() and _daily_board.get("player_rank") != null:
		tag.text = "%s · %s" % [
			tr("UI_DAILY_CHALLENGE_TITLE").to_upper(),
			tr("UI_DAILY_RANK_TOTAL").format({
				"rank": int(_daily_board["player_rank"]),
				"total": int(_daily_board.get("total_players", 0)),
			}),
		]
	tag.add_theme_font_size_override("font_size", UiScale.font(14))
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	labels.add_child(tag)

	var name_label := Label.new()
	name_label.text = category_name if known else tr("UI_DAILY_CHALLENGE_LOADING")
	name_label.add_theme_font_size_override("font_size", UiScale.font(24))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	labels.add_child(name_label)

	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", UiScale.font(14))
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	if not result.is_empty():
		var seconds := DailyChallenge.seconds_until_reset()
		sub.text = "%s\n%s" % [
			tr("UI_DAILY_CHALLENGE_DONE").format({
				"score": int(result.get("score", 0)),
				"correct": int(result.get("correct_count", 0)),
				"total": int(result.get("total_count", 0)),
			}),
			tr("UI_DAILY_CHALLENGE_NEXT").format({
				"time": "%dh%02d" % [int(seconds / 3600.0), int((seconds % 3600) / 60.0)],
			}),
		]
	else:
		sub.text = tr("UI_DAILY_CHALLENGE_SUB")
	labels.add_child(sub)

	if not result.is_empty():
		var board := Button.new()
		board.text = "🏆 " + tr("UI_DAILY_BOARD_BUTTON")
		board.custom_minimum_size = Vector2(150, 48)
		board.add_theme_font_size_override("font_size", UiScale.font(18))
		for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
			board.add_theme_color_override(slot, UiTokens.INK)
		var outline := UiStyle.filled(Color(1, 1, 1, 1), 24)
		outline.set_border_width_all(3)
		outline.border_color = UiTokens.PODIUM_GOLD
		for state in ["normal", "hover", "pressed", "focus"]:
			board.add_theme_stylebox_override(state, outline)
		PressScaleUtil.wire(board, self)
		board.pressed.connect(_open_daily_board)
		row.add_child(board)
		return

	var play := Button.new()
	play.text = tr("UI_PLAY").to_upper()
	play.custom_minimum_size = Vector2(110, 48)
	play.add_theme_font_size_override("font_size", UiScale.font(20))
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		play.add_theme_color_override(slot, UiTokens.INK)
	var style := UiStyle.filled(UiTokens.PODIUM_GOLD, 24)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		play.add_theme_stylebox_override(state, style)
	play.disabled = not known or _daily_fetching
	PressScaleUtil.wire(play, self)
	play.pressed.connect(_on_daily_play_pressed)
	row.add_child(play)


## Modal list of today's top players; the player's own row is highlighted.
func _open_daily_board() -> void:
	if _board_overlay != null:
		_board_overlay.queue_free()

	_board_overlay = ColorRect.new()
	(_board_overlay as ColorRect).color = Color(0.04, 0.05, 0.1, 0.78)
	_board_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_board_overlay)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.PODIUM_GOLD))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "🏆 " + tr("UI_DAILY_BOARD_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", UiScale.font(28))
	title.add_theme_color_override("font_color", UiTokens.INK)
	column.add_child(title)

	var scroll := ScrollContainer.new()
	## Height follows the number of rows (capped) so a short list has no empty space.
	scroll.custom_minimum_size = Vector2(0, clampf(float(_daily_board.get("entries", []).size()) * 64.0, 90.0, 640.0))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)

	var entries: Array = _daily_board.get("entries", [])
	if _daily_board.is_empty() or entries.is_empty():
		var note := Label.new()
		note.text = tr("UI_DAILY_BOARD_ERROR") if _daily_board_failed else (
			tr("UI_DAILY_BOARD_EMPTY") if not _daily_board.is_empty() else tr("UI_DAILY_CHALLENGE_LOADING")
		)
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", UiScale.font(20))
		note.add_theme_color_override("font_color", UiTokens.INK_MUTED)
		list.add_child(note)
	for entry in entries:
		list.add_child(_make_board_row(entry))

	var close := Button.new()
	close.text = tr("UI_BACK")
	close.custom_minimum_size = Vector2(0, 52)
	close.add_theme_font_size_override("font_size", UiScale.font(20))
	PressScaleUtil.wire(close, self)
	close.pressed.connect(func() -> void:
		_board_overlay.queue_free()
		_board_overlay = null
	)
	column.add_child(close)


func _make_board_row(entry: Dictionary) -> Control:
	var mine := str(entry.get("player_id", "")) == NetworkManager.player_id
	var row := PanelContainer.new()
	var box := UiStyle.filled(Color(UiTokens.PODIUM_GOLD, 0.22) if mine else Color(0.95, 0.96, 0.98, 1), 16)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	if mine:
		box.set_border_width_all(2)
		box.border_color = UiTokens.PODIUM_GOLD
	row.add_theme_stylebox_override("panel", box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	row.add_child(line)

	var rank := int(entry.get("rank", 0))
	var rank_label := Label.new()
	rank_label.text = ["🥇", "🥈", "🥉"][rank - 1] if rank >= 1 and rank <= 3 else "#%d" % rank
	rank_label.custom_minimum_size = Vector2(56, 0)
	rank_label.add_theme_font_size_override("font_size", UiScale.font(22))
	rank_label.add_theme_color_override("font_color", UiTokens.INK)
	line.add_child(rank_label)

	var name_label := Label.new()
	name_label.text = str(entry.get("display_name", ""))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(name_label.text))
	)
	name_label.add_theme_color_override("font_color", UiTokens.INK)
	line.add_child(name_label)

	var score := Label.new()
	score.text = "%d" % int(entry.get("score", 0))
	score.add_theme_font_size_override("font_size", UiScale.font(22))
	score.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	line.add_child(score)
	return row


func _on_daily_play_pressed() -> void:
	var date := str(_daily.get("date", ""))
	if date.is_empty() or not DailyChallenge.result_for(date).is_empty():
		return
	## The date doubles as the ordering seed (the server's seed is that same date).
	GameManager.start_round(str(_daily.get("category_id", "")), "", date)
	if GameManager.has_questions():
		get_tree().change_scene_to_file(ScenePaths.QUIZ_GAME)


func _make_category_tile(index: int, category: Dictionary) -> Button:
	var category_id := str(category.get("id", ""))
	var accent := UiTokens.accent_for_category(category_id)
	var featured := category_id == PRIMARY_CATEGORY_ID
	var button := Button.new()
	button.custom_minimum_size.y = 96 if featured else 78
	button.text = ""
	button.pressed.connect(_on_category_selected.bind(index))
	PressScaleUtil.wire(button, self)

	var chrome := _aurore_chrome_style(accent, false)
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, chrome)
	_wire_aurore_fill(button, accent)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var icon_size := 64.0 if featured else 56.0
	row.add_child(GameAssets.make_circular_icon_display(GameAssets.category_texture(category_id), "🧠", icon_size))

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)

	var name_label := Label.new()
	name_label.text = str(category.get("name", category_id))
	name_label.add_theme_font_size_override("font_size", UiScale.font(26 if featured else 22))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)

	var desc := Label.new()
	desc.text = str(category.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", UiScale.font(14 if featured else 13))
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(desc)

	button.set_meta("accent", accent)
	button.set_meta("featured", featured)
	button.set_meta("name_label", name_label)
	button.set_meta("desc_label", desc)
	return button


func _on_category_selected(index: int) -> void:
	if index < 0 or index >= categories.size():
		return
	_selected_index = index
	description_label.text = categories[index].get("description", "")
	start_button.disabled = false
	_refresh_mode_picker()
	for tile_index in range(_tile_buttons.size()):
		var tile := _tile_buttons[tile_index]
		var accent: Color = tile.get_meta("accent")
		var selected := tile_index == index
		var style := _aurore_chrome_style(accent, selected)
		tile.add_theme_stylebox_override("normal", style)
		tile.add_theme_stylebox_override("hover", style)
		tile.add_theme_stylebox_override("pressed", style)
		tile.add_theme_stylebox_override("focus", style)
		var name_label: Label = tile.get_meta("name_label")
		var desc_label: Label = tile.get_meta("desc_label")
		if selected:
			name_label.add_theme_color_override("font_color", Color.WHITE)
			desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.90))
		else:
			name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
			desc_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))


func _on_start_pressed() -> void:
	if _duel_only:
		GameManager.shell_tab_index = ScenePaths.Tab.QUIZ
		get_tree().change_scene_to_file(ScenePaths.LIVE_MATCH)
		return
	if _selected_index < 0 or _selected_index >= categories.size():
		return
	var category_id: String = str(categories[_selected_index].get("id", ""))
	GameManager.start_round(category_id, "", "", GameManager.selected_mode)
	if not GameManager.has_questions():
		description_label.text = tr("UI_EMPTY_QUESTIONS")
		return
	get_tree().change_scene_to_file(ScenePaths.QUIZ_GAME)


func _on_back_pressed() -> void:
	if embedded_mode:
		back_requested.emit()
	else:
		ScenePaths.go_to_shell(get_tree(), ScenePaths.Tab.HOME)


func _on_locale_changed(_locale: String) -> void:
	refresh()
