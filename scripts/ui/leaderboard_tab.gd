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
@onready var scope_host: VBoxContainer = %ScopeHost

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
	while scope_host.get_child_count() > 0:
		var scope_child := scope_host.get_child(0)
		scope_host.remove_child(scope_child)
		scope_child.free()

	var global_snap := _global_snapshot()
	var friends_snap := LeaderboardSnapshot.build_friends(LocaleManager.get_content_locale())

	scope_host.add_child(_scope_toggle())
	_tint_page_for_scope()

	if _scope == "friends":
		content.add_child(_board_section(
			tr("UI_LEADERBOARD_FRIENDS_TITLE"),
			"👥",
			friends_snap,
			true,
			false
		))
	else:
		content.add_child(_board_section(
			tr("UI_LEADERBOARD_GENERAL_TITLE"),
			"🌐",
			global_snap,
			true,
			false
		))

	if not bool(global_snap.get("is_demo", false)):
		NetworkManager.fetch_leaderboard(_selected_filter)
	ScrollTouch.let_drags_through(content)


func _global_snapshot() -> Dictionary:
	var local_snap := LeaderboardSnapshot.build(_selected_filter, LocaleManager.get_content_locale())
	## Never let a short online payload replace the padded demo board.
	if bool(local_snap.get("is_demo", false)):
		return local_snap
	var online_entries: Variant = _online_entries_by_category.get(_selected_filter)
	if online_entries != null:
		return _snapshot_from_online(online_entries)
	return local_snap


func _scope_accent() -> Color:
	return (
		UiTokens.ACCENT_LEADERBOARD_FRIENDS if _scope == "friends"
		else UiTokens.ACCENT_LEADERBOARD
	)


## Same unique aurora pair as the Général / Amis pills.
func _scope_aurore_themes() -> PackedStringArray:
	return AuroreTile.themes_closest_unique([
		UiTokens.ACCENT_LEADERBOARD,
		UiTokens.ACCENT_LEADERBOARD_FRIENDS,
	])


func _scope_card_bg(raised: bool = false) -> Color:
	if _scope == "friends":
		return (
			UiTokens.LEADERBOARD_FRIENDS_CARD_BG_RAISED if raised
			else UiTokens.LEADERBOARD_FRIENDS_CARD_BG
		)
	return UiTokens.LEADERBOARD_CARD_BG_RAISED if raised else UiTokens.LEADERBOARD_CARD_BG


func _tint_page_for_scope() -> void:
	## Soft wash shift so Général (lime) and Amis (olive) read apart.
	var accent := _scope_accent()
	var bg := get_node_or_null("TabPageBackground") as ColorRect
	if bg != null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/tab_page_bg.gdshader") as Shader
		mat.set_shader_parameter("accent", accent)
		mat.set_shader_parameter("deep", UiTokens.BG_CREAM)
		bg.material = mat
	## Only the header margin gap — never the full shell (Quiz uses that canvas).
	var top_bar := _find_top_app_bar()
	if top_bar != null:
		top_bar.set_margin_wash(accent)


func _find_top_app_bar() -> TopAppBar:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child("TopAppBar", true, false) as TopAppBar


func _scope_toggle() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scope_buttons.clear()
	var themes := _scope_aurore_themes()
	var general := _pill_chip(
		"🌐",
		tr("UI_LEADERBOARD_SCOPE_GENERAL"),
		_scope == "general",
		UiTokens.ACCENT_LEADERBOARD,
		54,
		22,
		19,
		_on_scope_pressed.bind("general"),
		str(themes[0]) if themes.size() > 0 else ""
	)
	var friends := _pill_chip(
		"👤",
		tr("UI_LEADERBOARD_SCOPE_FRIENDS"),
		_scope == "friends",
		UiTokens.ACCENT_LEADERBOARD_FRIENDS,
		54,
		22,
		19,
		_on_scope_pressed.bind("friends"),
		str(themes[1]) if themes.size() > 1 else ""
	)
	row.add_child(general)
	row.add_child(friends)
	_scope_buttons["general"] = general
	_scope_buttons["friends"] = friends
	return row


