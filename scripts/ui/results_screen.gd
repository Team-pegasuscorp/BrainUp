extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const AchievementsCatalog = preload("res://scripts/profile/achievements_catalog.gd")

@onready var score_caption_label: Label = %ScoreCaption
@onready var correct_caption_label: Label = %CorrectCaption
@onready var combo_caption_label: Label = %ComboCaption
@onready var average_caption_label: Label = %AverageCaption
@onready var title_label: Label = %TitleLabel
@onready var score_value_label: Label = %ScoreValueLabel
@onready var correct_value_label: Label = %CorrectValueLabel
@onready var combo_value_label: Label = %ComboValueLabel
@onready var average_value_label: Label = %AverageValueLabel
@onready var play_again_button: Button = %PlayAgainButton
@onready var menu_button: Button = %MenuButton
@onready var stats_panel: PanelContainer = %StatsPanel
@onready var vbox: VBoxContainer = $MarginContainer/VBox
@onready var stats_grid: GridContainer = $MarginContainer/VBox/StatsPanel/StatsMargin/StatsGrid

const CONFETTI_COLORS: Array[Color] = [
	Color(0.36, 0.75, 1.0), Color(0.941, 0.706, 0.161), Color(0.95, 0.30, 0.55),
	Color(0.55, 0.32, 1.0), Color(0.18, 0.78, 0.52),
]
const STAT_STAGGER := 0.12
const XP_FILL_SECONDS := 0.9

var summary: Dictionary = {}
var _subtitle_label: Label
var _level_label: Label
var _xp_gain_label: Label
var _xp_detail_label: Label
var _xp_bar: ProgressBar
var _xp_card: PanelContainer
var _achievements_card: PanelContainer
var _streak_label: Label
var _daily_rank_label: Label
var _flash: ColorRect
var _intro: Tween
var _intro_done: bool = false
var _skipping: bool = false


