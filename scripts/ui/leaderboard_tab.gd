## Leaderboard tab — mock layout (header, Général/Amis, podium, lists).
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const GameAssets = preload("res://scripts/config/game_assets.gd")
const LeaderboardSnapshot = preload("res://scripts/profile/leaderboard_snapshot.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiFonts = preload("res://scripts/config/ui_fonts.gd")

@onready var scroll: ScrollContainer = %Scroll
@onready var content: VBoxContainer = %Content

var _scope: String = "general" ## general | friends
var _selected_filter: String = "all"
var _online_entries_by_category: Dictionary = {}
var _scope_buttons: Dictionary = {} ## id -> Button


func _ready() -> void:
	if scroll != null:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_apply()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	NetworkManager.leaderboard_received.connect(_on_leaderboard_received)
	NetworkManager.leaderboard_failed.connect(_on_leaderboard_failed)


func on_tab_shown() -> void:
	_apply()


func _apply() -> void:
	_rebuild()


func _rebuild() -> void:
	while content.get_child_count() > 0:
		var child := content.get_child(0)
		content.remove_child(child)
		child.free()

	var global_snap := _global_snapshot()
	var friends_snap := LeaderboardSnapshot.build_friends(LocaleManager.get_content_locale())

	content.add_child(_scope_toggle())

	if _scope == "friends":
		content.add_child(_board_section(
			tr("UI_LEADERBOARD_FRIENDS_TITLE"),
			"👥",
			friends_snap,
			true,
			false
		))
	else:
		content.add_child(_category_sub_toggle())
		content.add_child(_board_section(
			tr("UI_LEADERBOARD_GENERAL_TITLE"),
			"🌐",
			global_snap,
			true,
			false
		))

	if bool(global_snap.get("is_demo", false)):
		var hint := Label.new()
		hint.text = tr("UI_LEADERBOARD_DEMO_HINT")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		content.add_child(hint)
	else:
		NetworkManager.fetch_leaderboard(_selected_filter)


func _global_snapshot() -> Dictionary:
	var local_snap := LeaderboardSnapshot.build(_selected_filter, LocaleManager.get_content_locale())
	## Never let a short online payload replace the padded demo board.
	if bool(local_snap.get("is_demo", false)):
		return local_snap
	var online_entries: Variant = _online_entries_by_category.get(_selected_filter)
	if online_entries != null:
		return _snapshot_from_online(online_entries)
	return local_snap


func _scope_toggle() -> Control:
	var panel := _toggle_track(24, 5)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)
	_scope_buttons.clear()
	var general := _pill_chip(
		"🌐",
		tr("UI_LEADERBOARD_SCOPE_GENERAL"),
		_scope == "general",
		54,
		22,
		19,
		_on_scope_pressed.bind("general")
	)
	var friends := _pill_chip(
		"👤",
		tr("UI_LEADERBOARD_SCOPE_FRIENDS"),
		_scope == "friends",
		54,
		22,
		19,
		_on_scope_pressed.bind("friends")
	)
	row.add_child(general)
	row.add_child(friends)
	_scope_buttons["general"] = general
	_scope_buttons["friends"] = friends
	return panel


func _category_sub_toggle() -> Control:
	var panel := _toggle_track(26, 8)
	const ICON := 64.0

	var scroll_row := ScrollContainer.new()
	scroll_row.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll_row.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_row.custom_minimum_size.y = ICON + 6.0
	panel.add_child(scroll_row)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll_row.add_child(row)

	for filter_data in LeaderboardSnapshot.available_filters(LocaleManager.get_content_locale()):
		if typeof(filter_data) != TYPE_DICTIONARY:
			continue
		var filter_id := str(filter_data.get("id", ""))
		if filter_id.is_empty():
			continue
		var tip := tr("UI_LEADERBOARD_MODE_ALL") if filter_id == "all" else str(filter_data.get("label", filter_id))
		row.add_child(_category_icon_chip(filter_id, ICON, tip))
	return panel


