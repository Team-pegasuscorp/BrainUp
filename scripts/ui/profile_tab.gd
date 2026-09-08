## BrainUp profile — layout and tiles matching the competitive mock.
extends Control

const ProfileSnapshot = preload("res://scripts/profile/profile_snapshot.gd")
const ProfileDonutScript = preload("res://scripts/ui/profile_donut.gd")
const CircularAvatarScript = preload("res://scripts/ui/circular_avatar.gd")
const CountryFlags = preload("res://scripts/profile/country_flags.gd")
const UiFonts = preload("res://scripts/config/ui_fonts.gd")
const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")

@onready var sections: VBoxContainer = %Sections
@onready var scroll: ScrollContainer = %ScrollContainer
@onready var outer_margin: MarginContainer = %OuterMargin
@onready var photo_dialog: FileDialog = %PhotoDialog
@onready var badge_backdrop: ColorRect = %BadgeBackdrop
@onready var badge_detail_panel: PanelContainer = %BadgeDetailPanel
@onready var badge_detail_icon: Label = %BadgeDetailIcon
@onready var badge_detail_title: Label = %BadgeDetailTitle
@onready var badge_detail_desc: Label = %BadgeDetailDesc
@onready var badge_detail_close: Button = %BadgeDetailClose
@onready var edit_backdrop: ColorRect = %EditBackdrop
@onready var edit_panel: PanelContainer = %EditPanel
@onready var edit_title: Label = %EditTitle
@onready var pseudo_input: LineEdit = %PseudoInput
@onready var change_photo_button: Button = %ChangePhotoButton
@onready var remove_photo_button: Button = %RemovePhotoButton
@onready var edit_save_button: Button = %EditSaveButton
@onready var edit_close_button: Button = %EditCloseButton

var _profile_data: Dictionary = {}
var _animated_nodes: Array[Control] = []
var _xp_bar: ProgressBar
var _active_tweens: Array[Tween] = []
## Base page gutter; left/right stay equal visually without changing tile width.
const _PAGE_GUTTER: int = 18


func _ready() -> void:
	pseudo_input.max_length = UiTokens.MAX_PLAYER_NAME_LENGTH
	badge_detail_panel.add_theme_stylebox_override("panel", UiStyle.profile_card(UiTokens.ACCENT_PROFILE, true))
	edit_panel.add_theme_stylebox_override("panel", UiStyle.profile_card(UiTokens.ACCENT_PROFILE, true))
	_style_dark_controls()
	_wire_events()
	_apply_translations()
	if not scroll.resized.is_connected(_balance_page_gutters):
		scroll.resized.connect(_balance_page_gutters)
	call_deferred("_balance_page_gutters")
	refresh()


func _balance_page_gutters() -> void:
	## Scrollbar eats the right side of the viewport. Shift margins so
	## visual left == visual right, while left+right stays 2*_PAGE_GUTTER (tile width unchanged).
	if outer_margin == null or scroll == null:
		return
	var sb := scroll.get_v_scroll_bar()
	var sb_w := 0.0
	if sb != null and sb.visible and sb.get_max() > sb.get_page():
		sb_w = sb.size.x
	var half := sb_w * 0.5
	outer_margin.add_theme_constant_override("margin_left", int(round(float(_PAGE_GUTTER) + half)))
	outer_margin.add_theme_constant_override("margin_right", int(round(maxf(float(_PAGE_GUTTER) - half, 0.0))))


func _style_dark_controls() -> void:
	for label in [edit_title, badge_detail_title, badge_detail_icon]:
		if label:
			label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	badge_detail_desc.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	pseudo_input.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	pseudo_input.add_theme_color_override("font_placeholder_color", UiTokens.PROFILE_TEXT_MUTED)
	for button in [
		change_photo_button, remove_photo_button, edit_save_button,
		edit_close_button, badge_detail_close,
	]:
		_style_profile_button(button, UiTokens.ACCENT_PROFILE)


func refresh() -> void:
	_profile_data = ProfileSnapshot.build_full(LocaleManager.get_content_locale())
	_rebuild_sections()
	call_deferred("_balance_page_gutters")
	_play_entrance_animation()


func on_tab_shown() -> void:
	refresh()


func _wire_events() -> void:
	change_photo_button.pressed.connect(_on_change_photo_pressed)
	remove_photo_button.pressed.connect(_on_remove_photo_pressed)
	photo_dialog.files_selected.connect(_on_photo_selected)
	edit_save_button.pressed.connect(_on_edit_save_pressed)
	edit_close_button.pressed.connect(_close_edit_profile)
	edit_backdrop.gui_input.connect(_on_edit_backdrop_gui_input)
	pseudo_input.text_submitted.connect(func(_t: String) -> void: _on_edit_save_pressed())
	badge_backdrop.gui_input.connect(_on_badge_backdrop_gui_input)
	badge_detail_close.pressed.connect(_close_badge_detail)
	LocaleManager.locale_changed.connect(_on_locale_changed)
	for button in [
		change_photo_button, remove_photo_button, edit_save_button,
		edit_close_button, badge_detail_close,
	]:
		PressScaleUtil.wire(button, self)