func _ready() -> void:
	summary = GameManager.last_summary
	stats_panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_QUIZ))
	title_label.add_theme_color_override("font_color", UiTokens.INK)
	correct_value_label.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT)
	combo_value_label.add_theme_color_override("font_color", UiTokens.ACCENT_QUIZ)
	average_value_label.add_theme_color_override("font_color", UiTokens.INK)
	_enlarge_layout()
	_build_outcome_sections()
	_apply_translations()
	_play_intro()
	play_again_button.pressed.connect(_on_play_again_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	LocaleManager.locale_changed.connect(_on_locale_changed)
	PressScaleUtil.wire(play_again_button, self)
	PressScaleUtil.wire(menu_button, self)


func _apply_translations() -> void:
	title_label.text = tr("UI_RESULTS")
	score_caption_label.text = tr("UI_FINAL_SCORE")
	correct_caption_label.text = tr("UI_CORRECT_COUNT")
	combo_caption_label.text = tr("UI_BEST_COMBO")
	average_caption_label.text = tr("UI_AVG_TIME")
	_apply_outcome_texts()
	correct_value_label.text = "%d / %d" % [
		summary.get("correct_count", 0),
		summary.get("total_count", 0),
	]
	combo_value_label.text = "x%d" % summary.get("max_combo", 0)
	average_value_label.text = tr("UI_SECONDS").format({
		"value": "%.1f" % summary.get("average_time", 0.0),
	})
	play_again_button.text = tr("UI_PLAY_AGAIN")
	menu_button.text = tr("UI_MAIN_MENU")


func _on_play_again_pressed() -> void:
	GameManager.start_round(summary.get("category_id", ""))
	if GameManager.has_questions():
		get_tree().change_scene_to_file(ScenePaths.QUIZ_GAME)
	else:
		ScenePaths.go_to_shell(get_tree(), ScenePaths.Tab.QUIZ)


func _on_menu_pressed() -> void:
	ScenePaths.go_to_shell(get_tree(), ScenePaths.Tab.HOME)


func _on_locale_changed(_locale: String) -> void:
	_apply_translations()


## All results sounds go through here so a fast-forward stays silent.
func _sfx(sound: String, pitch: float = 1.0) -> void:
	if not _skipping:
		AudioManager.play(sound, pitch)


## Rank arrives from the server; it may land after the screen is already up.
func _show_daily_rank(data: Dictionary) -> void:
	if _daily_rank_label == null:
		return
	_daily_rank_label.text = "🏆 " + tr("UI_DAILY_RANK").format({"rank": int(data.get("rank", 0))})
	_daily_rank_label.visible = true
	_daily_rank_label.pivot_offset = _daily_rank_label.size * 0.5
	var pop := create_tween()
	pop.tween_property(_daily_rank_label, "scale", Vector2(1.25, 1.25), 0.12)
	pop.tween_property(_daily_rank_label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _is_win() -> bool:
	return bool(summary.get("won", false))


func _outcome_color() -> Color:
	return UiTokens.FEEDBACK_CORRECT if _is_win() else UiTokens.FEEDBACK_WRONG


## Bigger type, values pushed to the right edge, roomier cards.
func _enlarge_layout() -> void:
	title_label.add_theme_font_size_override("font_size", 60)
	vbox.add_theme_constant_override("separation", 22)
	stats_grid.add_theme_constant_override("v_separation", 20)
	var kids := stats_grid.get_children()
	for index in kids.size():
		var label := kids[index] as Label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if index % 2 == 0:
			label.add_theme_font_size_override("font_size", 20)
		else:
			label.add_theme_font_size_override("font_size", 40 if index == 1 else 30)


## Subtitle, XP card and new-achievements card, inserted above the stats panel.
func _build_outcome_sections() -> void:
	title_label.add_theme_color_override("font_color", _outcome_color())
	_subtitle_label = Label.new()
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	_subtitle_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	_insert_before_stats(_subtitle_label)

	_streak_label = Label.new()
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_label.add_theme_font_size_override("font_size", 22)
	_streak_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.18))
	_streak_label.visible = _is_win() and SaveManager.current_win_streak >= 2
	_insert_before_stats(_streak_label)

	if bool(summary.get("is_daily", false)):
		_daily_rank_label = Label.new()
		_daily_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_daily_rank_label.add_theme_font_size_override("font_size", 22)
		_daily_rank_label.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
		_daily_rank_label.visible = false
		_insert_before_stats(_daily_rank_label)
		NetworkManager.daily_result_submitted.connect(_show_daily_rank)
		if not NetworkManager.last_daily_result.is_empty():
			_show_daily_rank(NetworkManager.last_daily_result)

	## Full-screen colour flash (green burst on win, red on defeat); never eats input.
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = _outcome_color()
	_flash.modulate.a = 0.0
	add_child(_flash)

	_xp_card = _build_xp_card()
	_insert_before_stats(_xp_card)

	var new_ids: Array = summary.get("new_achievements", [])
	if not new_ids.is_empty():
		_achievements_card = _build_achievements_card(new_ids)
		_insert_before_stats(_achievements_card)


func _insert_before_stats(node: Control) -> void:
	vbox.add_child(node)
	vbox.move_child(node, stats_panel.get_index())


func _build_xp_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_QUIZ))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	_level_label = Label.new()
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_level_label.add_theme_font_size_override("font_size", 26)
	_level_label.add_theme_color_override("font_color", UiTokens.INK)
	header.add_child(_level_label)
	_xp_gain_label = Label.new()
	_xp_gain_label.add_theme_font_size_override("font_size", 26)
	_xp_gain_label.add_theme_color_override("font_color", UiTokens.ACCENT_QUIZ_DEEP)
	header.add_child(_xp_gain_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.min_value = 0.0
	_xp_bar.max_value = 1.0
	_xp_bar.step = 0.001
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(0, 22)
	_xp_bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
	_xp_bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(UiTokens.ACCENT_QUIZ))
	column.add_child(_xp_bar)

	_xp_detail_label = Label.new()
	_xp_detail_label.add_theme_font_size_override("font_size", 18)
	_xp_detail_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	column.add_child(_xp_detail_label)
	return panel


func _build_achievements_card(achievement_ids: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_LEADERBOARD))
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.name = "AchievementsTitle"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	column.add_child(title)

	var by_id := {}
	for achievement in AchievementsCatalog.all():
		by_id[str(achievement.get("id", ""))] = achievement
	## Cap the list so the screen never scrolls; the profile lists everything.
	for achievement_id in achievement_ids.slice(0, 3):
		var achievement: Dictionary = by_id.get(str(achievement_id), {})
		if achievement.is_empty():
			continue
		column.add_child(_build_achievement_row(str(achievement_id), achievement))
	return panel