func _category_icon_chip(filter_id: String, size_px: float, tooltip: String) -> Button:
	var selected := _selected_filter == filter_id
	var accent := (
		UiTokens.ACCENT_LEADERBOARD if filter_id == "all"
		else UiTokens.accent_for_category(filter_id)
	)
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(size_px, size_px)
	btn.tooltip_text = tooltip
	btn.pressed.connect(_on_category_filter_pressed.bind(filter_id))
	PressScaleUtil.wire(btn, self)

	var chip := StyleBoxFlat.new()
	if selected:
		chip.bg_color = Color(accent.r, accent.g, accent.b, 0.95)
		chip.set_border_width_all(3)
		chip.border_color = Color(1, 1, 1, 0.9)
		chip.shadow_color = Color(accent.r, accent.g, accent.b, 0.4)
		chip.shadow_size = 10
	else:
		chip.bg_color = Color(1, 1, 1, 0.08)
		chip.set_border_width_all(2)
		chip.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	chip.set_corner_radius_all(int(size_px * 0.5))
	chip.content_margin_left = 0
	chip.content_margin_right = 0
	chip.content_margin_top = 0
	chip.content_margin_bottom = 0
	btn.add_theme_stylebox_override("normal", chip)
	btn.add_theme_stylebox_override("hover", chip)
	btn.add_theme_stylebox_override("pressed", chip)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))

	var emoji := "🏆" if filter_id == "all" else ProfileSnapshot._category_icon(filter_id)
	var icon := GameAssets.make_circular_icon_display(
		null if filter_id == "all" else GameAssets.category_texture(filter_id),
		emoji,
		size_px,
		int(size_px * 0.58),
		0.82
	)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	return btn


func _toggle_track(radius: int, pad: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.LEADERBOARD_CARD_BG
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = UiTokens.LEADERBOARD_CARD_BORDER
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _pill_chip(
	icon_text: String,
	label_text: String,
	selected: bool,
	height: float,
	icon_size: int,
	label_size: int,
	on_pressed: Callable
) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = height
	btn.pressed.connect(on_pressed)
	PressScaleUtil.wire(btn, self)

	var chip := StyleBoxFlat.new()
	if selected:
		chip.bg_color = UiTokens.ACCENT_LEADERBOARD
	else:
		chip.bg_color = Color(1, 1, 1, 0.06)
	chip.set_corner_radius_all(int(height * 0.37))
	chip.content_margin_left = 14
	chip.content_margin_right = 14
	chip.content_margin_top = 10
	chip.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", chip)
	btn.add_theme_stylebox_override("hover", chip)
	btn.add_theme_stylebox_override("pressed", chip)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon := Label.new()
	icon.text = icon_text
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", icon_size)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	row.add_child(icon)

	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", label_size)
	label.add_theme_color_override(
		"font_color",
		Color(0.12, 0.1, 0.08, 1) if selected else Color(1, 1, 1, 0.92)
	)
	row.add_child(label)
	return btn


func _board_section(
	title_text: String,
	icon_text: String,
	snapshot: Dictionary,
	with_podium: bool,
	show_title: bool = true
) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.leaderboard_surface(false, 14))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	if show_title:
		var header := HBoxContainer.new()
		header.add_theme_constant_override("separation", 8)
		header.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.add_child(header)

		var icon := Label.new()
		icon.text = icon_text
		icon.add_theme_font_size_override("font_size", 18)
		var emoji_font := UiFonts.emoji_font()
		if emoji_font != null:
			icon.add_theme_font_override("font", emoji_font)
		header.add_child(icon)

		var title := Label.new()
		title.text = title_text
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
		header.add_child(title)

	var podium: Array = snapshot.get("podium", [])
	var rest: Array = snapshot.get("rest", [])
	## Top 3 always when available (all categories + friends).
	if with_podium and not podium.is_empty():
		vbox.add_child(_make_podium(podium))

	var player_rank := int(snapshot.get("player_rank", 0))
	if player_rank > 0:
		var rank_hint := Label.new()
		rank_hint.text = tr("UI_LEADERBOARD_YOUR_RANK").format({"rank": player_rank})
		rank_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_hint.add_theme_font_size_override("font_size", 22)
		rank_hint.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
		vbox.add_child(rank_hint)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	vbox.add_child(list)

	var rows: Array = rest if with_podium and not podium.is_empty() else snapshot.get("entries", [])

	if rows.is_empty() and podium.is_empty():
		list.add_child(_make_empty_label(tr("UI_LEADERBOARD_EMPTY")))
	else:
		for entry in rows:
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if bool(entry.get("is_gap", false)):
				list.add_child(_make_gap_row(entry))
			else:
				list.add_child(_make_rank_row(entry))

	return panel


func _make_gap_row(entry: Dictionary) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size.y = 28
	var label := Label.new()
	var from_rank := int(entry.get("from_rank", 0))
	var to_rank := int(entry.get("to_rank", 0))
	if from_rank > 0 and to_rank >= from_rank:
		label.text = "%s ··· %s" % [_format_int(from_rank), _format_int(to_rank)]
	else:
		label.text = "···"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	wrap.add_child(label)
	return wrap