func _apply_translations() -> void:
	edit_title.text = tr("UI_PROFILE_EDIT")
	pseudo_input.placeholder_text = tr("UI_PROFILE_PSEUDO_PLACEHOLDER")
	change_photo_button.text = tr("UI_PROFILE_CHANGE_PHOTO")
	remove_photo_button.text = tr("UI_PROFILE_REMOVE_PHOTO")
	edit_save_button.text = tr("UI_PROFILE_SAVE")
	edit_close_button.text = tr("UI_BACK")
	badge_detail_close.text = tr("UI_BACK")


func _rebuild_sections() -> void:
	_kill_profile_tweens()
	_animated_nodes.clear()
	while sections.get_child_count() > 0:
		var child := sections.get_child(0)
		sections.remove_child(child)
		child.free()

	sections.add_theme_constant_override("separation", 12)
	sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	## Mobile stack matching the competitive mock tiles.
	sections.add_child(_build_hero())
	sections.add_child(_build_stats_strip())
	sections.add_child(_build_mastery_mosaic())
	sections.add_child(_build_history_tile())
	sections.add_child(_build_badges_tile())
	sections.add_child(_build_season_tile())


func _kill_profile_tweens() -> void:
	for tween in _active_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_active_tweens.clear()


func _track_tween(tween: Tween) -> Tween:
	_active_tweens.append(tween)
	return tween