func _build_achievement_row(achievement_id: String, achievement: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_meta("title_key", str(achievement.get("title_key", "")))

	var icon_slot: Control
	var texture := GameAssets.badge_texture(achievement_id)
	if texture != null:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_slot = rect
	else:
		var glyph := Label.new()
		glyph.text = str(achievement.get("icon", "?"))
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		glyph.add_theme_font_size_override("font_size", 28)
		icon_slot = glyph
	icon_slot.custom_minimum_size = Vector2(44, 44)
	row.add_child(icon_slot)

	var label := Label.new()
	label.name = "Title"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", achievement.get("accent", UiTokens.INK))
	row.add_child(label)
	return row


func _apply_outcome_texts() -> void:
	var won := _is_win()
	title_label.text = tr("UI_RESULTS_VICTORY") if won else tr("UI_RESULTS_DEFEAT")
	_subtitle_label.text = tr("UI_RESULTS_VICTORY_SUB") if won else tr("UI_RESULTS_DEFEAT_SUB")
	if bool(summary.get("is_daily", false)):
		_subtitle_label.text = "%s · %s" % [tr("UI_DAILY_CHALLENGE_TITLE"), _subtitle_label.text]
	_streak_label.text = tr("UI_RESULTS_STREAK").format({"count": SaveManager.current_win_streak})
	_xp_gain_label.text = tr("UI_RESULTS_XP_GAINED").format({"xp": int(summary.get("xp_gained", 0))})

	var leveled_up := int(summary.get("level_after", 1)) > int(summary.get("level_before", 1))
	_level_label.text = tr("UI_RESULTS_LEVEL").format({"level": int(summary.get("level_before", 1))})
	_xp_detail_label.text = tr("UI_RESULTS_XP_PROGRESS").format({
		"current": int(summary.get("xp_before", 0)) if leveled_up else int(summary.get("xp_after", 0)),
		"needed": int(summary.get("xp_needed_before", 100)) if leveled_up else int(summary.get("xp_needed_after", 100)),
	})

	if _achievements_card != null:
		_achievements_card.find_child("AchievementsTitle", true, false).text = tr("UI_RESULTS_NEW_ACHIEVEMENTS").to_upper()
		for row in _achievements_card.find_children("Title", "Label", true, false):
			row.text = tr(str(row.get_parent().get_meta("title_key", "")))


## Whole intro is ONE tween with absolute delays, so a tap can fast-forward it
## with custom_step() and every value/callback still lands on its final state.
func _play_intro() -> void:
	var won := _is_win()
	var target_score := int(summary.get("score", 0))
	var ratio_before := _ratio(int(summary.get("xp_before", 0)), int(summary.get("xp_needed_before", 100)))
	var ratio_after := _ratio(int(summary.get("xp_after", 0)), int(summary.get("xp_needed_after", 100)))
	var leveled_up := int(summary.get("level_after", 1)) > int(summary.get("level_before", 1))

	title_label.modulate.a = 0.0
	_subtitle_label.modulate.a = 0.0
	_streak_label.modulate.a = 0.0
	_xp_card.modulate.a = 0.0
	_xp_bar.value = ratio_before
	var stat_rows := _stat_rows()
	for row in stat_rows:
		row["caption"].modulate.a = 0.0
		row["value"].modulate.a = 0.0
	if _achievements_card != null:
		_achievements_card.modulate.a = 0.0

	_intro = create_tween().set_parallel(true)

	# 0.00 — title slams in.
	_intro.tween_method(_set_title_scale, 2.4, 1.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_intro.tween_property(title_label, "modulate:a", 1.0, 0.2)
	_intro.tween_property(_flash, "modulate:a", 0.28, 0.08)
	_intro.tween_property(_flash, "modulate:a", 0.0, 0.5).set_delay(0.08)
	_intro.tween_callback(_sfx.bind("thud"))
	_intro.tween_callback(_sfx.bind("victory" if won else "defeat")).set_delay(0.2)
	if won:
		_intro.tween_callback(_spawn_confetti).set_delay(0.1)
	else:
		_intro.tween_method(_wobble_title, 0.0, 1.0, 0.5)
	_intro.tween_property(_subtitle_label, "modulate:a", 1.0, 0.3).set_delay(0.35)
	_intro.tween_property(_streak_label, "modulate:a", 1.0, 0.3).set_delay(0.6)

	# 0.55 — stat rows cascade in and count up.
	var t := 0.55
	for i in stat_rows.size():
		var row: Dictionary = stat_rows[i]
		var at := t + float(i) * STAT_STAGGER
		_intro.tween_property(row["caption"], "modulate:a", 1.0, 0.2).set_delay(at)
		_intro.tween_property(row["value"], "modulate:a", 1.0, 0.2).set_delay(at)
		_intro.tween_method(row["setter"], 0.0, float(row["target"]), 0.55).set_delay(at)
		_intro.tween_callback(_sfx.bind("tick_soft", 1.0 + float(i) * 0.12)).set_delay(at)
	var stats_end := t + float(stat_rows.size()) * STAT_STAGGER + 0.55
	_intro.tween_method(_punch_score, 0.0, 1.0, 0.3).set_delay(t + 0.55)

	# XP card follows, bar fills (rolling over on a level-up).
	var xp_at := stats_end - 0.2
	_intro.tween_property(_xp_card, "modulate:a", 1.0, 0.3).set_delay(xp_at)
	var fill_at := xp_at + 0.3
	_intro.tween_callback(_sfx.bind("xp_fill")).set_delay(fill_at)
	var end_at := fill_at
	if leveled_up:
		var first := XP_FILL_SECONDS * (1.0 - ratio_before) + 0.15
		_intro.tween_property(_xp_bar, "value", 1.0, first).set_delay(fill_at)
		_intro.tween_callback(_show_level_up).set_delay(fill_at + first)
		var second := XP_FILL_SECONDS * ratio_after + 0.15
		_intro.tween_property(_xp_bar, "value", ratio_after, second).set_delay(fill_at + first + 0.25)
		end_at = fill_at + first + 0.25 + second
	else:
		var span := XP_FILL_SECONDS * maxf(ratio_after - ratio_before, 0.2)
		_intro.tween_property(_xp_bar, "value", ratio_after, span).set_delay(fill_at)
		end_at = fill_at + span

	# New achievements pop in one after the other.
	if _achievements_card != null:
		_intro.tween_property(_achievements_card, "modulate:a", 1.0, 0.25).set_delay(end_at)
		var rows := _achievements_card.find_children("*", "HBoxContainer", true, false)
		for j in rows.size():
			var badge: Control = rows[j]
			badge.scale = Vector2.ZERO
			_intro.tween_callback(_sfx.bind("achievement", 1.0 + float(j) * 0.12)).set_delay(end_at + 0.15 + float(j) * 0.2)
			_intro.tween_method(_pop_control.bind(badge), 0.0, 1.0, 0.45).set_delay(end_at + 0.15 + float(j) * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		end_at += 0.15 + float(rows.size()) * 0.2 + 0.4

	_intro.tween_callback(_on_intro_finished).set_delay(end_at)


func _input(event: InputEvent) -> void:
	## Tap anywhere to fast-forward the reveal.
	if _intro_done or _intro == null or not _intro.is_valid():
		return
	var tapped: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		_skipping = true
		_intro.custom_step(60.0)
		_skipping = false
		AudioManager.stop_all()


func _on_intro_finished() -> void:
	_intro_done = true
	## Idle pulse on the primary button: invites the next round without fighting
	## PressScaleUtil, which owns the button's scale.
	var pulse := play_again_button.create_tween().set_loops()
	pulse.tween_property(play_again_button, "modulate", Color(1.14, 1.14, 1.14), 0.7).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(play_again_button, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)


func _stat_rows() -> Array:
	var kids := stats_grid.get_children()
	return [
		{"caption": kids[0], "value": kids[1], "target": int(summary.get("score", 0)),
			"setter": func(v: float) -> void: score_value_label.text = str(int(v))},
		{"caption": kids[2], "value": kids[3], "target": int(summary.get("correct_count", 0)),
			"setter": func(v: float) -> void:
				correct_value_label.text = "%d / %d" % [int(v), int(summary.get("total_count", 0))]},
		{"caption": kids[4], "value": kids[5], "target": int(summary.get("max_combo", 0)),
			"setter": func(v: float) -> void: combo_value_label.text = "x%d" % int(v)},
		{"caption": kids[6], "value": kids[7], "target": float(summary.get("average_time", 0.0)),
			"setter": func(v: float) -> void:
				average_value_label.text = tr("UI_SECONDS").format({"value": "%.1f" % v})},
	]


func _set_title_scale(value: float) -> void:
	title_label.pivot_offset = title_label.size * 0.5
	title_label.scale = Vector2(value, value)


func _wobble_title(progress: float) -> void:
	title_label.pivot_offset = title_label.size * 0.5
	title_label.rotation = sin(progress * TAU * 3.0) * 0.06 * (1.0 - progress)


func _punch_score(progress: float) -> void:
	score_value_label.pivot_offset = score_value_label.size * 0.5
	var bump := 1.0 + sin(progress * PI) * 0.35
	score_value_label.scale = Vector2(bump, bump)


func _pop_control(progress: float, control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	control.scale = Vector2(progress, progress)


func _show_level_up() -> void:
	_sfx("level_up")
	_xp_bar.value = 0.0
	_level_label.text = tr("UI_RESULTS_LEVEL_UP").format({"level": int(summary.get("level_after", 1))})
	_level_label.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
	_xp_detail_label.text = tr("UI_RESULTS_XP_PROGRESS").format({
		"current": int(summary.get("xp_after", 0)),
		"needed": int(summary.get("xp_needed_after", 100)),
	})
	_pop_label(_level_label)
	_spawn_burst(_level_label.global_position + _level_label.size * 0.5, Color(0.941, 0.706, 0.161))
	_flash.color = UiTokens.ACCENT_LEADERBOARD
	create_tween().tween_property(_flash, "modulate:a", 0.22, 0.08)
	create_tween().tween_property(_flash, "modulate:a", 0.0, 0.45).set_delay(0.08)


func _pop_label(label: Label) -> void:
	label.pivot_offset = label.size * 0.5
	var pop := create_tween()
	pop.tween_property(label, "scale", Vector2(1.18, 1.18), 0.12)
	pop.tween_property(label, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Rain of coloured paper from the top edge; one shot, frees itself.
func _spawn_confetti() -> void:
	var width := get_viewport_rect().size.x
	var confetti := CPUParticles2D.new()
	confetti.position = Vector2(width * 0.5, -20.0)
	confetti.amount = 90
	confetti.lifetime = 3.2
	confetti.one_shot = true
	confetti.explosiveness = 0.35
	confetti.randomness = 1.0
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(width * 0.5, 6.0)
	confetti.direction = Vector2.DOWN
	confetti.spread = 30.0
	confetti.gravity = Vector2(0.0, 520.0)
	confetti.initial_velocity_min = 180.0
	confetti.initial_velocity_max = 420.0
	confetti.angular_velocity_min = -540.0
	confetti.angular_velocity_max = 540.0
	confetti.scale_amount_min = 6.0
	confetti.scale_amount_max = 11.0
	confetti.color_initial_ramp = _confetti_gradient()
	confetti.emitting = true
	add_child(confetti)
	get_tree().create_timer(confetti.lifetime + 0.5).timeout.connect(confetti.queue_free)


func _spawn_burst(at: Vector2, color: Color) -> void:
	var burst := CPUParticles2D.new()
	burst.position = at
	burst.amount = 40
	burst.lifetime = 0.9
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.direction = Vector2.UP
	burst.spread = 180.0
	burst.gravity = Vector2(0.0, 300.0)
	burst.initial_velocity_min = 160.0
	burst.initial_velocity_max = 380.0
	burst.scale_amount_min = 5.0
	burst.scale_amount_max = 9.0
	burst.color = color
	burst.emitting = true
	add_child(burst)
	get_tree().create_timer(burst.lifetime + 0.3).timeout.connect(burst.queue_free)


func _confetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	var colors := PackedColorArray(CONFETTI_COLORS)
	gradient.set_color(0, colors[0])
	gradient.set_color(1, colors[colors.size() - 1])
	for k in range(1, colors.size() - 1):
		gradient.add_point(float(k) / float(colors.size() - 1), colors[k])
	return gradient


func _ratio(current: int, needed: int) -> float:
	if needed <= 0:
		return 0.0
	return clampf(float(current) / float(needed), 0.0, 1.0)