func _make_podium(podium: Array) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var slots: Array[Dictionary] = []
	if podium.size() >= 2:
		slots.append(podium[1])
	if podium.size() >= 1:
		slots.append(podium[0])
	if podium.size() >= 3:
		slots.append(podium[2])

	## Bottom-aligned steps: 1st > 2nd > 3rd. Host clips so the 1st bg cannot spill.
	var heights := [186.0, 208.0, 164.0]
	var places := [2, 1, 3]
	var accents := [
		Color(0.75, 0.78, 0.84, 1), ## silver
		UiTokens.ACCENT_LEADERBOARD, ## gold
		Color(0.90, 0.58, 0.32, 1), ## bronze
	]
	var max_h := 208.0
	row.custom_minimum_size.y = max_h

	for slot_index in range(slots.size()):
		var entry: Dictionary = slots[slot_index]
		var card_h: float = heights[slot_index]
		var slot := Control.new()
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.custom_minimum_size.y = max_h
		slot.clip_contents = true

		var host := Control.new()
		host.set_anchor(SIDE_LEFT, 0.0)
		host.set_anchor(SIDE_RIGHT, 1.0)
		host.set_anchor(SIDE_TOP, 1.0)
		host.set_anchor(SIDE_BOTTOM, 1.0)
		host.offset_left = 0.0
		host.offset_right = 0.0
		host.offset_top = -card_h
		host.offset_bottom = 0.0
		host.clip_contents = true
		slot.add_child(host)

		var card := _podium_card(
			entry,
			accents[slot_index],
			int(entry.get("rank", places[slot_index])),
			places[slot_index]
		)
		card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(card)
		row.add_child(slot)
	return row


func _podium_card(
	entry: Dictionary,
	accent: Color,
	rank: int,
	place: int
) -> PanelContainer:
	var is_first := place == 1
	var panel := PanelContainer.new()
	panel.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.LEADERBOARD_CARD_BG_RAISED
	style.set_corner_radius_all(16)
	style.set_border_width_all(2 if is_first else 1)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.85 if is_first else 0.45)
	match place:
		1:
			style.content_margin_left = 8
			style.content_margin_right = 8
			style.content_margin_top = 6
			style.content_margin_bottom = 10
		2:
			style.content_margin_left = 6
			style.content_margin_right = 6
			style.content_margin_top = 6
			style.content_margin_bottom = 10
		_:
			style.content_margin_left = 6
			style.content_margin_right = 6
			style.content_margin_top = 4
			style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.alignment = BoxContainer.ALIGNMENT_END
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var medal := Label.new()
	medal.text = _rank_medal_icon(rank)
	medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var medal_size := 48 if place == 1 else (40 if place == 2 else 34)
	medal.add_theme_font_size_override("font_size", medal_size)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		medal.add_theme_font_override("font", emoji_font)
	vbox.add_child(medal)

	var avatar_size := 52.0 if place == 1 else (42.0 if place == 2 else 36.0)
	vbox.add_child(_entry_avatar(entry, avatar_size, accent))

	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", UiTokens.PSEUDO_FONT_SIZE)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(name_label)

	var level := Label.new()
	level.text = "★ %s %d" % [tr("UI_PROFILE_LEVEL_CAPTION"), int(entry.get("level", 1))]
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.add_theme_font_size_override("font_size", 12 if place != 3 else 11)
	level.add_theme_color_override("font_color", Color(0.72, 0.62, 1.0, 1))
	vbox.add_child(level)

	var score := Label.new()
	score.text = "🏆 %s" % _format_int(int(entry.get("score", 0)))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 26 if place == 1 else (24 if place == 2 else 22))
	score.add_theme_color_override("font_color", accent)
	vbox.add_child(score)
	return panel


