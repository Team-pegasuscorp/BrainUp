## Home tab — hub du jour (pas de bouton Play : le FAB Quiz reste l'action principale).
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const ProfileSnapshot = preload("res://scripts/profile/profile_snapshot.gd")

@onready var subtitle_label: Label = %SubtitleLabel
@onready var content: VBoxContainer = %Content


func _ready() -> void:
	_rebuild()
	LocaleManager.locale_changed.connect(_on_locale_changed)


func on_tab_shown() -> void:
	_rebuild()


func _rebuild() -> void:
	var snapshot: Dictionary = ProfileSnapshot.build_full(LocaleManager.get_content_locale())
	_apply_hello(snapshot)
	_rebuild_cards(snapshot)


func _apply_hello(snapshot: Dictionary) -> void:
	var name: String = str(snapshot.get("player_name", UiTokens.DEFAULT_PLAYER_NAME))
	subtitle_label.text = tr("UI_HOME_HELLO").format({"name": name})
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	subtitle_label.add_theme_color_override("font_color", UiTokens.INK)


func _rebuild_cards(snapshot: Dictionary) -> void:
	for child in content.get_children():
		child.queue_free()

	content.add_child(_make_progress_compact(snapshot))
	content.add_child(_make_today_card(snapshot))
	content.add_child(_make_rank_streak_row(snapshot))
	content.add_child(_make_last_match_card(snapshot))


func _make_progress_compact(snapshot: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.profile_surface(UiTokens.ACCENT_XP, false, 0))

	var margin := _pad(12, 10)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var level := Label.new()
	level.text = tr("UI_PLAYER_LEVEL").format({"level": snapshot.get("level", 1)})
	level.add_theme_font_size_override("font_size", 18)
	level.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(level)

	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 10
	bar.max_value = 1.0
	bar.value = float(snapshot.get("xp_progress", 0.0))
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
	bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(UiTokens.ACCENT_XP))
	vbox.add_child(bar)

	var xp := Label.new()
	xp.text = tr("UI_PROFILE_XP_PROGRESS").format({
		"current": snapshot.get("xp", 0),
		"target": snapshot.get("xp_to_next", 100),
	})
	xp.add_theme_font_size_override("font_size", 12)
	xp.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	vbox.add_child(xp)
	return panel


func _make_today_card(snapshot: Dictionary) -> PanelContainer:
	## Priority: resume last category → suggest weakest category → FAB hint.
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.profile_surface(UiTokens.ACCENT_HOME, false, 0))

	var margin := _pad(14, 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	var eyebrow := Label.new()
	eyebrow.text = tr("UI_HOME_TODAY").to_upper()
	eyebrow.add_theme_font_size_override("font_size", 11)
	eyebrow.add_theme_color_override("font_color", UiTokens.ACCENT_HOME)
	vbox.add_child(eyebrow)

	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(title)

	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	vbox.add_child(detail)

	var history: Array = snapshot.get("history", [])
	if not history.is_empty() and typeof(history[0]) == TYPE_DICTIONARY:
		var last: Dictionary = history[0]
		var category_name := str(last.get("category_name", ""))
		title.text = tr("UI_HOME_RESUME_TITLE").format({"category": category_name})
		detail.text = tr("UI_HOME_RESUME_DETAIL").format({
			"score": last.get("score", 0),
			"result": tr("UI_PROFILE_WIN") if last.get("won", false) else tr("UI_PROFILE_LOSS"),
		})
	else:
		var weak := _weakest_category(snapshot)
		if not weak.is_empty():
			title.text = tr("UI_HOME_SUGGEST_TITLE").format({"category": weak.get("name", "")})
			detail.text = tr("UI_HOME_SUGGEST_DETAIL").format({
				"percent": "%.0f" % weak.get("accuracy_percent", 0.0),
			})
		else:
			title.text = tr("UI_HOME_START_TITLE")
			detail.text = tr("UI_HOME_QUIZ_HINT")

	return panel


func _make_rank_streak_row(snapshot: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var ranking: Dictionary = snapshot.get("ranking", {})
	row.add_child(_make_metric_chip(
		tr("UI_HOME_RANK"),
		"#%s" % _format_int(int(ranking.get("rank", 0))),
		UiTokens.ACCENT_LEADERBOARD
	))
	row.add_child(_make_metric_chip(
		tr("UI_PROFILE_WIN_STREAK"),
		str(snapshot.get("current_win_streak", 0)),
		UiTokens.ACCENT_HOME
	))
	return row


func _make_metric_chip(caption: String, value: String, accent: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 84
	panel.add_theme_stylebox_override("panel", UiStyle.profile_surface(accent, false, 0))

	var margin := _pad(10, 10)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", accent)
	vbox.add_child(value_label)

	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_label.add_theme_font_size_override("font_size", 12)
	caption_label.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT_MUTED)
	vbox.add_child(caption_label)
	return panel


func _make_last_match_card(snapshot: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiStyle.profile_surface(UiTokens.ACCENT_QUIZ, false, 0))

	var margin := _pad(14, 12)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = tr("UI_HOME_LAST_MATCH").to_upper()
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", UiTokens.ACCENT_QUIZ)
	vbox.add_child(title)

	var line := Label.new()
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", 15)
	line.add_theme_color_override("font_color", UiTokens.PROFILE_TEXT)
	vbox.add_child(line)

	var history: Array = snapshot.get("history", [])
	if history.is_empty() or typeof(history[0]) != TYPE_DICTIONARY:
		line.text = tr("UI_HOME_NO_LAST_MATCH")
	else:
		var last: Dictionary = history[0]
		line.text = tr("UI_HOME_LAST_MATCH_LINE").format({
			"category": last.get("category_name", ""),
			"score": last.get("score", 0),
			"result": tr("UI_PROFILE_WIN") if last.get("won", false) else tr("UI_PROFILE_LOSS"),
			"time": _format_age(int(last.get("age_hours", 0))),
		})
	return panel


func _weakest_category(snapshot: Dictionary) -> Dictionary:
	var weakest: Dictionary = {}
	var weakest_accuracy := 101.0
	for row in snapshot.get("categories", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("games_played", 0)) <= 0 and not snapshot.get("is_demo", false):
			continue
		var accuracy := float(row.get("accuracy_percent", 100.0))
		if accuracy < weakest_accuracy:
			weakest_accuracy = accuracy
			weakest = row
	return weakest


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


func _format_age(hours: int) -> String:
	if hours <= 0:
		return tr("UI_PROFILE_TIME_NOW")
	if hours < 24:
		return tr("UI_PROFILE_TIME_HOURS").format({"hours": hours})
	return tr("UI_PROFILE_TIME_DAYS").format({"days": int(hours / 24.0)})


func _on_locale_changed(_locale: String) -> void:
	_rebuild()
