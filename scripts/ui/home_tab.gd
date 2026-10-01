## Home tab — hub du jour (pas de bouton Play : le FAB Quiz reste l'action principale).
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const UiFonts = preload("res://scripts/config/ui_fonts.gd")
const GameAssets = preload("res://scripts/config/game_assets.gd")
const ProfileSnapshot = preload("res://scripts/profile/profile_snapshot.gd")
const CircularAvatarScript = preload("res://scripts/ui/circular_avatar.gd")
const CountryFlags = preload("res://scripts/profile/country_flags.gd")
const DailyQuests = preload("res://scripts/profile/daily_quests.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")

@onready var content: VBoxContainer = %Content


func _ready() -> void:
	_rebuild()
	LocaleManager.locale_changed.connect(_on_locale_changed)


func on_tab_shown() -> void:
	_rebuild()


func _rebuild() -> void:
	var snapshot: Dictionary = ProfileSnapshot.build_full(LocaleManager.get_content_locale())
	_rebuild_cards(snapshot)


func _rebuild_cards(snapshot: Dictionary) -> void:
	for child in content.get_children():
		child.queue_free()

	content.add_child(_make_profile_summary_card(snapshot))
	content.add_child(_make_daily_challenges_card())
	content.add_child(_make_near_achievements_card(snapshot))
	content.add_child(_make_last_match_card(snapshot))
	ScrollTouch.let_drags_through(content)