func _pill_chip(
	icon_text: String,
	label_text: String,
	selected: bool,
	accent: Color,
	height: float,
	icon_size: int,
	label_size: int,
	on_pressed: Callable,
	aurore_theme: String = ""
) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size.y = height
	btn.clip_contents = true
	btn.pressed.connect(on_pressed)
	PressScaleUtil.wire(btn, self)

	## Transparent chrome so aurora shows through; white ring when selected.
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color(0, 0, 0, 0)
	chip.set_corner_radius_all(int(height * 0.37))
	chip.content_margin_left = 14
	chip.content_margin_right = 14
	chip.content_margin_top = 10
	chip.content_margin_bottom = 10
	if selected:
		chip.set_border_width_all(3)
		chip.border_color = Color(1, 1, 1, 0.92)
	else:
		chip.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", chip)
	btn.add_theme_stylebox_override("hover", chip)
	btn.add_theme_stylebox_override("pressed", chip)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_hover_color", Color(0, 0, 0, 0))
	btn.add_theme_color_override("font_pressed_color", Color(0, 0, 0, 0))

	var bg := AuroreTile.new()
	bg.name = "AuroreFill"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.aurore_theme = aurore_theme if not aurore_theme.is_empty() else AuroreTile.theme_closest_to(accent)
	if not selected:
		bg.modulate = Color(1, 1, 1, 0.62)
	btn.add_child(bg)
	btn.move_child(bg, 0)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)

	var icon := Label.new()
	icon.text = icon_text
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", UiScale.font(icon_size))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	row.add_child(icon)

	var label := Label.new()
	label.text = label_text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiScale.font(label_size))
	label.add_theme_color_override(
		"font_color",
		Color.WHITE if selected else Color(1, 1, 1, 0.88)
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
	panel.add_theme_stylebox_override(
		"panel",
		UiStyle.leaderboard_surface(false, 14, _scope == "friends")
	)

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
		icon.add_theme_font_size_override("font_size", UiScale.font(18))
		var emoji_font := UiFonts.emoji_font()
		if emoji_font != null:
			icon.add_theme_font_override("font", emoji_font)
		header.add_child(icon)

		var title := Label.new()
		title.text = title_text
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.add_theme_font_size_override("font_size", UiScale.font(18))
		title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
		header.add_child(title)

	var podium: Array = snapshot.get("podium", [])
	var rest: Array = snapshot.get("rest", [])
	## Top 3 always when available (all categories + friends).
	if with_podium and not podium.is_empty():
		vbox.add_child(_make_podium(podium))

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
	label.add_theme_font_size_override("font_size", UiScale.font(16))
	label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	wrap.add_child(label)
	return wrap


func _make_podium(podium: Array) -> Control:
	## Top 3 as banner tiles: 2nd · 1st · 3rd (no pedestal steps), bottom-aligned.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var slots: Array[Dictionary] = []
	if podium.size() >= 2:
		slots.append(podium[1])
	if podium.size() >= 1:
		slots.append(podium[0])
	if podium.size() >= 3:
		slots.append(podium[2])

	var places := [2, 1, 3]
	var accents := [
		Color(0.75, 0.78, 0.84, 1), ## silver
		UiTokens.PODIUM_GOLD, ## classic gold — 1st place (not page champagne)
		Color(0.90, 0.58, 0.32, 1), ## bronze
	]

	for slot_index in range(slots.size()):
		var entry: Dictionary = slots[slot_index]
		var place: int = places[slot_index]
		var accent: Color = accents[slot_index]

		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.alignment = BoxContainer.ALIGNMENT_END
		col.add_theme_constant_override("separation", 0)
		## 1st place reads slightly taller in the row.
		if place == 1:
			col.size_flags_stretch_ratio = 1.15
		row.add_child(col)

		col.add_child(_podium_identity(
			entry,
			accent,
			int(entry.get("rank", place)),
			place
		))
	return row


func _podium_identity(
	entry: Dictionary,
	accent: Color,
	rank: int,
	place: int
) -> Control:
	## Card with the player's banner behind medal / avatar / name / trophies.
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var radius := 18 if place == 1 else 16
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(radius)
	style.set_border_width_all(0)
	style.shadow_color = Color(0, 0, 0, 0.16)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	tile.add_theme_stylebox_override("panel", style)

	var cosmetics: Dictionary = entry.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(str(entry.get("name", "")))
	tile.add_child(CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2.ZERO, radius))

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 8 if place == 1 else 6)
	pad.add_theme_constant_override("margin_right", 8 if place == 1 else 6)
	pad.add_theme_constant_override("margin_top", 10 if place == 1 else 8)
	pad.add_theme_constant_override("margin_bottom", 10 if place == 1 else 8)
	tile.add_child(pad)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(vbox)

	var medal := Label.new()
	medal.text = _rank_medal_icon(rank)
	medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var medal_size := 58 if place == 1 else (50 if place == 2 else 44)
	medal.add_theme_font_size_override("font_size", UiScale.font(medal_size))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		medal.add_theme_font_override("font", emoji_font)
	vbox.add_child(medal)

	var avatar_size := 100.0 if place == 1 else (86.0 if place == 2 else 78.0)
	vbox.add_child(_entry_avatar(entry, avatar_size, accent))

	var name_label := Label.new()
	name_label.text = str(entry.get("name", ""))
	if bool(entry.get("is_player", false)):
		name_label.text = tr("UI_LEADERBOARD_YOU_NAME").format({"name": name_label.text})
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(str(entry.get("name", ""))))
	)
	name_label.add_theme_color_override(
		"font_color",
		_scope_accent() if bool(entry.get("is_player", false)) else UiTokens.PROFILE_TEXT
	)
	vbox.add_child(name_label)

	var level := Label.new()
	level.text = "★ %s %d" % [tr("UI_PROFILE_LEVEL_CAPTION"), int(entry.get("level", 1))]
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.add_theme_font_size_override("font_size", UiScale.font(12))
	level.add_theme_color_override(
		"font_color",
		UiTokens.PROFILE_TEXT_MUTED if bool(entry.get("is_player", false)) else Color(0.72, 0.62, 1.0, 1)
	)
	vbox.add_child(level)

	var score := Label.new()
	score.text = "🏆 %s" % _format_int(int(entry.get("score", 0)))
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", UiScale.font(28 if place == 1 else (24 if place == 2 else 22)))
	score.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(score)
	return tile