func _build_hero() -> PanelContainer:
	## Mock layout: avatar | identity+XP | divider | league column (~1/4 width).
	var panel := _tile(UiTokens.ACCENT_PROFILE, true)
	panel.custom_minimum_size.y = UiTokens.DASH_HERO_HEIGHT
	var margin := _pad(16, 16)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(row)

	## Avatar — nearly full hero height, circular.
	var avatar_wrap := Control.new()
	avatar_wrap.custom_minimum_size = Vector2(148, 148)
	avatar_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(avatar_wrap)

	var avatar := CircularAvatarScript.new()
	avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Mock gradient ring: violet → magenta → orange + glow.
	avatar.ring_color = UiTokens.ACCENT_PROFILE
	avatar.ring_color_mid = UiTokens.ACCENT_SOCIAL
	avatar.ring_color_secondary = UiTokens.PROFILE_AVATAR_RING
	avatar.ring_width = 3.5
	avatar.ring_gap = 2.5
	avatar.fill_color = UiTokens.PROFILE_CARD_BG_RAISED
	## Presence pill: green only when the user is connected (social-ready).
	if bool(_profile_data.get("is_online", false)):
		avatar.set_presence(CircularAvatarScript.Presence.ONLINE)
	else:
		avatar.set_presence(CircularAvatarScript.Presence.HIDDEN)
	avatar.set_avatar(_profile_data.get("avatar_texture") as Texture2D)
	avatar_wrap.add_child(avatar)

	var avatar_btn := Button.new()
	avatar_btn.flat = true
	avatar_btn.focus_mode = Control.FOCUS_NONE
	avatar_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	avatar_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		avatar_btn.add_theme_stylebox_override(state, empty)
	avatar_btn.pressed.connect(_open_edit_profile)
	avatar_btn.mouse_entered.connect(_on_avatar_hover.bind(avatar, true))
	avatar_btn.mouse_exited.connect(_on_avatar_hover.bind(avatar, false))
	avatar_btn.button_down.connect(_on_avatar_hover.bind(avatar, true))
	avatar_btn.button_up.connect(_on_avatar_hover.bind(avatar, false))
	avatar_wrap.add_child(avatar_btn)
	PressScaleUtil.wire(avatar_btn, self)

	## Identity + level / XP (center ~55%).
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 6)
	row.add_child(info)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	info.add_child(name_row)

	var name_label := Label.new()
	name_label.text = str(_profile_data.get("player_name", UiTokens.DEFAULT_PLAYER_NAME))
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	name_row.add_child(name_label)

	## Shown only when the account email has been verified.
	if bool(_profile_data.get("email_verified", false)):
		var verified := Label.new()
		verified.text = "☑"
		verified.tooltip_text = tr("UI_PROFILE_EMAIL_VERIFIED")
		verified.add_theme_font_size_override("font_size", 20)
		verified.add_theme_color_override("font_color", Color(0.36, 0.75, 1.0, 1))
		name_row.add_child(verified)

	var country_row := HBoxContainer.new()
	country_row.add_theme_constant_override("separation", 6)
	info.add_child(country_row)

	var country_name := str(_profile_data.get("country", "France"))
	var flag := str(_profile_data.get("country_flag", ""))
	if flag.is_empty():
		flag = CountryFlags.emoji_for(country_name)

	## Separate label so the flag uses a CBDT emoji font (Godot can't render Windows COLR emoji).
	var flag_label := Label.new()
	flag_label.text = flag
	flag_label.add_theme_font_size_override("font_size", 26)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		flag_label.add_theme_font_override("font", emoji_font)
	else:
		flag_label.add_theme_font_override("font", UiFonts.text_with_emoji())
	country_row.add_child(flag_label)

	var country := Label.new()
	country.text = country_name
	country.add_theme_font_size_override("font_size", 19)
	country.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	country_row.add_child(country)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.custom_minimum_size.y = 6
	info.add_child(spacer)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	bottom.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_child(bottom)

	## Level column: caption + number (number centered under "NIVEAU")
	var level_col := VBoxContainer.new()
	level_col.add_theme_constant_override("separation", 0)
	level_col.alignment = BoxContainer.ALIGNMENT_CENTER
	level_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var level_wrap := MarginContainer.new()
	level_wrap.add_theme_constant_override("margin_left", 5)
	level_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_wrap.add_child(level_col)
	bottom.add_child(level_wrap)

	var level_caption := Label.new()
	level_caption.text = tr("UI_PROFILE_LEVEL_CAPTION").to_upper()
	level_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_caption.add_theme_font_size_override("font_size", 14)
	level_caption.add_theme_color_override("font_color", UiTokens.PROFILE_TITLE_CAPS)
	level_col.add_child(level_caption)

	var level_num := Label.new()
	level_num.text = str(_profile_data.get("level", 1))
	level_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_num.add_theme_font_size_override("font_size", 34)
	level_num.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	## Keep a readable gap under the larger "NIVEAU" caption.
	var level_num_wrap := MarginContainer.new()
	level_num_wrap.add_theme_constant_override("margin_top", -2)
	level_num_wrap.add_child(level_num)
	level_col.add_child(level_num_wrap)

	## Keep XP block slightly nudged right of the level column.
	var xp_nudge := Control.new()
	xp_nudge.custom_minimum_size.x = 10
	xp_nudge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(xp_nudge)

	## XP column: label, bar, next level — centered with level block.
	var xp_col := VBoxContainer.new()
	xp_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xp_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_col.add_theme_constant_override("separation", 5)
	xp_col.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(xp_col)

	var xp_line := HBoxContainer.new()
	xp_line.add_theme_constant_override("separation", 6)
	var xp_line_wrap := MarginContainer.new()
	xp_line_wrap.add_theme_constant_override("margin_top", -5)
	xp_line_wrap.add_child(xp_line)
	xp_col.add_child(xp_line_wrap)

	var xp_tag := Label.new()
	xp_tag.text = tr("UI_PROFILE_XP_LABEL")
	xp_tag.add_theme_font_size_override("font_size", 14)
	xp_tag.add_theme_color_override("font_color", UiTokens.ACCENT_PROFILE)
	xp_line.add_child(xp_tag)

	var xp_values := Label.new()
	xp_values.text = "%s / %s" % [
		_format_int(int(_profile_data.get("xp", 0))),
		_format_int(int(_profile_data.get("xp_to_next", 100))),
	]
	xp_values.add_theme_font_size_override("font_size", 14)
	xp_values.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	xp_line.add_child(xp_values)

	_xp_bar = ProgressBar.new()
	## Shorter bar (length), keep a readable thickness.
	_xp_bar.custom_minimum_size = Vector2(148, 12)
	_xp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_xp_bar.max_value = 1.0
	_xp_bar.value = 0.0
	_xp_bar.show_percentage = false
	_xp_bar.add_theme_stylebox_override("background", UiStyle.profile_progress_bg())
	var xp_fill := UiStyle.progress_fill(Color(0.85, 0.28, 0.78, 1))
	xp_fill.set_corner_radius_all(8)
	_xp_bar.add_theme_stylebox_override("fill", xp_fill)
	xp_col.add_child(_xp_bar)

	var next_xp := Label.new()
	next_xp.text = tr("UI_PROFILE_NEXT_LEVEL").format({
		"xp": _format_int(int(_profile_data.get("xp_remaining", 0))),
	})
	next_xp.add_theme_font_size_override("font_size", 12)
	next_xp.add_theme_color_override("font_color", UiTokens.PROFILE_TITLE_CAPS)
	xp_col.add_child(next_xp)

	## Divider + league column (~1/4 width), no nested card.
	## Fixed non-shrinking rule (ColorRect+EXPAND can collapse to invisible).
	var divider_wrap := CenterContainer.new()
	divider_wrap.custom_minimum_size = Vector2(14, 0)
	divider_wrap.size_flags_horizontal = 0
	divider_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	divider_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(divider_wrap)
	var divider := Panel.new()
	divider.custom_minimum_size = Vector2(2, 168)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var divider_style := StyleBoxFlat.new()
	divider_style.bg_color = Color(1, 1, 1, 0.22)
	divider_style.set_corner_radius_all(1)
	divider.add_theme_stylebox_override("panel", divider_style)
	divider_wrap.add_child(divider)

	var ranking: Dictionary = _profile_data.get("ranking", {})
	var league_col := VBoxContainer.new()
	league_col.alignment = BoxContainer.ALIGNMENT_CENTER
	league_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	league_col.custom_minimum_size.x = 150
	league_col.add_theme_constant_override("separation", 12)
	row.add_child(league_col)

	var league_title := Label.new()
	league_title.text = (
		tr("UI_PROFILE_LEAGUE") + " " + tr(str(ranking.get("league_key", "UI_LEAGUE_BRONZE")))
	).to_upper()
	league_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	league_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	league_title.add_theme_font_size_override("font_size", 16)
	league_title.add_theme_color_override("font_color", UiTokens.ACCENT_PROFILE)
	league_col.add_child(league_title)

	## Icon follows trophy league tier (not a fixed diamond).
	var league_icon := Label.new()
	league_icon.text = str(ranking.get("league_icon", "🥉"))
	league_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	league_icon.add_theme_font_size_override("font_size", 64)
	var league_emoji_font := UiFonts.emoji_font()
	if league_emoji_font != null:
		league_icon.add_theme_font_override("font", league_emoji_font)
	league_col.add_child(league_icon)

	var points := Label.new()
	points.text = "🏆  %s" % _format_int(int(ranking.get("points", 0)))
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", 22)
	points.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	league_col.add_child(points)

	_animated_nodes.append(panel)
	call_deferred(
		"_fit_hero_mock_proportions",
		panel, avatar_wrap, avatar, league_col, league_icon, league_title, points
	)
	call_deferred("_animate_xp_bar")
	return panel


