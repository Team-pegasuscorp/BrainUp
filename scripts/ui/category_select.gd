extends Control

signal back_requested

const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const DailyChallenge = preload("res://scripts/profile/daily_challenge.gd")

@export var embedded_mode: bool = false

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
## Room inside ScrollContainer so selected-tile neon (shadow_size 20) isn't clipped.
const TILE_GLOW_PAD := 20


func _ready() -> void:
	_wrap_list_in_scroll()
	_apply_embedded_layout()
	_apply_translations()
	_load_categories()
	if embedded_mode:
		_setup_daily_card()
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
	start_button.text = tr("UI_PLAY")


func refresh() -> void:
	_apply_translations()
	_load_categories()
	if _daily_card != null:
		_render_daily()


func _load_categories() -> void:
	categories = QuestionLoaderScript.get_categories(LocaleManager.get_content_locale())
	for child in category_list.get_children():
		child.queue_free()
	_tile_buttons.clear()

	if categories.is_empty():
		description_label.text = tr("UI_NO_CATEGORIES")
		start_button.disabled = true
		return

	for index in range(categories.size()):
		var category: Dictionary = categories[index]
		var tile := _make_category_tile(index, category)
		category_list.add_child(tile)
		_tile_buttons.append(tile)

	_selected_index = clampi(_selected_index, 0, categories.size() - 1)
	_on_category_selected(_selected_index)


## Shared daily challenge card, pinned above the category list.
func _setup_daily_card() -> void:
	_daily_card = PanelContainer.new()
	_daily_card.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_LEADERBOARD))
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
		child.queue_free()

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 4)
	_daily_card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
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
	tag.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
	labels.add_child(tag)

	var name_label := Label.new()
	name_label.text = category_name if known else tr("UI_DAILY_CHALLENGE_LOADING")
	name_label.add_theme_font_size_override("font_size", UiScale.font(24))
	name_label.add_theme_color_override("font_color", UiTokens.INK)
	labels.add_child(name_label)

	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", UiScale.font(14))
	sub.add_theme_color_override("font_color", UiTokens.INK_MUTED)
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
		outline.border_color = UiTokens.ACCENT_LEADERBOARD
		for state in ["normal", "hover", "pressed", "focus"]:
			board.add_theme_stylebox_override(state, outline)
		PressScaleUtil.wire(board, self)
		board.pressed.connect(_open_daily_board)
		row.add_child(board)
		return

	var play := Button.new()
	play.text = tr("UI_PLAY")
	play.custom_minimum_size = Vector2(110, 48)
	play.add_theme_font_size_override("font_size", UiScale.font(20))
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		play.add_theme_color_override(slot, UiTokens.INK)
	var style := UiStyle.filled(UiTokens.ACCENT_LEADERBOARD, 24)
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
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_LEADERBOARD))
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
	var box := UiStyle.filled(Color(UiTokens.ACCENT_LEADERBOARD, 0.22) if mine else Color(0.95, 0.96, 0.98, 1), 16)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	if mine:
		box.set_border_width_all(2)
		box.border_color = UiTokens.ACCENT_LEADERBOARD
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
	score.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
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
	var button := Button.new()
	button.custom_minimum_size.y = 78
	button.text = ""
	button.pressed.connect(_on_category_selected.bind(index))
	PressScaleUtil.wire(button, self)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	## Balanced inset; left 16 keeps the color bar +10px vs the old 6px inset.
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(10, 0)
	swatch.color = accent
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(swatch)

	row.add_child(GameAssets.make_circular_icon_display(GameAssets.category_texture(category_id), "🧠", 56.0))

	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.alignment = BoxContainer.ALIGNMENT_CENTER
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)

	var name_label := Label.new()
	name_label.text = str(category.get("name", category_id))
	name_label.add_theme_font_size_override("font_size", UiScale.font(22))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)

	var desc := Label.new()
	desc.text = str(category.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", UiScale.font(13))
	desc.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(desc)

	button.set_meta("accent", accent)
	button.set_meta("name_label", name_label)
	button.set_meta("desc_label", desc)
	return button


func _on_category_selected(index: int) -> void:
	if index < 0 or index >= categories.size():
		return
	_selected_index = index
	description_label.text = categories[index].get("description", "")
	start_button.disabled = false
	for tile_index in range(_tile_buttons.size()):
		var tile := _tile_buttons[tile_index]
		var accent: Color = tile.get_meta("accent")
		var selected := tile_index == index
		tile.add_theme_stylebox_override(
			"normal",
			UiStyle.category_tile_selected(accent) if selected else UiStyle.category_tile(accent)
		)
		tile.add_theme_stylebox_override(
			"hover",
			UiStyle.category_tile_selected(accent) if selected else UiStyle.category_tile(accent)
		)
		tile.add_theme_stylebox_override(
			"pressed",
			UiStyle.category_tile_selected(accent)
		)
		var name_label: Label = tile.get_meta("name_label")
		var desc_label: Label = tile.get_meta("desc_label")
		name_label.add_theme_color_override("font_color", UiTokens.INK)
		desc_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)


func _on_start_pressed() -> void:
	if _selected_index < 0 or _selected_index >= categories.size():
		return
	var category_id: String = str(categories[_selected_index].get("id", ""))
	GameManager.start_round(category_id)
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