func _make_rank_row(entry: Dictionary) -> PanelContainer:
	var is_player: bool = bool(entry.get("is_player", false))
	var rank := int(entry.get("rank", 0))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	if is_player:
		style.bg_color = Color(UiTokens.ACCENT_LEADERBOARD.r, UiTokens.ACCENT_LEADERBOARD.g, UiTokens.ACCENT_LEADERBOARD.b, 0.38)
		style.set_border_width_all(1)
		style.border_color = Color(UiTokens.ACCENT_LEADERBOARD.r, UiTokens.ACCENT_LEADERBOARD.g, UiTokens.ACCENT_LEADERBOARD.b, 0.75)
	else:
		style.bg_color = UiTokens.LEADERBOARD_CARD_BG_RAISED.lightened(0.06)
		style.set_border_width_all(0)
	style.set_corner_radius_all(14)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	var rank_slot := Control.new()
	rank_slot.custom_minimum_size = Vector2(48, 48)
	rank_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_slot)

	if rank >= 1 and rank <= 3:
		var medal := Label.new()
		medal.text = _rank_medal_icon(rank)
		medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		medal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		medal.add_theme_font_size_override("font_size", 42)
		var emoji_font := UiFonts.emoji_font()
		if emoji_font != null:
			medal.add_theme_font_override("font", emoji_font)
		rank_slot.add_child(medal)
	else:
		var rank_disc := Panel.new()
		rank_disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rd := StyleBoxFlat.new()
		rd.bg_color = Color(1, 1, 1, 0.10)
		rd.set_corner_radius_all(16)
		rank_disc.add_theme_stylebox_override("panel", rd)
		rank_slot.add_child(rank_disc)
		var rank_label := Label.new()
		rank_label.text = str(rank)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rank_label.add_theme_font_size_override("font_size", 13)
		rank_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
		rank_slot.add_child(rank_label)

	row.add_child(_entry_avatar(entry, 44.0, UiTokens.ACCENT_LEADERBOARD))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)

	var name := Label.new()
	name.text = str(entry.get("name", ""))
	if is_player:
		name.text = tr("UI_LEADERBOARD_YOU_NAME").format({"name": name.text})
	name.clip_text = true
	name.add_theme_font_size_override("font_size", UiTokens.PSEUDO_FONT_SIZE)
	name.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	info.add_child(name)

	var level := Label.new()
	level.text = "★ %s %d" % [tr("UI_PROFILE_LEVEL_CAPTION"), int(entry.get("level", 1))]
	level.add_theme_font_size_override("font_size", 12)
	level.add_theme_color_override("font_color", Color(0.72, 0.62, 1.0, 1))
	info.add_child(level)

	var score := Label.new()
	score.text = "🏆 %s" % _format_int(int(entry.get("score", 0)))
	score.add_theme_font_size_override("font_size", 24)
	score.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
	row.add_child(score)
	return panel


func _rank_medal_icon(rank: int) -> String:
	match rank:
		1:
			return "🥇"
		2:
			return "🥈"
		3:
			return "🥉"
		_:
			return str(rank)


func _entry_avatar(entry: Dictionary, size_px: float, accent: Color) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(size_px, size_px)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.clip_contents = true

	var name := str(entry.get("name", "?"))
	var tex: Texture2D = null
	if bool(entry.get("is_player", false)):
		tex = SaveManager.get_profile_avatar_texture()
	if tex == null:
		tex = GameAssets.demo_avatar_texture(name)

	if tex != null:
		var display := GameAssets.make_circular_icon_display(
			tex,
			"",
			size_px,
			28,
			GameAssets.ROUND_AVATAR_INSET
		)
		display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		wrap.add_child(display)
		return wrap

	## Letter fallback if no texture at all.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(size_px, size_px)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var disc := StyleBoxFlat.new()
	disc.bg_color = Color(accent.r, accent.g, accent.b, 0.45)
	disc.set_corner_radius_all(int(size_px * 0.5))
	panel.add_theme_stylebox_override("panel", disc)
	wrap.add_child(panel)
	var initial := Label.new()
	initial.text = name.substr(0, 1).to_upper()
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	initial.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	initial.add_theme_font_size_override("font_size", int(size_px * 0.42))
	initial.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(initial)
	return wrap


func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	return label


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


func _on_scope_pressed(scope_id: String) -> void:
	if _scope == scope_id:
		return
	_scope = scope_id
	_rebuild()


func _on_category_filter_pressed(filter_id: String) -> void:
	if _selected_filter == filter_id:
		return
	_selected_filter = filter_id
	_rebuild()


func _on_leaderboard_received(category: String, entries: Array) -> void:
	_online_entries_by_category[category] = entries
	## Ignore online updates while the padded demo board is active.
	var local_snap := LeaderboardSnapshot.build(_selected_filter, LocaleManager.get_content_locale())
	if bool(local_snap.get("is_demo", false)):
		return
	if category == _selected_filter and _scope == "general":
		_rebuild()


func _on_leaderboard_failed(_category: String) -> void:
	pass


func _snapshot_from_online(entries: Array) -> Dictionary:
	var built: Array[Dictionary] = []
	for raw in entries:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var is_player := not NetworkManager.player_id.is_empty() \
			and str(raw.get("player_id", "")) == NetworkManager.player_id
		built.append({
			"id": str(raw.get("player_id", "")),
			"name": str(raw.get("display_name", "")),
			"score": int(raw.get("score", 0)),
			"level": int(raw.get("level", 1)),
			"rank_title_key": "UI_RANK_ROOKIE",
			"is_player": is_player,
			"rank": int(raw.get("rank", 0)),
			"country": "FR",
		})
	return LeaderboardSnapshot._pack_board(built, _selected_filter)


func _on_locale_changed(_locale: String) -> void:
	_apply()