func _on_avatar_hover(avatar: Control, show_overlay: bool) -> void:
	if not is_instance_valid(avatar) or not (avatar is CircularAvatarScript):
		return
	var circ := avatar as CircularAvatarScript
	var target := 1.0 if show_overlay else 0.0
	var tween := _track_tween(create_tween())
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(circ.set_overlay_alpha, circ.overlay_alpha, target, 0.2)


func _fit_hero_mock_proportions(
	hero: Control,
	avatar_wrap: Control,
	avatar: Control,
	league_col: Control,
	league_icon: Label,
	league_title: Label = null,
	points: Label = null
) -> void:
	if not is_instance_valid(hero):
		return
	await get_tree().process_frame
	if not is_instance_valid(hero):
		return
	var h := hero.size.y
	var w := hero.size.x
	if h <= 1.0 or w <= 1.0:
		return
	## Avatar ≈ full inner height; league column wider for larger right-side info.
	var avatar_side := clampf(h - 32.0, 128.0, 196.0)
	var league_w := clampf(w * 0.34, 140.0, 190.0)
	if is_instance_valid(avatar_wrap):
		avatar_wrap.custom_minimum_size = Vector2(avatar_side, avatar_side)
	if is_instance_valid(league_col):
		league_col.custom_minimum_size.x = league_w
	if is_instance_valid(avatar) and avatar is CircularAvatarScript:
		var circ := avatar as CircularAvatarScript
		circ.ring_width = clampf(avatar_side * 0.022, 3.0, 4.5)
		circ.ring_gap = clampf(avatar_side * 0.016, 2.0, 3.5)
		circ.queue_redraw()
	if is_instance_valid(league_title):
		league_title.add_theme_font_size_override("font_size", int(clampf(league_w * 0.105, 15.0, 19.0)))
	if is_instance_valid(league_icon):
		league_icon.add_theme_font_size_override("font_size", int(clampf(league_w * 0.50, 58.0, 78.0)))
	if is_instance_valid(points):
		points.add_theme_font_size_override("font_size", int(clampf(league_w * 0.135, 20.0, 26.0)))


func _build_stats_strip() -> PanelContainer:
	## Mock: icon left + value/label right, thin vertical dividers.
	## Height only (user-requested) — never change tile/page width here.
	var panel := _tile()
	panel.custom_minimum_size.y = UiTokens.DASH_STAT_HEIGHT
	var margin := _pad(10, 14)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	var ranking: Dictionary = _profile_data.get("ranking", {})
	var items := [
		{"icon": "🎮", "value": _format_int(int(_profile_data.get("games_played", 0))), "label": tr("UI_PROFILE_STAT_GAMES"), "color": Color(0.36, 0.75, 1.0)},
		{"icon": "🏆", "value": _format_int(int(_profile_data.get("wins", 0))), "label": tr("UI_PROFILE_STAT_WINS"), "color": UiTokens.FEEDBACK_CORRECT},
		{"icon": "🎯", "value": "%.0f%%" % _profile_data.get("win_rate_percent", 0.0), "label": tr("UI_PROFILE_STAT_WINRATE"), "color": Color(1.0, 0.55, 0.18)},
		{"icon": "🔥", "value": str(_profile_data.get("best_win_streak", 0)), "label": tr("UI_PROFILE_STAT_STREAK"), "color": Color(1.0, 0.42, 0.28)},
		{"icon": "📊", "value": _format_int(int(ranking.get("points", 0))), "label": tr("UI_PROFILE_STAT_RANK"), "color": UiTokens.ACCENT_PROFILE},
	]
	for i in range(items.size()):
		if i > 0:
			row.add_child(_stat_strip_divider())
		var item: Dictionary = items[i]
		row.add_child(_stat_icon_cell(str(item.icon), str(item.value), str(item.label), item.color))

	_animated_nodes.append(panel)
	return panel


func _stat_strip_divider() -> Control:
	## Non-expanding vertical rule between each stat (mock).
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(14, 69)
	wrap.size_flags_horizontal = 0 ## SIZE_FILL only — never expand/shrink away.
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := Panel.new()
	line.custom_minimum_size = Vector2(2, 65)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.22)
	style.set_corner_radius_all(1)
	line.add_theme_stylebox_override("panel", style)
	wrap.add_child(line)
	return wrap