func _make_profile_summary_card(snapshot: Dictionary) -> PanelContainer:
	## Identity first (avatar + pseudo), then league + streak mini-tiles.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 220
	## Empty chrome: banner alone is the card surface; light drop shadow only.
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0, 0, 0, 0)
	surface.set_corner_radius_all(UiTokens.PROFILE_CARD_RADIUS)
	surface.set_border_width_all(0)
	surface.shadow_color = Color(0, 0, 0, 0.16)
	surface.shadow_size = 5
	surface.shadow_offset = Vector2(0, 2)
	panel.add_theme_stylebox_override("panel", surface)

	var banner := CosmeticsView.banner(
		SaveManager.get_equipped_banner(), Vector2.ZERO, UiTokens.PROFILE_CARD_RADIUS
	)
	panel.add_child(banner)

	var margin := _pad(16, 14)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(row)

	## —— Identity block (hero of the tile) ——
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 14)
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.size_flags_stretch_ratio = 1.4
	identity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(identity)

	var avatar_wrap := Control.new()
	avatar_wrap.custom_minimum_size = Vector2(148, 148)
	avatar_wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	identity.add_child(avatar_wrap)

	var avatar := CircularAvatarScript.new()
	avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Ring = the frame equipped in the shop locker.
	ShopCatalog.apply_frame(avatar, SaveManager.get_equipped_frame())
	avatar.ring_gap = 2.0
	avatar.fill_color = UiTokens.HOME_CARD_BG_RAISED
	if bool(snapshot.get("is_online", false)):
		avatar.set_presence(CircularAvatarScript.Presence.ONLINE)
	else:
		avatar.set_presence(CircularAvatarScript.Presence.HIDDEN)
	avatar.set_avatar(snapshot.get("avatar_texture") as Texture2D)
	avatar_wrap.add_child(avatar)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 6)
	identity.add_child(info)

	var name_label := Label.new()
	name_label.text = str(snapshot.get("player_name", UiTokens.DEFAULT_PLAYER_NAME))
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(name_label.text, UiTokens.PSEUDO_FONT_SIZE_HOME + 6))
	)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	info.add_child(name_label)

	var country_row := HBoxContainer.new()
	country_row.add_theme_constant_override("separation", 8)
	country_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	country_row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info.add_child(country_row)

	var country_name := str(snapshot.get("country", "France"))
	var flag := str(snapshot.get("country_flag", "")).strip_edges()
	if flag.is_empty():
		flag = CountryFlags.emoji_for(country_name)

	## Clip the flag slot: Noto Color Emoji often leaves a thin leftover mark after flags.
	var flag_slot := Control.new()
	var flag_px := float(UiScale.font(24))
	flag_slot.custom_minimum_size = Vector2(flag_px * 1.2, flag_px * 1.15)
	flag_slot.clip_contents = true
	flag_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	flag_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	country_row.add_child(flag_slot)

	var flag_label := Label.new()
	flag_label.text = flag
	flag_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flag_label.add_theme_font_size_override("font_size", UiScale.font(22))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		flag_label.add_theme_font_override("font", emoji_font)
	else:
		flag_label.add_theme_font_override("font", UiFonts.text_with_emoji())
	flag_slot.add_child(flag_label)

	var country := Label.new()
	country.text = country_name
	country.clip_text = true
	country.add_theme_font_size_override("font_size", UiScale.font(18))
	country.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	country_row.add_child(country)

	## Level under the flag.
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 6)
	level_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	level_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(level_row)

	var level_caption := Label.new()
	level_caption.text = tr("UI_PROFILE_LEVEL_CAPTION").to_upper()
	level_caption.add_theme_font_size_override("font_size", UiScale.font(14))
	level_caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	level_row.add_child(level_caption)

	var level_num := Label.new()
	level_num.text = str(snapshot.get("level", 1))
	level_num.add_theme_font_size_override("font_size", UiScale.font(26))
	level_num.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	level_row.add_child(level_num)

	var ranking: Dictionary = snapshot.get("ranking", {})

	## —— League + streak as mini tiles ——
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 16)
	stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.size_flags_stretch_ratio = 1.0
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(stats)

	## League + streak mini-tiles with foret aurora fill.
	var league_tile := _summary_stat_tile()
	stats.add_child(league_tile)
	var league_body := league_tile.get_meta("body") as VBoxContainer

	var league_title := Label.new()
	league_title.text = tr(str(ranking.get("league_key", "UI_LEAGUE_BRONZE"))).to_upper()
	league_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	league_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	league_title.add_theme_font_size_override("font_size", UiScale.font(15))
	league_title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	league_body.add_child(league_title)

	var points_row := HBoxContainer.new()
	points_row.add_theme_constant_override("separation", 4)
	points_row.alignment = BoxContainer.ALIGNMENT_CENTER
	points_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	league_body.add_child(points_row)

	var trophy := Label.new()
	trophy.text = "🏆"
	trophy.add_theme_font_size_override("font_size", UiScale.font(20))
	if emoji_font != null:
		trophy.add_theme_font_override("font", emoji_font)
	points_row.add_child(trophy)

	var points := Label.new()
	points.text = _format_int(int(ranking.get("points", 0)))
	points.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points.add_theme_font_size_override("font_size", UiScale.font(22))
	points.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	points_row.add_child(points)

	var streak_tile := _summary_stat_tile()
	stats.add_child(streak_tile)
	var streak_body := streak_tile.get_meta("body") as VBoxContainer

	var streak_value := Label.new()
	## Consecutive days played: the habit the home screen should push.
	streak_value.text = str(snapshot.get("day_streak", 0))
	streak_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_value.add_theme_font_size_override("font_size", UiScale.font(24))
	streak_value.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	streak_body.add_child(streak_value)

	var streak_caption := Label.new()
	## Streak alive but nothing played yet today: nudge before it breaks at midnight.
	var at_risk := not bool(snapshot.get("is_demo", false)) and DayStreak.at_risk()
	streak_caption.text = tr("UI_HOME_DAY_STREAK_RISK" if at_risk else "UI_HOME_DAY_STREAK")
	streak_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	streak_caption.add_theme_font_size_override("font_size", UiScale.font(13))
	streak_caption.add_theme_color_override(
		"font_color",
		Color(1.0, 0.72, 0.42, 1) if at_risk else Color(1, 1, 1, 0.72)
	)
	streak_body.add_child(streak_caption)

	return panel


## Défis du jour card fill — reused by hero league / streak subtiles.
const _DAILY_CHALLENGES_BG := Color(0.075, 0.255, 0.245, 1)


func _summary_stat_tile() -> PanelContainer:
	## League / streak chips — foret aurora fill.
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tile.custom_minimum_size = Vector2(124, 112)
	var empty := StyleBoxEmpty.new()
	tile.add_theme_stylebox_override("panel", empty)

	var bg := AuroreTile.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.aurore_theme = "foret"
	tile.add_child(bg)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	tile.add_child(pad)

	var body := VBoxContainer.new()
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_theme_constant_override("separation", 6)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(body)
	tile.set_meta("body", body)
	return tile


