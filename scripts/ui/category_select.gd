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


func _ready() -> void:
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


func _apply_embedded_layout() -> void:
	if not embedded_mode:
		return
	background.visible = false
	## The embedded page sits on the dark shell, so the title must be light.
	title_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	back_button.visible = false
	description_label.visible = false


func _apply_translations() -> void:
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
	var column := title_label.get_parent()
	column.add_child(_daily_card)
	column.move_child(_daily_card, title_label.get_index() + 1)
	NetworkManager.daily_challenge_received.connect(_on_daily_received)
	NetworkManager.daily_challenge_failed.connect(_on_daily_failed)
	_render_daily()
	_daily_fetching = true
	NetworkManager.fetch_daily_challenge()


func _on_daily_received(data: Dictionary) -> void:
	_daily_fetching = false
	_daily = data
	_render_daily()


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
	tag.add_theme_font_size_override("font_size", 14)
	tag.add_theme_color_override("font_color", UiTokens.ACCENT_LEADERBOARD)
	labels.add_child(tag)

	var name_label := Label.new()
	name_label.text = category_name if known else tr("UI_DAILY_CHALLENGE_LOADING")
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", UiTokens.INK)
	labels.add_child(name_label)

	var sub := Label.new()
	sub.add_theme_font_size_override("font_size", 14)
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
		var done := Label.new()
		done.text = "✓"
		done.add_theme_font_size_override("font_size", 34)
		done.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT)
		row.add_child(done)
		return

	var play := Button.new()
	play.text = tr("UI_PLAY")
	play.custom_minimum_size = Vector2(110, 48)
	play.add_theme_font_size_override("font_size", 20)
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
		play.add_theme_color_override(slot, UiTokens.INK)
	var style := UiStyle.filled(UiTokens.ACCENT_LEADERBOARD, 24)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		play.add_theme_stylebox_override(state, style)
	play.disabled = not known or _daily_fetching
	PressScaleUtil.wire(play, self)
	play.pressed.connect(_on_daily_play_pressed)
	row.add_child(play)


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
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
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
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)

	var desc := Label.new()
	desc.text = str(category.get("description", ""))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
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