func _stat_icon_cell(icon: String, value: String, label: String, color: Color) -> Control:
	## Mock cell: icon + value on top; caption centered between separators below.
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.size_flags_stretch_ratio = 1.0
	pad.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 2)
	pad.add_theme_constant_override("margin_right", 2)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 2)
	pad.add_child(col)

	## Top block: icon + number, same vertical level, lifted together.
	var top_center := CenterContainer.new()
	top_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(top_center)

	var top_lift := MarginContainer.new()
	top_lift.add_theme_constant_override("margin_top", -9)
	top_center.add_child(top_lift)

	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 6)
	top_lift.add_child(top)

	var icon_slot := CenterContainer.new()
	icon_slot.custom_minimum_size = Vector2(44, 44)
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_nudge := MarginContainer.new()
	icon_nudge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_nudge.add_theme_constant_override("margin_left", -8)
	icon_nudge.add_child(icon_slot)
	top.add_child(icon_nudge)

	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.custom_minimum_size = Vector2(44, 44)
	icon_label.add_theme_font_size_override("font_size", 38)
	icon_label.add_theme_color_override("font_color", color)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon_label.add_theme_font_override("font", emoji_font)
	icon_slot.add_child(icon_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_label.add_theme_font_size_override("font_size", 26)
	value_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	var value_wrap := MarginContainer.new()
	value_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	value_wrap.add_theme_constant_override("margin_left", 6)
	value_wrap.add_child(value_label)
	top.add_child(value_wrap)

	## Caption centered in the full column between separators.
	var caption := Label.new()
	caption.text = label.to_upper()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", Color(0.62, 0.66, 0.78, 1))
	var caption_wrap := MarginContainer.new()
	caption_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption_wrap.add_theme_constant_override("margin_top", 5)
	## Keep tile height: larger caption overlaps instead of growing.
	caption_wrap.add_theme_constant_override("margin_bottom", -8)
	caption_wrap.add_child(caption)
	col.add_child(caption_wrap)
	return pad


func _build_mastery_mosaic() -> Control:
	## Mock grid: categories (tall left) | best subject + win split (stacked right).
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiTokens.DASH_GUTTER)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cats := _build_categories_tile()
	cats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cats.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cats.size_flags_stretch_ratio = 1.2
	row.add_child(cats)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", UiTokens.DASH_GUTTER)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.85
	row.add_child(right)

	var best := _build_best_subject_tile()
	best.custom_minimum_size.y = UiTokens.DASH_BEST_SUBJECT_HEIGHT
	best.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	best.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add_child(best)

	var dist := _build_win_distribution_tile()
	dist.custom_minimum_size.y = UiTokens.DASH_WIN_SPLIT_HEIGHT
	dist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dist.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(dist)

	_animated_nodes.append(row)
	return row


func _build_categories_tile() -> PanelContainer:
	## Header + rows [icon | name/bar | NIVEAU+n | badge] — max 6 visible.
	var panel := _tile()
	panel.custom_minimum_size.y = UiTokens.DASH_CATEGORY_HEIGHT
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := _tile_body(panel, tr("UI_PROFILE_CATEGORIES_MASTERED"))
	## Extra air between title and category rows.
	root.add_theme_constant_override("separation", 13)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 14)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(list)

	var categories: Array = _profile_data.get("categories", []).duplicate()
	categories.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_played := int(a.get("games_played", 0)) > 0
		var b_played := int(b.get("games_played", 0)) > 0
		if a_played != b_played:
			return a_played
		return float(a.get("accuracy_percent", 0.0)) > float(b.get("accuracy_percent", 0.0))
	)
	var shown := 0
	const MAX_VISIBLE := 6
	for row in categories:
		if shown >= MAX_VISIBLE:
			break
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("games_played", 0)) <= 0 and not _profile_data.get("is_demo", false):
			continue
		list.add_child(_category_mastery_row(row))
		shown += 1
	if shown == 0:
		list.add_child(_empty(tr("UI_PROFILE_NO_CATEGORIES")))
	## Avoid double-counting when embedded in the mosaic.
	return panel


func _mastery_category_icon(icon_text: String, accent: Color) -> Control:
	## Shared badge used by categories + best subject (identical size/glow).
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(54, 54)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	icon_style.set_corner_radius_all(27)
	icon_style.set_content_margin_all(0)
	icon_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
	icon_style.shadow_size = 2
	bg.add_theme_stylebox_override("panel", icon_style)
	slot.add_child(bg)

	var icon := Label.new()
	icon.text = icon_text
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", 28)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	slot.add_child(icon)
	return slot


func _category_mastery_row(row: Dictionary) -> Control:
	var accent := UiTokens.accent_for_category(str(row.get("id", "")))
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	hbox.add_child(_mastery_category_icon(str(row.get("icon", "🧠")), accent))

	## Name + progress bar (center stretch).
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 5)
	hbox.add_child(mid)

	var title := Label.new()
	title.text = str(row.get("name", ""))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	mid.add_child(title)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 1.0
	bar.value = float(row.get("mastery_progress", 0.0))
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UiStyle.profile_progress_bg())
	var fill := UiStyle.progress_fill(accent)
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", fill)
	mid.add_child(bar)

	## Level column: small "NIVEAU" over large accent number (mock right block).
	var level_col := VBoxContainer.new()
	level_col.alignment = BoxContainer.ALIGNMENT_CENTER
	level_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_col.add_theme_constant_override("separation", 0)
	level_col.custom_minimum_size.x = 52
	hbox.add_child(level_col)

	var level_caption := Label.new()
	level_caption.text = tr("UI_PROFILE_LEVEL_CAPTION").to_upper()
	level_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_caption.add_theme_font_size_override("font_size", 9)
	level_caption.add_theme_color_override("font_color", UiTokens.PROFILE_TITLE_CAPS)
	level_col.add_child(level_caption)

	var level_num := Label.new()
	level_num.text = str(row.get("display_level", row.get("mastery_level", 1)))
	level_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_num.add_theme_font_size_override("font_size", 20)
	level_num.add_theme_color_override("font_color", accent)
	var level_num_wrap := MarginContainer.new()
	level_num_wrap.add_theme_constant_override("margin_top", -2)
	level_num_wrap.add_child(level_num)
	level_col.add_child(level_num_wrap)

	## Rank badge — only gold / silver / bronze (top 3); spacer keeps levels aligned.
	var medal_kind := str(row.get("medal", "none"))
	if medal_kind != "none":
		var medal := Label.new()
		medal.text = _medal_icon(medal_kind)
		medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		medal.custom_minimum_size = Vector2(28, 28)
		medal.add_theme_font_size_override("font_size", 24)
		var emoji_font := UiFonts.emoji_font()
		if emoji_font != null:
			medal.add_theme_font_override("font", emoji_font)
		hbox.add_child(medal)
	else:
		var medal_slot := Control.new()
		medal_slot.custom_minimum_size = Vector2(28, 28)
		medal_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(medal_slot)
	return hbox