func _make_daily_challenges_card() -> PanelContainer:
	## Featured home block — stronger wash so daily quests read as the day’s call to action.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := UiStyle.home_surface(true, 0)
	style.bg_color = _DAILY_CHALLENGES_BG
	style.set_border_width_all(2)
	style.border_color = Color(UiTokens.ACCENT_HOME.r, UiTokens.ACCENT_HOME.g, UiTokens.ACCENT_HOME.b, 0.55)
	panel.add_theme_stylebox_override("panel", style)

	var margin := _pad(14, 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var fire := Label.new()
	fire.text = "🔥"
	fire.add_theme_font_size_override("font_size", UiScale.font(24))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		fire.add_theme_font_override("font", emoji_font)
	header.add_child(fire)

	var title := Label.new()
	title.text = tr("UI_HOME_DAILY_CHALLENGES").to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UiScale.font(20))
	title.add_theme_color_override("font_color", Color(1, 1, 1, 0.98))
	header.add_child(title)

	var seconds := DailyQuests.seconds_until_reset()
	var reset := Label.new()
	reset.text = tr("UI_DAILY_RESET_IN").format({
		"time": "%dh%02d" % [int(seconds / 3600.0), int((seconds % 3600) / 60.0)],
	})
	reset.add_theme_font_size_override("font_size", UiScale.font(15))
	reset.add_theme_color_override("font_color", UiTokens.ACCENT_HOME)
	header.add_child(reset)

	var quests: Array = DailyQuests.get_quests(LocaleManager.get_content_locale())
	var quest_keys: Array = []
	for row in quests:
		quest_keys.append(str(row.get("id", quest_keys.size())))
	var quest_themes := _assign_daily_aurore_themes(quest_keys)
	for row in quests:
		var key := str(row.get("id", ""))
		vbox.add_child(_make_aurore_content_tile(
			_make_daily_challenge_row(row),
			str(quest_themes.get(key, "violet")),
			true
		))

	return panel


## Soft but clearly distinct pastels for home inset rows (autres blocs).
const _HOME_SUBTILE_WASH := [
	Color(0.42, 0.82, 0.78, 1), ## teal
	Color(0.98, 0.72, 0.38, 1), ## amber
	Color(0.62, 0.58, 0.95, 1), ## violet
]

const _AURORE_THEMES := [
	"violet", "sunset", "ocean", "foret", "fruits", "or", "indigo", "menthe",
	"lavande", "lagon", "crepuscule", "bonbon", "citron", "minuit", "sakura", "lave",
]


func _assign_daily_aurore_themes(keys: Array) -> Dictionary:
	## One theme per key for the local day (duplicates allowed).
	var out := {}
	for key_variant in keys:
		var key := str(key_variant)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("%s|%s" % [DailyQuests.today_key(), key])
		out[key] = _AURORE_THEMES[rng.randi_range(0, _AURORE_THEMES.size() - 1)]
	return out


func _make_home_subtile(
	content: Control,
	slot: int = 0,
	accent_override: Color = Color(0, 0, 0, 0),
	softness: float = 0.72
) -> PanelContainer:
	var wash: Color
	if accent_override.a > 0.02:
		## Achievement / result tint: very light pastel of the accent.
		wash = accent_override
	else:
		wash = _HOME_SUBTILE_WASH[slot % _HOME_SUBTILE_WASH.size()]
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = wash.lerp(Color(0.97, 0.98, 0.99, 1.0), softness)
	style.set_corner_radius_all(14)
	style.set_border_width_all(1)
	style.border_color = Color(wash.r, wash.g, wash.b, 0.28 if softness > 0.8 else 0.40)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	tile.add_theme_stylebox_override("panel", style)
	tile.add_child(content)
	return tile


func _make_aurore_content_tile(
	content: Control,
	aurore_theme: String = "violet",
	compact: bool = false
) -> Control:
	## Transparent panel + AuroreTile fill behind the row content.
	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var empty := StyleBoxEmpty.new()
	tile.add_theme_stylebox_override("panel", empty)

	var bg := AuroreTile.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.aurore_theme = aurore_theme
	tile.add_child(bg)

	var pad_h := 10 if compact else 12
	var pad_v := 6 if compact else 10
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", pad_h)
	pad.add_theme_constant_override("margin_right", pad_h)
	pad.add_theme_constant_override("margin_top", pad_v)
	pad.add_theme_constant_override("margin_bottom", pad_v)
	tile.add_child(pad)
	pad.add_child(content)
	return tile


