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

## Rank strip, ranked-duels feature card, then daily challenge.
func _build_duel_tiles() -> void:
	for node in [_mode_section_label, _mode_row, _mode_hint, start_button]:
		if node != null:
			node.visible = false
	if _duel_tiles != null and is_instance_valid(_duel_tiles):
		_duel_tiles.queue_free()
	_duel_tiles = VBoxContainer.new()
	_duel_tiles.add_theme_constant_override("separation", 12)
	_scroll_content.add_child(_duel_tiles)
	_scroll_content.move_child(_duel_tiles, 0)

	## League + Pass inside the same blue shell as ranked / daily (no title).
	var progress := _quiz_feature_card("", "")
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 10)
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress["body"].add_child(top_row)
	var rank := _rank_strip()
	rank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rank.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rank.size_flags_stretch_ratio = 3.0
	top_row.add_child(rank)
	var pass_tile := _pass_strip()
	pass_tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pass_tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pass_tile.size_flags_stretch_ratio = 1.0
	top_row.add_child(pass_tile)
	_duel_tiles.add_child(progress["panel"])

	## Ranked duel modes.
	var ranked := _quiz_feature_card(tr("UI_DUEL_TILES_TITLE"), "⚔️")
	ranked["body"].add_child(_mode_tile(GameManager.Mode.CLASSIC))
	ranked["body"].add_child(_mode_tile(GameManager.Mode.SURVIVAL))
	ranked["body"].add_child(_mode_tile(GameManager.Mode.TIME_ATTACK))
	_duel_tiles.add_child(ranked["panel"])

	if _daily_card != null:
		_scroll_content.move_child(_daily_card, _scroll_content.get_child_count() - 1)
		_daily_card.custom_minimum_size.y = 0
	ScrollTouch.let_drags_through(_duel_tiles)


## Dark blue feature card — returns {panel, body}.
func _quiz_feature_card(title_text: String, emoji: String, show_reset: bool = false) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var shell := UiStyle.home_surface(true, 0)
	shell.bg_color = Color(0.07, 0.16, 0.32, 1)
	shell.set_border_width_all(2)
	shell.border_color = Color(UiTokens.ACCENT_QUIZ.r, UiTokens.ACCENT_QUIZ.g, UiTokens.ACCENT_QUIZ.b, 0.55)
	panel.add_theme_stylebox_override("panel", shell)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	if not title_text.is_empty() or not emoji.is_empty() or show_reset:
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 10)
		header.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(header)

		if not emoji.is_empty():
			var icon := Label.new()
			icon.text = emoji
			icon.add_theme_font_size_override("font_size", UiScale.font(26))
			var emoji_font := UiFonts.emoji_font()
			if emoji_font != null:
				icon.add_theme_font_override("font", emoji_font)
			header.add_child(icon)

		if not title_text.is_empty():
			var title := Label.new()
			title.text = title_text.to_upper()
			title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title.add_theme_font_size_override("font_size", UiScale.font(20))
			title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
			header.add_child(title)

		if show_reset:
			var seconds := DailyChallenge.seconds_until_reset()
			var reset := Label.new()
			reset.text = tr("UI_DAILY_RESET_IN").format({
				"time": "%dh%02d" % [int(seconds / 3600.0), int((seconds % 3600) / 60.0)],
			})
			reset.add_theme_font_size_override("font_size", UiScale.font(15))
			reset.add_theme_color_override("font_color", UiTokens.ACCENT_QUIZ)
			header.add_child(reset)

	return {"panel": panel, "body": vbox}


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", UiScale.font(18))
	## Match home / profile section caps on the dark quiz sheet.
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
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