func _build_best_subject_tile() -> PanelContainer:
	## Mock: [icon] name | big % + caption — no level (same icon as categories).
	var panel := _tile(UiTokens.FEEDBACK_CORRECT)
	var root := _tile_body(panel, tr("UI_PROFILE_BEST_SUBJECT"))
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var best: Dictionary = _profile_data.get("best_category", {})
	if best.is_empty():
		root.add_child(_empty(tr("UI_PROFILE_NO_CATEGORIES")))
		return panel

	var accent := UiTokens.accent_for_category(str(best.get("id", "")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(row)

	row.add_child(_mastery_category_icon(str(best.get("icon", "🧠")), accent))

	var name_label := Label.new()
	name_label.text = str(best.get("name", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	row.add_child(name_label)

	var pct_col := VBoxContainer.new()
	pct_col.alignment = BoxContainer.ALIGNMENT_CENTER
	pct_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pct_col.add_theme_constant_override("separation", 0)
	row.add_child(pct_col)

	var pct_value := "%.0f" % float(best.get("accuracy_percent", 0.0))
	var pct := Label.new()
	pct.text = "%s%%" % pct_value
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	pct.add_theme_font_size_override("font_size", 28)
	pct.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	pct_col.add_child(pct)

	var acc_caption := Label.new()
	## Reuse existing i18n template, strip the percent placeholder for the small caption.
	acc_caption.text = tr("UI_PROFILE_BEST_SUBJECT_ACC").format({"percent": "§"}).replace("§%", "").replace("§", "").strip_edges()
	acc_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	acc_caption.add_theme_font_size_override("font_size", 10)
	acc_caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	pct_col.add_child(acc_caption)

	return panel


func _build_win_distribution_tile() -> PanelContainer:
	## Donut pinned under the title; legend below.
	var panel := _tile(UiTokens.ACCENT_PROFILE)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := _tile_body(panel, tr("UI_PROFILE_WIN_SPLIT"))
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(body)

	var donut_wrap := CenterContainer.new()
	donut_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	donut_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(donut_wrap)

	var donut := ProfileDonutScript.new()
	donut.custom_minimum_size = Vector2(168, 168)
	donut.line_width = 34.0
	donut_wrap.add_child(donut)

	var dist: Array = _profile_data.get("win_distribution", [])
	var segments: Array = []
	for row in dist:
		segments.append({"ratio": row.get("ratio", 0.0), "color": row.get("color", Color.WHITE)})
	var wins_sub := tr("UI_PROFILE_WINS_COUNT").format({"count": "§"}).replace("§", "").strip_edges()
	donut.set_segments(segments, str(_profile_data.get("wins", 0)), wins_sub)

	var legend_scroll := ScrollContainer.new()
	legend_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	legend_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	## Fixed legend viewport — extra categories scroll; donut keeps center space.
	legend_scroll.custom_minimum_size.y = 78
	legend_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend_scroll.size_flags_vertical = Control.SIZE_SHRINK_END
	body.add_child(legend_scroll)

	var legend := VBoxContainer.new()
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_theme_constant_override("separation", 5)
	legend_scroll.add_child(legend)
	if dist.is_empty():
		legend.add_child(_empty(tr("UI_PROFILE_NO_CATEGORIES")))
	else:
		for row in dist:
			var line := HBoxContainer.new()
			line.add_theme_constant_override("separation", 6)
			line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			legend.add_child(line)
			var dot := Label.new()
			dot.text = "●"
			dot.add_theme_font_size_override("font_size", 11)
			dot.add_theme_color_override("font_color", row.get("color", UiTokens.PROFILE_TEXT))
			line.add_child(dot)
			var text := Label.new()
			text.text = str(row.get("name", ""))
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text.clip_text = true
			text.add_theme_font_size_override("font_size", 12)
			text.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
			line.add_child(text)
			var wins_label := Label.new()
			wins_label.text = _format_int(int(row.get("wins", 0)))
			wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			wins_label.add_theme_font_size_override("font_size", 12)
			wins_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
			var wins_wrap := MarginContainer.new()
			wins_wrap.add_theme_constant_override("margin_right", 8)
			wins_wrap.add_child(wins_label)
			line.add_child(wins_wrap)

	return panel


func _build_history_tile() -> PanelContainer:
	## Height only — snug for 4 matches max (same icon/text scale as categories).
	var panel := _tile()
	panel.custom_minimum_size.y = UiTokens.DASH_HISTORY_HEIGHT
	var root := _tile_body(panel, tr("UI_PROFILE_HISTORY_TITLE"))
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 12)
	root.add_child(list)

	var history: Array = _profile_data.get("history", [])
	if history.is_empty():
		list.add_child(_empty(tr("UI_PROFILE_NO_HISTORY")))
	else:
		var count := 0
		for row in history:
			if count >= 4:
				break
			list.add_child(_history_row(row))
			count += 1
	_animated_nodes.append(panel)
	return panel


func _history_row(row: Dictionary) -> Control:
	var won: bool = row.get("won", false)
	var accent := UiTokens.FEEDBACK_CORRECT if won else UiTokens.FEEDBACK_WRONG
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	## Same badge footprint as categories (54 / glyph 28 / soft glow).
	var avatar_slot := Control.new()
	avatar_slot.custom_minimum_size = Vector2(54, 54)
	avatar_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(avatar_slot)

	var avatar_bg := Panel.new()
	avatar_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var av_style := StyleBoxFlat.new()
	av_style.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	av_style.set_corner_radius_all(27)
	av_style.set_content_margin_all(0)
	av_style.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
	av_style.shadow_size = 2
	avatar_bg.add_theme_stylebox_override("panel", av_style)
	avatar_slot.add_child(avatar_bg)

	var initial := Label.new()
	initial.text = str(row.get("opponent", "?"))[0].to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	initial.add_theme_font_size_override("font_size", 28)
	initial.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	avatar_slot.add_child(initial)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 2)
	hbox.add_child(left)

	var name_label := Label.new()
	name_label.text = str(row.get("opponent", ""))
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	left.add_child(name_label)

	var cat := Label.new()
	cat.text = str(row.get("category_name", ""))
	cat.clip_text = true
	cat.add_theme_font_size_override("font_size", 14)
	cat.add_theme_color_override("font_color", UiTokens.accent_for_category(str(row.get("category_id", ""))))
	left.add_child(cat)

	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(mid)

	var result := Label.new()
	result.text = (tr("UI_PROFILE_WIN") if won else tr("UI_PROFILE_LOSS")).to_upper()
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 14)
	result.add_theme_color_override("font_color", accent)
	mid.add_child(result)

	var theirs := maxi(int(row.get("total_count", 0)) - int(row.get("correct_count", 0)), 0)
	var score := Label.new()
	score.text = tr("UI_PROFILE_MATCH_SCORE").format({
		"mine": row.get("correct_count", 0),
		"theirs": theirs,
	})
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 14)
	score.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	mid.add_child(score)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(right)

	var age := Label.new()
	age.text = _format_age(int(row.get("age_hours", 0)))
	age.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	age.add_theme_font_size_override("font_size", 14)
	age.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	right.add_child(age)

	var chevron := Label.new()
	chevron.text = ">"
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chevron.add_theme_font_size_override("font_size", 18)
	chevron.add_theme_color_override("font_color", UiTokens.PROFILE_TITLE_CAPS)
	right.add_child(chevron)
	return hbox