func _make_near_achievements_card(snapshot: Dictionary) -> PanelContainer:
	## Same layout as daily challenges — locked badges closest to unlock.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.home_surface(true, 0))

	var margin := _pad(14, 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var title := Label.new()
	title.text = tr("UI_HOME_NEAR_ACHIEVEMENTS").to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UiScale.font(20))
	title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(title)

	var near := _near_achievements(snapshot, 3)
	if near.is_empty():
		vbox.add_child(_empty_line(tr("UI_HOME_NEAR_ACHIEVEMENTS_EMPTY")))
	else:
		var keys: Array = []
		for row in near:
			keys.append(str(row.get("id", keys.size())))
		var themes := _assign_daily_aurore_themes(keys)
		for row in near:
			var key := str(row.get("id", ""))
			vbox.add_child(_make_aurore_content_tile(
				_make_near_achievement_row(row),
				str(themes.get(key, "violet"))
			))

	return panel


func _near_achievements(snapshot: Dictionary, limit: int) -> Array:
	## Demo profile unlocks almost everything — use a fixed “almost there” set.
	if bool(snapshot.get("is_demo", false)):
		return _demo_near_achievements().slice(0, limit)

	var in_progress: Array = []
	var starters: Array = []
	for row in snapshot.get("achievements", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if bool(row.get("unlocked", false)):
			continue
		var current := int(row.get("current", 0))
		var target := maxi(int(row.get("target", 1)), 1)
		if current >= target:
			continue
		## Binary badges (0/1) with no progress aren't "proche".
		if current <= 0 and target <= 1:
			continue
		if current > 0:
			in_progress.append(row)
		else:
			starters.append(row)

	var by_closest := func(a: Dictionary, b: Dictionary) -> bool:
		var pa := float(a.get("progress", 0.0))
		var pb := float(b.get("progress", 0.0))
		if not is_equal_approx(pa, pb):
			return pa > pb
		return (int(a.get("target", 1)) - int(a.get("current", 0))) < (
			int(b.get("target", 1)) - int(b.get("current", 0))
		)
	in_progress.sort_custom(by_closest)
	starters.sort_custom(by_closest)

	var out: Array = []
	for row in in_progress:
		if out.size() >= limit:
			break
		out.append(row)
	for row in starters:
		if out.size() >= limit:
			break
		out.append(row)
	return out


func _demo_near_achievements() -> Array:
	return [
		{
			"id": "ten_matches",
			"title_key": "UI_ACH_TEN_MATCHES",
			"desc_key": "UI_ACH_TEN_MATCHES_DESC",
			"icon": "📚",
			"accent": Color(0.42, 0.361, 1.0, 1),
			"current": 8,
			"target": 10,
			"progress": 0.8,
		},
		{
			"id": "level_5",
			"title_key": "UI_ACH_LEVEL_5",
			"desc_key": "UI_ACH_LEVEL_5_DESC",
			"icon": "🛡️",
			"accent": Color(0.071, 0.769, 0.722, 1),
			"current": 4,
			"target": 5,
			"progress": 0.8,
		},
		{
			"id": "streak_10",
			"title_key": "UI_ACH_STREAK_10",
			"desc_key": "UI_ACH_STREAK_10_DESC",
			"icon": "10",
			"accent": Color(0.55, 0.32, 1.0, 1),
			"current": 7,
			"target": 10,
			"progress": 0.7,
		},
	]


func _make_near_achievement_row(data: Dictionary) -> Control:
	var accent: Color = data.get("accent", UiTokens.ACCENT_HOME)
	if typeof(accent) != TYPE_COLOR:
		accent = UiTokens.ACCENT_HOME

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(48, 48)
	icon_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_slot)

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(accent.r, accent.g, accent.b, 0.28)
	bg_style.set_corner_radius_all(24)
	bg.add_theme_stylebox_override("panel", bg_style)
	icon_slot.add_child(bg)

	var icon_text := str(data.get("icon", "?"))
	var icon_font_size := 18 if icon_text.is_valid_int() else 20
	var icon_display := GameAssets.make_circular_icon_display(
		GameAssets.badge_texture(str(data.get("id", ""))),
		icon_text,
		48.0,
		icon_font_size,
		GameAssets.ROUND_ICON_INSET
	)
	icon_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_slot.add_child(icon_display)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	row.add_child(mid)

	var title := Label.new()
	title.text = tr(str(data.get("title_key", "")))
	title.clip_text = true
	title.add_theme_font_size_override("font_size", UiScale.font(18))
	title.add_theme_color_override("font_color", Color.WHITE)
	mid.add_child(title)

	var desc := Label.new()
	desc.text = tr(str(data.get("desc_key", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", UiScale.font(16))
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	mid.add_child(desc)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 8)
	progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(progress_row)

	var current := int(data.get("current", 0))
	var target := maxi(int(data.get("target", 1)), 1)

	var ratio_label := Label.new()
	ratio_label.text = tr("UI_HOME_DAILY_PROGRESS").format({
		"current": current,
		"target": target,
	})
	ratio_label.add_theme_font_size_override("font_size", UiScale.font(15))
	ratio_label.add_theme_color_override("font_color", Color.WHITE)
	progress_row.add_child(ratio_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 8)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 1.0
	bar.value = clampf(float(current) / float(target), 0.0, 1.0)
	bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.18)
	bar_bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bar_bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 1, 1, 0.92)
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	progress_row.add_child(bar)

	var remaining_row := HBoxContainer.new()
	remaining_row.add_theme_constant_override("separation", 4)
	remaining_row.size_flags_horizontal = Control.SIZE_SHRINK_END
	progress_row.add_child(remaining_row)

	var lock := Label.new()
	lock.text = "🔒"
	lock.add_theme_font_size_override("font_size", UiScale.font(15))
	var lock_font := UiFonts.emoji_font()
	if lock_font != null:
		lock.add_theme_font_override("font", lock_font)
	remaining_row.add_child(lock)

	var remaining := Label.new()
	remaining.text = tr("UI_HOME_NEAR_REMAINING").format({"n": maxi(target - current, 0)})
	remaining.add_theme_font_size_override("font_size", UiScale.font(15))
	remaining.add_theme_color_override("font_color", Color.WHITE)
	remaining_row.add_child(remaining)

	return row