## League badge + trophies — half-width compact tile.
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
	panel.custom_minimum_size.y = 132
	var league_theme := AuroreTile.theme_for_league(str(league.get("id", "bronze")))
	var league_accent := AuroreTile.primary_color(league_theme)
	panel.add_theme_stylebox_override("panel", _aurore_chrome_style(league_accent))
	_wire_aurore_fill(panel, league_accent, league_theme)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(column)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(head)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = GameAssets.load_texture("res://assets/leagues/%s.png" % str(league.get("id", "bronze")))
	head.add_child(icon)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.add_theme_constant_override("separation", 2)
	head.add_child(name_col)
	var title := Label.new()
	title.text = tr(str(league.get("title_key", "")))
	title.clip_text = true
	title.add_theme_font_size_override("font_size", UiScale.font(18))
	title.add_theme_color_override("font_color", Color.WHITE)
	name_col.add_child(title)
	var cups := Label.new()
	cups.text = "🏆 %d" % trophies
	cups.add_theme_font_size_override("font_size", UiScale.font(16))
	cups.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	name_col.add_child(cups)

	if next_min > 0:
		var floor_min := int(league.get("min_trophies", 0))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.max_value = float(next_min - floor_min)
		bar.value = float(trophies - floor_min)
		bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
		bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(UiTokens.PODIUM_GOLD))
		column.add_child(bar)
		var hint := Label.new()
		hint.text = tr("UI_DUEL_NEXT_LEAGUE").format({"league": tr(next_key), "trophies": next_min - trophies})
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = 2
		hint.add_theme_font_size_override("font_size", UiScale.font(12))
		hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		column.add_child(hint)
	return panel


## Battle pass progress — narrow companion (~1/4) next to the league tile.
func _pass_strip() -> Control:
	var state: Dictionary = NetworkManager.pass_state
	if state.is_empty():
		NetworkManager.fetch_pass()
		if not NetworkManager.pass_received.is_connected(_on_pass_state):
			NetworkManager.pass_received.connect(_on_pass_state)
	var button := Button.new()
	button.custom_minimum_size.y = 132
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
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	button.add_child(pad)
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(column)

	var ticket := Label.new()
	ticket.text = "🎫"
	ticket.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ticket.add_theme_font_size_override("font_size", UiScale.font(32))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		ticket.add_theme_font_override("font", emoji_font)
	column.add_child(ticket)

	var title := Label.new()
	var active := bool(state.get("active", false))
	title.text = ("T%d" % int(state.get("tier", 0))) if active else tr("UI_PASS_TAB")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.add_theme_font_size_override("font_size", UiScale.font(14))
	title.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(title)

	if active:
		var tier_xp := int(state.get("tier_xp", 800))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 6
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