func _build_badges_tile() -> PanelContainer:
	var panel := _tile(UiTokens.ACCENT_LEADERBOARD)
	var root := _tile_body(panel, tr("UI_PROFILE_BADGES_RECENT"))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)

	var achievements: Array = _profile_data.get("achievements", [])
	var limit := mini(achievements.size(), 6)
	for i in range(limit):
		grid.add_child(_badge_cell(achievements[i]))
	_nudge_tile_height(root, 5)
	_animated_nodes.append(panel)
	return panel


func _badge_cell(achievement: Dictionary) -> Button:
	var unlocked: bool = achievement.get("unlocked", false)
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 96)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	var accent := UiTokens.ACCENT_LEADERBOARD if unlocked else UiTokens.PROFILE_TEXT_MUTED
	button.add_theme_stylebox_override("normal", UiStyle.profile_card(accent))
	button.add_theme_stylebox_override("hover", UiStyle.profile_card(accent, true))
	button.add_theme_stylebox_override("pressed", UiStyle.profile_card(accent))
	button.modulate = Color.WHITE if unlocked else UiTokens.PROFILE_BADGE_LOCKED
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.text = "%s\n%s\n%s" % [
		str(achievement.get("icon", "?")),
		tr(str(achievement.get("title_key", ""))),
		tr(str(achievement.get("desc_key", ""))),
	]
	button.add_theme_font_size_override("font_size", 10)
	button.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	button.pressed.connect(_on_badge_pressed.bind(achievement))
	PressScaleUtil.wire(button, self)
	return button


func _build_season_tile() -> PanelContainer:
	var panel := _tile(UiTokens.ACCENT_LEADERBOARD, true)
	var root := _tile_body(panel, tr("UI_PROFILE_BEST_SEASON"))
	var season: Dictionary = _profile_data.get("season", {})

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	root.add_child(row)

	var crest := Label.new()
	crest.text = "🏅"
	crest.add_theme_font_size_override("font_size", 48)
	row.add_child(crest)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	var season_label := Label.new()
	season_label.text = tr("UI_PROFILE_SEASON_N").format({"n": season.get("number", 1)}).to_upper()
	season_label.add_theme_font_size_override("font_size", 12)
	season_label.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
	col.add_child(season_label)

	col.add_child(_season_stat_line("🏆", tr("UI_PROFILE_SEASON_BEST_RANK"), "#%s" % _format_int(int(season.get("best_rank", 0)))))
	col.add_child(_season_stat_line("🥇", tr("UI_PROFILE_SEASON_WINS"), _format_int(int(season.get("wins", 0)))))
	col.add_child(_season_stat_line("◎", tr("UI_PROFILE_WIN_RATE"), "%.0f%%" % float(season.get("win_rate", 0.0))))

	_nudge_tile_height(root, 5)
	_animated_nodes.append(panel)
	return panel