func _empty_line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiScale.font(16))
	label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	return label


func _make_daily_challenge_row(data: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	row.add_child(_make_challenge_icon(str(data.get("icon", "★")), data.get("accent", UiTokens.ACCENT_HOME), 40.0))

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)

	var title := Label.new()
	title.text = str(data.get("title", ""))
	title.clip_text = true
	title.add_theme_font_size_override("font_size", UiScale.font(17))
	title.add_theme_color_override("font_color", Color.WHITE)
	mid.add_child(title)

	var desc := Label.new()
	desc.text = str(data.get("desc", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", UiScale.font(13))
	desc.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	mid.add_child(desc)

	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 6)
	progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_child(progress_row)

	var current := int(data.get("current", 0))
	var target := maxi(int(data.get("target", 1)), 1)

	var ratio_label := Label.new()
	ratio_label.text = tr("UI_HOME_DAILY_PROGRESS").format({
		"current": current,
		"target": target,
	})
	ratio_label.add_theme_font_size_override("font_size", UiScale.font(13))
	ratio_label.add_theme_color_override("font_color", Color.WHITE)
	progress_row.add_child(ratio_label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 7)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 1.0
	bar.value = clampf(float(current) / float(target), 0.0, 1.0)
	bar.show_percentage = false
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(1, 1, 1, 0.18)
	bar_bg.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", bar_bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1, 1, 1, 0.92)
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("fill", fill)
	progress_row.add_child(bar)

	var claimed := bool(data.get("claimed", false))
	if bool(data.get("completed", false)) and not claimed:
		progress_row.add_child(_make_claim_button(str(data.get("id", "")), int(data.get("xp", 0))))
	elif claimed:
		var done := Label.new()
		done.text = "✓"
		done.add_theme_font_size_override("font_size", UiScale.font(18))
		done.add_theme_color_override("font_color", Color(0.45, 1.0, 0.62, 1))
		progress_row.add_child(done)
	else:
		progress_row.add_child(_make_xp_badge(int(data.get("xp", 0))))

	return row


func _make_xp_badge(xp_amount: int) -> Control:
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 4)
	xp_row.size_flags_horizontal = Control.SIZE_SHRINK_END

	var star := Label.new()
	star.text = "⭐"
	star.add_theme_font_size_override("font_size", UiScale.font(15))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		star.add_theme_font_override("font", emoji_font)
	xp_row.add_child(star)

	var xp := Label.new()
	xp.text = tr("UI_HOME_DAILY_CHALLENGE_XP").format({"xp": xp_amount})
	xp.add_theme_font_size_override("font_size", UiScale.font(15))
	xp.add_theme_color_override("font_color", Color.WHITE)
	xp_row.add_child(xp)
	return xp_row