func _make_rank_row(entry: Dictionary) -> PanelContainer:
	var is_player: bool = bool(entry.get("is_player", false))
	var rank := int(entry.get("rank", 0))
	var accent := _scope_accent()
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	if is_player:
		## Featured “you” tile — larger + dark card + scope-accent frame.
		style.bg_color = _scope_card_bg(true).darkened(0.08)
		style.set_border_width_all(3)
		style.border_color = accent
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.14)
		style.shadow_size = 6
		style.shadow_offset = Vector2(0, 2)
	else:
		style.bg_color = _scope_card_bg(true).lightened(0.06)
		style.set_border_width_all(0)
		style.shadow_color = Color(0, 0, 0, 0.14)
		style.shadow_size = 4
		style.shadow_offset = Vector2(0, 2)
	style.set_corner_radius_all(16 if is_player else 14)
	panel.add_theme_stylebox_override("panel", style)
	if is_player:
		panel.custom_minimum_size.y = 112

	## The player's banner fills the card, dimmed so the row stays readable.
	var cosmetics: Dictionary = entry.get("cosmetics", {})
	var banner := CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2.ZERO, 16 if is_player else 14)
	banner.modulate = Color(0.62, 0.62, 0.68)
	panel.add_child(banner)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14 if is_player else 10)
	pad.add_theme_constant_override("margin_right", 14 if is_player else 10)
	pad.add_theme_constant_override("margin_top", 14 if is_player else 9)
	pad.add_theme_constant_override("margin_bottom", 14 if is_player else 9)
	panel.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12 if is_player else 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pad.add_child(row)

	if is_player:
		## Left accent rail — same language as match-history accent bars.
		var bar := Panel.new()
		bar.custom_minimum_size = Vector2(5, 80)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar_style := StyleBoxFlat.new()
		bar_style.bg_color = accent
		bar_style.set_corner_radius_all(3)
		bar.add_theme_stylebox_override("panel", bar_style)
		row.add_child(bar)

	var rank_slot_size := 58.0 if is_player else 48.0
	var rank_slot := Control.new()
	rank_slot.custom_minimum_size = Vector2(rank_slot_size, rank_slot_size)
	rank_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rank_slot)

	if rank >= 1 and rank <= 3:
		var medal := Label.new()
		medal.text = _rank_medal_icon(rank)
		medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		medal.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		medal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		medal.add_theme_font_size_override("font_size", UiScale.font(48 if is_player else 42))
		var emoji_font := UiFonts.emoji_font()
		if emoji_font != null:
			medal.add_theme_font_override("font", emoji_font)
		rank_slot.add_child(medal)
	else:
		var rank_disc := Panel.new()
		rank_disc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var rd := StyleBoxFlat.new()
		## Opaque fill so the rank chip stays readable on the banner.
		if is_player:
			rd.bg_color = accent
		else:
			rd.bg_color = _scope_card_bg(true).lightened(0.10)
		rd.set_corner_radius_all(int(rank_slot_size * 0.34))
		rank_disc.add_theme_stylebox_override("panel", rd)
		rank_slot.add_child(rank_disc)
		var rank_label := Label.new()
		rank_label.text = str(rank)
		rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rank_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rank_label.add_theme_font_size_override("font_size", UiScale.font(18 if is_player else 13))
		rank_label.add_theme_color_override(
			"font_color",
			Color(0.10, 0.08, 0.04, 1) if is_player else UiTokens.PROFILE_TEXT
		)
		rank_slot.add_child(rank_label)

	row.add_child(_entry_avatar(entry, 80.0 if is_player else 58.0, accent))

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3 if is_player else 2)
	row.add_child(info)

	var name := Label.new()
	name.text = str(entry.get("name", ""))
	if is_player:
		name.text = tr("UI_LEADERBOARD_YOU_NAME").format({"name": name.text})
	name.clip_text = true
	name.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(
			str(entry.get("name", "")),
			UiTokens.PSEUDO_FONT_SIZE + (6 if is_player else 0)
		))
	)
	name.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	info.add_child(name)

	var level := Label.new()
	level.text = "★ %s %d" % [tr("UI_PROFILE_LEVEL_CAPTION"), int(entry.get("level", 1))]
	level.add_theme_font_size_override("font_size", UiScale.font(14 if is_player else 12))
	level.add_theme_color_override(
		"font_color",
		UiTokens.PROFILE_TEXT_MUTED if is_player else Color(0.72, 0.62, 1.0, 1)
	)
	info.add_child(level)

	var score := Label.new()
	score.text = "🏆 %s" % _format_int(int(entry.get("score", 0)))
	score.add_theme_font_size_override("font_size", UiScale.font(30 if is_player else 24))
	score.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
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
	## Framed avatar from the player's look (server, local or demo; see _pack_board).
	var cosmetics: Variant = entry.get("cosmetics")
	if typeof(cosmetics) == TYPE_DICTIONARY:
		var framed := CosmeticsView.avatar(cosmetics, size_px)
		framed.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return framed

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
	initial.add_theme_font_size_override("font_size", UiScale.font(int(size_px * 0.42)))
	initial.add_theme_color_override("font_color", Color.WHITE)
	panel.add_child(initial)
	return wrap


func _make_empty_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiScale.font(14))
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
			"cosmetics": raw.get("cosmetics", {}),
		})
	return LeaderboardSnapshot._pack_board(built, _selected_filter)


func _on_locale_changed(_locale: String) -> void:
	_apply()