func _season_stat_line(icon: String, label: String, value: String) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 12)
	line.add_child(icon_label)
	var caption := Label.new()
	caption.text = label
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	line.add_child(caption)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", 12)
	value_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	line.add_child(value_label)
	return line


func _tile(accent: Color = Color(0, 0, 0, 0), raised: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_stylebox_override("panel", UiStyle.profile_card(accent, raised))
	return panel


func _nudge_tile_height(root: VBoxContainer, extra_px: float) -> void:
	## Height-only slack for tiles without a fixed DASH_*_HEIGHT.
	var slack := Control.new()
	slack.custom_minimum_size.y = extra_px
	slack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slack)


func _tile_body(panel: PanelContainer, title_text: String, with_see_all: bool = false) -> VBoxContainer:
	var margin := _pad(12, 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(header)

	var title := Label.new()
	title.text = title_text.to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(title)

	if with_see_all:
		var see_all := Label.new()
		see_all.text = tr("UI_PROFILE_SEE_ALL").to_upper() + " >"
		see_all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		see_all.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		see_all.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		see_all.add_theme_font_size_override("font_size", 14)
		see_all.add_theme_color_override("font_color", UiTokens.ACCENT_PROFILE)
		header.add_child(see_all)
	return root


func _pad(h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	return margin


func _empty(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	return label


func _medal_icon(medal: String) -> String:
	match medal:
		"gold":
			return "🥇"
		"silver":
			return "🥈"
		"bronze":
			return "🥉"
		_:
			return "🛡️"


func _format_int(value: int) -> String:
	var raw := str(absi(value))
	var out := ""
	var count := 0
	for i in range(raw.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = " " + out
		out = raw[i] + out
		count += 1
	return ("-" if value < 0 else "") + out


func _format_age(hours: int) -> String:
	if hours <= 0:
		return tr("UI_PROFILE_TIME_NOW")
	if hours < 24:
		return tr("UI_PROFILE_TIME_HOURS").format({"hours": hours})
	return tr("UI_PROFILE_TIME_DAYS").format({"days": int(hours / 24.0)})


func _style_profile_button(button: Button, accent: Color) -> void:
	if button == null:
		return
	var normal := UiStyle.profile_card(accent)
	normal.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	var hover := UiStyle.profile_card(accent, true)
	hover.bg_color = Color(accent.r, accent.g, accent.b, 0.4)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)


func _animate_xp_bar() -> void:
	if _xp_bar == null or not is_instance_valid(_xp_bar):
		return
	var target := clampf(float(_profile_data.get("xp_progress", 0.0)), 0.0, 1.0)
	_xp_bar.value = 0.0
	var tween := _track_tween(create_tween())
	tween.tween_property(_xp_bar, "value", target, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _play_entrance_animation() -> void:
	## Only fade — never touch position (breaks VBox layout / causes overlap).
	var delay := 0.0
	for node in _animated_nodes:
		if not is_instance_valid(node):
			continue
		node.modulate.a = 0.0
		var tween := _track_tween(create_tween())
		tween.tween_property(node, "modulate:a", 1.0, 0.2).set_delay(delay)
		delay += 0.025
	_animated_nodes.clear()


func _open_edit_profile() -> void:
	pseudo_input.text = str(_profile_data.get("player_name", ""))
	remove_photo_button.visible = _profile_data.get("has_custom_avatar", false)
	edit_backdrop.visible = true
	edit_panel.visible = true
	edit_panel.move_to_front()
	pseudo_input.grab_focus()


func _close_edit_profile() -> void:
	edit_backdrop.visible = false
	edit_panel.visible = false


func _on_edit_save_pressed() -> void:
	SaveManager.set_player_name(pseudo_input.text)
	_close_edit_profile()
	refresh()


func _on_edit_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_close_edit_profile()


func _on_badge_pressed(achievement: Dictionary) -> void:
	badge_detail_icon.text = str(achievement.get("icon", "?"))
	badge_detail_title.text = tr(str(achievement.get("title_key", "")))
	badge_detail_desc.text = tr(str(achievement.get("desc_key", "")))
	if not achievement.get("unlocked", false):
		badge_detail_desc.text += "\n\n" + tr("UI_PROFILE_BADGE_LOCKED")
	badge_backdrop.visible = true
	badge_detail_panel.visible = true
	badge_detail_panel.move_to_front()


func _close_badge_detail() -> void:
	badge_backdrop.visible = false
	badge_detail_panel.visible = false


func _on_badge_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			_close_badge_detail()


func _on_change_photo_pressed() -> void:
	photo_dialog.popup_centered_ratio(0.8)


func _on_remove_photo_pressed() -> void:
	SaveManager.clear_profile_avatar()
	remove_photo_button.visible = false
	refresh()
	_open_edit_profile()


func _on_photo_selected(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	if SaveManager.set_profile_avatar_from_file(paths[0]):
		refresh()
		_open_edit_profile()


func _on_locale_changed(_locale: String) -> void:
	_apply_translations()
	refresh()