## Gold button shown once a quest is complete; tapping it pays the XP out.
func _make_claim_button(quest_id: String, xp_amount: int) -> Button:
	var button := Button.new()
	button.text = "%s +%d" % [tr("UI_DAILY_CLAIM"), xp_amount]
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", UiScale.font(15))
	button.add_theme_color_override("font_color", UiTokens.INK)
	button.add_theme_color_override("font_hover_color", UiTokens.INK)
	button.add_theme_color_override("font_pressed_color", UiTokens.INK)
	var style := UiStyle.filled(UiTokens.ACCENT_LEADERBOARD, 17)
	style.content_margin_left = 14
	style.content_margin_right = 14
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, style)
	PressScaleUtil.wire(button, self)
	button.pressed.connect(_on_claim_pressed.bind(quest_id, button))
	return button


func _on_claim_pressed(quest_id: String, button: Button) -> void:
	var granted := DailyQuests.claim(quest_id, LocaleManager.get_content_locale())
	if granted <= 0:
		return
	AudioManager.play("achievement")
	button.disabled = true
	button.text = tr("UI_RESULTS_XP_GAINED").format({"xp": granted})
	button.pivot_offset = button.size * 0.5
	var pop := create_tween()
	pop.tween_property(button, "scale", Vector2(1.25, 1.25), 0.12)
	pop.tween_property(button, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_interval(0.5)
	pop.tween_callback(_rebuild)


func _make_challenge_icon(icon_text: String, accent: Color, size_px: float = 48.0) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size_px, size_px)
	slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.92)
	style.set_corner_radius_all(int(size_px * 0.5))
	bg.add_theme_stylebox_override("panel", style)
	slot.add_child(bg)

	var icon := Label.new()
	icon.text = icon_text
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_theme_font_size_override("font_size", UiScale.font(18 if size_px < 48.0 else 22))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	slot.add_child(icon)
	return slot


func _make_last_match_card(snapshot: Dictionary) -> PanelContainer:
	## Profile “last games” tile, hosted on home (accent · avatar · result · time).
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = UiTokens.DASH_HISTORY_HEIGHT
	panel.add_theme_stylebox_override("panel", UiStyle.home_surface(true, 0))

	var margin := _pad(14, 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(header)

	var title := Label.new()
	title.text = tr("UI_PROFILE_HISTORY_TITLE").to_upper()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", UiScale.font(20))
	title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	header.add_child(title)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(list)

	var history: Array = snapshot.get("history", [])
	if history.is_empty():
		var empty := Label.new()
		empty.text = tr("UI_PROFILE_NO_HISTORY")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", UiScale.font(14))
		empty.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
		list.add_child(empty)
	else:
		var count := 0
		for row in history:
			if count >= 4:
				break
			if typeof(row) != TYPE_DICTIONARY:
				continue
			list.add_child(_history_row(row))
			count += 1

	return panel


func _history_divider() -> Control:
	## 2px — 1px rules vanish under swipe/scroll subpixel sampling.
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 2)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.color = Color(1, 1, 1, 0.14)
	return line


func _history_mode_meta(mode: String) -> Dictionary:
	match mode:
		"survival":
			return {
				"key": "UI_MODE_SURVIVAL",
				"icon": "❤️",
				"accent": UiTokens.ACCENT_MODE_SURVIVAL,
			}
		"time_attack":
			return {
				"key": "UI_MODE_TIME_ATTACK",
				"icon": "⏱️",
				"accent": UiTokens.ACCENT_MODE_TIME_ATTACK,
			}
		_:
			return {
				"key": "UI_MODE_CLASSIC",
				"icon": "🎯",
				"accent": UiTokens.ACCENT_MODE_CLASSIC,
			}