## Compact aurore row for one duel mode — same rhythm as home content tiles.
func _mode_tile(mode: int, _height: float = 0.0, _wide: bool = false) -> Button:
	var entry: Array = MODES[mode]
	var accent: Color = UiTokens.MODE_ACCENTS[mode]
	var tile := Button.new()
	tile.custom_minimum_size.y = 156
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

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	tile.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	## Mode emoji in a soft circle — mirrors category / home icon chips.
	const ICON := 88.0
	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(ICON, ICON)
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_slot)
	var icon_bg := Panel.new()
	icon_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(1, 1, 1, 0.18)
	icon_style.set_corner_radius_all(int(ICON * 0.5))
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	icon_slot.add_child(icon_bg)
	var emoji := Label.new()
	emoji.text = str(entry[3])
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emoji.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emoji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emoji.add_theme_font_size_override("font_size", UiScale.font(38))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		emoji.add_theme_font_override("font", emoji_font)
	icon_slot.add_child(emoji)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 6)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)

	var name_label := Label.new()
	name_label.text = tr(str(entry[1])).to_upper()
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", UiScale.font(28))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	texts.add_child(name_label)

	var hint := Label.new()
	hint.text = tr(str(entry[2]).replace("UI_MODE_", "UI_DUEL_TILE_"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 2
	hint.add_theme_font_size_override("font_size", UiScale.font(17))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	texts.add_child(hint)
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


## Shared daily challenge card — same shell as Accueil “défis du jour”.
func _setup_daily_card() -> void:
	_daily_card = PanelContainer.new()
	_daily_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	## Rebuild into the shared Accueil-style feature shell.
	while _daily_card.get_child_count() > 0:
		var child := _daily_card.get_child(0)
		_daily_card.remove_child(child)
		child.queue_free()

	var featured := _quiz_feature_card(tr("UI_DAILY_CHALLENGE_TITLE"), "🔥", true)
	var shell_panel: PanelContainer = featured["panel"]
	var body: VBoxContainer = featured["body"]
	## Steal the feature card chrome onto the persistent daily node.
	_daily_card.add_theme_stylebox_override(
		"panel",
		shell_panel.get_theme_stylebox("panel").duplicate()
	)
	while shell_panel.get_child_count() > 0:
		var piece := shell_panel.get_child(0)
		shell_panel.remove_child(piece)
		_daily_card.add_child(piece)
	shell_panel.queue_free()

	var category_id := str(_daily.get("category_id", ""))
	var date := str(_daily.get("date", ""))
	var result := DailyChallenge.result_for(date) if not date.is_empty() else {}
	var known := false
	var category_name := ""
	for category in categories:
		if str(category.get("id", "")) == category_id:
			known = true
			category_name = str(category.get("name", category_id))

	var accent := UiTokens.PODIUM_GOLD
	if known:
		accent = UiTokens.accent_for_category(category_id)

	var inner := PanelContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.custom_minimum_size.y = 128
	inner.add_theme_stylebox_override("panel", _aurore_chrome_style(accent))
	_wire_aurore_fill(inner, accent)
	body.add_child(inner)

	var inner_pad := MarginContainer.new()
	inner_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_pad.add_theme_constant_override("margin_left", 12)
	inner_pad.add_theme_constant_override("margin_right", 12)
	inner_pad.add_theme_constant_override("margin_top", 10)
	inner_pad.add_theme_constant_override("margin_bottom", 10)
	inner.add_child(inner_pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner_pad.add_child(row)

	row.add_child(GameAssets.make_circular_icon_display(
		GameAssets.category_texture(category_id) if known else null, "🌍", 72.0
	))

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 2)
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)

	var tag := Label.new()
	tag.text = "+%d XP" % DailyChallenge.BONUS_XP
	if not result.is_empty() and _daily_board.get("player_rank") != null:
		tag.text = tr("UI_DAILY_RANK_TOTAL").format({
			"rank": int(_daily_board["player_rank"]),
			"total": int(_daily_board.get("total_players", 0)),
		})
	tag.add_theme_font_size_override("font_size", UiScale.font(14))
	tag.add_theme_color_override("font_color", Color(1, 1, 1, 0.88))
	labels.add_child(tag)

	var name_label := Label.new()
	name_label.text = category_name if known else tr("UI_DAILY_CHALLENGE_LOADING")
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", UiScale.font(22))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	labels.add_child(name_label)

	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", UiScale.font(14))
	sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	if not result.is_empty():
		sub.text = tr("UI_DAILY_CHALLENGE_DONE").format({
			"score": int(result.get("score", 0)),
			"correct": int(result.get("correct_count", 0)),
			"total": int(result.get("total_count", 0)),
		})
	else:
		sub.text = tr("UI_DAILY_CHALLENGE_SUB")
	labels.add_child(sub)

	if not result.is_empty():
		var board := Button.new()
		board.text = "🏆"
		board.custom_minimum_size = Vector2(56, 48)
		board.focus_mode = Control.FOCUS_NONE
		board.add_theme_font_size_override("font_size", UiScale.font(22))
		for slot in ["font_color", "font_hover_color", "font_pressed_color"]:
			board.add_theme_color_override(slot, UiTokens.INK)
		var outline := UiStyle.filled(Color(1, 1, 1, 1), 14)
		outline.set_border_width_all(2)
		outline.border_color = UiTokens.PODIUM_GOLD
		for state in ["normal", "hover", "pressed", "focus"]:
			board.add_theme_stylebox_override(state, outline)
		PressScaleUtil.wire(board, self)
		board.pressed.connect(_open_daily_board)
		row.add_child(board)
		return

	var play := Button.new()
	play.text = tr("UI_PLAY").to_upper()
	play.custom_minimum_size = Vector2(112, 48)
	play.focus_mode = Control.FOCUS_NONE
	play.add_theme_font_size_override("font_size", UiScale.font(18))
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		play.add_theme_color_override(slot, UiTokens.INK)
	var play_style := UiStyle.filled(UiTokens.PODIUM_GOLD, 14)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		play.add_theme_stylebox_override(state, play_style)
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