func _history_mode_badge(mode: String) -> Control:
	## Compact mode chip under the opponent name (same look as social challenge tiles).
	var meta := _history_mode_meta(mode)
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = meta["accent"]
	style.set_border_width_all(0)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	badge.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(row)

	var icon := Label.new()
	icon.text = str(meta["icon"])
	icon.add_theme_font_size_override("font_size", UiScale.font(14))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon.add_theme_font_override("font", emoji_font)
	row.add_child(icon)

	var label := Label.new()
	label.text = tr(str(meta["key"])).to_upper()
	label.add_theme_font_size_override("font_size", UiScale.font(13))
	label.add_theme_color_override("font_color", Color(0.10, 0.08, 0.12, 1))
	row.add_child(label)
	return badge


func _history_row(row: Dictionary) -> Control:
	## Opponent banner behind the row — same pattern as social request tiles.
	var won: bool = row.get("won", false)
	var win_color := Color(0.20, 0.86, 0.48, 1)
	var loss_color := Color(0.96, 0.26, 0.32, 1)
	var result_color := win_color if won else loss_color

	var opponent_name := str(row.get("opponent", "?"))
	var cosmetics: Dictionary = row.get("cosmetics", {})
	if cosmetics.is_empty():
		cosmetics = ShopCatalog.demo_cosmetics_for(opponent_name)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(14)
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", style)

	var banner := CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2.ZERO, 14)
	panel.add_child(banner)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_top", 8)
	pad.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(pad)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(hbox)

	const AVATAR_SIDE := 58.0

	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(3, AVATAR_SIDE)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = result_color
	bar_style.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("panel", bar_style)
	hbox.add_child(bar)

	var avatar := CosmeticsView.avatar(cosmetics, AVATAR_SIDE)
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(avatar)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", 2)
	hbox.add_child(left)

	var name_label := Label.new()
	name_label.text = opponent_name
	name_label.clip_text = true
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(opponent_name))
	)
	name_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	left.add_child(name_label)

	left.add_child(_history_mode_badge(str(row.get("mode", "classic"))))

	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 10)
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.custom_minimum_size = Vector2(188, 0)
	hbox.add_child(mid)

	var result := Label.new()
	result.text = (tr("UI_PROFILE_WIN") if won else tr("UI_PROFILE_LOSS")).to_upper()
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", UiScale.font(19))
	result.add_theme_color_override("font_color", result_color)
	result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	result.add_theme_constant_override("outline_size", 4)
	mid.add_child(result)

	var mine := int(row.get("my_score", row.get("correct_count", 0)))
	var theirs := int(row.get("opponent_score", maxi(int(row.get("total_count", 0)) - mine, 0)))
	var score := Label.new()
	score.text = tr("UI_PROFILE_MATCH_SCORE").format({"mine": mine, "theirs": theirs})
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score.custom_minimum_size.x = 60
	score.add_theme_font_size_override("font_size", UiScale.font(19))
	score.add_theme_color_override("font_color", result_color)
	score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	score.add_theme_constant_override("outline_size", 4)
	mid.add_child(score)

	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.custom_minimum_size.x = 118
	right.alignment = BoxContainer.ALIGNMENT_END
	hbox.add_child(right)

	var age := Label.new()
	age.text = _format_age_minutes(int(row.get("age_minutes", int(row.get("age_hours", 0)) * 60)))
	age.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	age.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	age.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	age.add_theme_font_size_override("font_size", UiScale.font(15))
	age.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	age.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	age.add_theme_constant_override("outline_size", 4)
	right.add_child(age)
	return panel


func _pad(h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	return margin


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


func _format_age_minutes(minutes: int) -> String:
	if minutes <= 0:
		return tr("UI_PROFILE_TIME_NOW")
	if minutes < 60:
		return tr("UI_PROFILE_TIME_MINUTES").format({"minutes": minutes})
	if minutes < 24 * 60:
		return tr("UI_PROFILE_TIME_HOURS").format({"hours": int(minutes / 60.0)})
	return tr("UI_PROFILE_TIME_DAYS").format({"days": int(minutes / (24.0 * 60.0))})


func _on_locale_changed(_locale: String) -> void:
	_rebuild()
