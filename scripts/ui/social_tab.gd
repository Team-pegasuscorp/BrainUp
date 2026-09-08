## Social tab page. Edit this script and `scenes/tabs/social_tab.tscn` only.
extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")

@onready var title_label: Label = %TitleLabel
@onready var content: VBoxContainer = %Content
@onready var message_label: Label = %MessageLabel

var _categories: Array[Dictionary] = []
var _selected_category_id: String = ""
var _current_challenge: Dictionary = {}
var _status_text: String = ""

var _live_state: String = "idle" # idle | searching | question | over
var _live_opponent_name: String = ""
var _live_my_score: int = 0
var _live_opponent_score: int = 0
var _live_question: Dictionary = {}
var _live_last_reveal: Dictionary = {}
var _live_answered: bool = false
var _live_countdown: float = 0.0
var _live_over_data: Dictionary = {}
var _countdown_label: Label = null


func _ready() -> void:
	_apply()
	LocaleManager.locale_changed.connect(_on_locale_changed)
	NetworkManager.challenge_created.connect(_on_challenge_created)
	NetworkManager.challenge_create_failed.connect(_on_challenge_create_failed)
	NetworkManager.challenge_joined.connect(_on_challenge_joined)
	NetworkManager.challenge_join_failed.connect(_on_challenge_join_failed)
	NetworkManager.challenge_fetched.connect(_on_challenge_fetched)
	NetworkManager.challenge_fetch_failed.connect(_on_challenge_fetch_failed)
	NetworkManager.live_match_found.connect(_on_live_match_found)
	NetworkManager.live_question.connect(_on_live_question)
	NetworkManager.live_reveal.connect(_on_live_reveal)
	NetworkManager.live_match_over.connect(_on_live_match_over)
	NetworkManager.live_error.connect(_on_live_error)


func _process(_delta: float) -> void:
	if _live_state != "question" or _live_answered:
		return
	_live_countdown = max(0.0, _live_countdown - _delta)
	if _countdown_label != null:
		_countdown_label.text = "%d" % ceili(_live_countdown)


func on_tab_shown() -> void:
	_apply()


func _apply() -> void:
	title_label.text = tr("UI_TAB_SOCIAL")
	_categories = QuestionLoaderScript.get_categories(LocaleManager.get_content_locale())
	if _selected_category_id.is_empty() and not _categories.is_empty():
		_selected_category_id = str(_categories[0].get("id", ""))
	_rebuild_content()


func _rebuild_content() -> void:
	for child in content.get_children():
		if child != message_label:
			child.queue_free()
	_countdown_label = null

	if _live_state != "idle":
		content.add_child(_live_section())
	elif _current_challenge.is_empty():
		content.add_child(_live_search_section())
		content.add_child(_create_section())
		content.add_child(_join_section())
	else:
		content.add_child(_challenge_card())

	if not _status_text.is_empty():
		var status := Label.new()
		status.text = _status_text
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.add_theme_font_size_override("font_size", 13)
		status.add_theme_color_override("font_color", UiTokens.INK_MUTED)
		content.add_child(status)

	message_label.text = tr("UI_SOCIAL_CHALLENGE_HINT")
	content.move_child(message_label, content.get_child_count() - 1)


func _create_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_SOCIAL))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_CREATE_CHALLENGE")
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", UiTokens.INK)
	vbox.add_child(caption)

	var category_scroll := ScrollContainer.new()
	category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	category_scroll.custom_minimum_size.y = 48
	vbox.add_child(category_scroll)

	var category_row := HBoxContainer.new()
	category_row.add_theme_constant_override("separation", 8)
	category_scroll.add_child(category_row)
	for category in _categories:
		var category_id := str(category.get("id", ""))
		var button := Button.new()
		button.text = str(category.get("name", category_id))
		var accent := UiTokens.accent_for_category(category_id)
		var selected := category_id == _selected_category_id
		button.add_theme_stylebox_override(
			"normal",
			UiStyle.category_tile_selected(accent) if selected else UiStyle.category_tile(accent)
		)
		button.pressed.connect(_on_category_pressed.bind(category_id))
		category_row.add_child(button)

	var create_button := Button.new()
	create_button.text = tr("UI_SOCIAL_CREATE_BUTTON")
	create_button.pressed.connect(_on_create_pressed)
	vbox.add_child(create_button)

	return panel


func _live_search_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_SOCIAL))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_LIVE_TITLE")
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", UiTokens.INK)
	vbox.add_child(caption)

	var search_button := Button.new()
	search_button.text = tr("UI_SOCIAL_LIVE_SEARCH")
	search_button.pressed.connect(_on_live_search_pressed)
	vbox.add_child(search_button)

	return panel


func _live_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_SOCIAL))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	match _live_state:
		"searching":
			var label := Label.new()
			label.text = tr("UI_SOCIAL_LIVE_SEARCHING")
			label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
			vbox.add_child(label)
			var cancel_button := Button.new()
			cancel_button.text = tr("UI_SOCIAL_LIVE_CANCEL")
			cancel_button.pressed.connect(_on_live_cancel_pressed)
			vbox.add_child(cancel_button)
		"question":
			_build_live_question_view(vbox)
		"over":
			_build_live_over_view(vbox)

	return panel


func _build_live_question_view(vbox: VBoxContainer) -> void:
	var header := Label.new()
	header.text = tr("UI_SOCIAL_LIVE_HEADER").format({
		"opponent": _live_opponent_name,
		"my_score": _live_my_score,
		"opponent_score": _live_opponent_score,
	})
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	vbox.add_child(header)

	_countdown_label = Label.new()
	_countdown_label.text = "%d" % ceili(_live_countdown)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 22)
	_countdown_label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	vbox.add_child(_countdown_label)

	var question_label := Label.new()
	question_label.text = str(_live_question.get("text", ""))
	question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	question_label.add_theme_font_size_override("font_size", 17)
	question_label.add_theme_color_override("font_color", UiTokens.INK)
	vbox.add_child(question_label)

	var correct_index := -1
	var your_selected := -2
	if not _live_last_reveal.is_empty():
		correct_index = int(_live_last_reveal.get("correct_index", -1))
		your_selected = int(_live_last_reveal.get("your_result", {}).get("selected_index", -2))

	var choices: Array = _live_question.get("choices", [])
	for index in range(choices.size()):
		var button := Button.new()
		button.text = str(choices[index])
		button.disabled = _live_answered
		if index == correct_index:
			button.add_theme_color_override("font_color", Color.FOREST_GREEN)
		elif index == your_selected:
			button.add_theme_color_override("font_color", Color.CRIMSON)
		button.pressed.connect(_on_live_choice_pressed.bind(index))
		vbox.add_child(button)

	if not _live_last_reveal.is_empty():
		var your_result: Dictionary = _live_last_reveal.get("your_result", {})
		var points_label := Label.new()
		points_label.text = tr("UI_SOCIAL_LIVE_POINTS").format({"points": int(your_result.get("points", 0))})
		points_label.add_theme_font_size_override("font_size", 13)
		points_label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
		vbox.add_child(points_label)


func _build_live_over_view(vbox: VBoxContainer) -> void:
	var won: bool = bool(_live_over_data.get("won", false))
	var my_score: int = int(_live_over_data.get("your_score", 0))
	var opponent_score: int = int(_live_over_data.get("opponent_score", 0))

	var key := "UI_SOCIAL_RESULT_LOSS"
	if won:
		key = "UI_SOCIAL_RESULT_WIN"
	elif my_score == opponent_score:
		key = "UI_SOCIAL_RESULT_TIE"

	var label := Label.new()
	label.text = tr(key).format({"my_score": my_score, "opponent_score": opponent_score})
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	vbox.add_child(label)

	var close_button := Button.new()
	close_button.text = tr("UI_SOCIAL_LIVE_CLOSE")
	close_button.pressed.connect(_on_live_close_pressed)
	vbox.add_child(close_button)


func _join_section() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_SOCIAL))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var caption := Label.new()
	caption.text = tr("UI_SOCIAL_JOIN_CHALLENGE")
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", UiTokens.INK)
	vbox.add_child(caption)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var code_input := LineEdit.new()
	code_input.placeholder_text = tr("UI_SOCIAL_CODE_PLACEHOLDER")
	code_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(code_input)

	var join_button := Button.new()
	join_button.text = tr("UI_SOCIAL_JOIN_BUTTON")
	join_button.pressed.connect(_on_join_pressed.bind(code_input))
	row.add_child(join_button)

	return panel


func _challenge_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.card(UiTokens.ACCENT_SOCIAL))

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var code := str(_current_challenge.get("code", ""))
	var category_id := str(_current_challenge.get("category", ""))
	var status := str(_current_challenge.get("status", "pending"))

	var header := Label.new()
	header.text = tr("UI_SOCIAL_CHALLENGE_HEADER").format({"category": category_id, "code": code})
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", UiTokens.INK)
	vbox.add_child(header)

	var copy_button := Button.new()
	copy_button.text = tr("UI_SOCIAL_COPY_CODE")
	copy_button.pressed.connect(_on_copy_code_pressed.bind(code))
	vbox.add_child(copy_button)

	if status == "completed":
		vbox.add_child(_make_result_label())
		var new_button := Button.new()
		new_button.text = tr("UI_SOCIAL_NEW_CHALLENGE")
		new_button.pressed.connect(_on_new_challenge_pressed)
		vbox.add_child(new_button)
	else:
		var status_label := Label.new()
		status_label.text = tr("UI_SOCIAL_STATUS_PENDING") if status == "pending" else tr("UI_SOCIAL_STATUS_ACCEPTED")
		status_label.add_theme_font_size_override("font_size", 13)
		status_label.add_theme_color_override("font_color", UiTokens.INK_MUTED)
		vbox.add_child(status_label)

		if status == "accepted" and not _my_score_submitted():
			var play_button := Button.new()
			play_button.text = tr("UI_PLAY")
			play_button.pressed.connect(_on_play_pressed)
			vbox.add_child(play_button)

		var refresh_button := Button.new()
		refresh_button.text = tr("UI_SOCIAL_REFRESH")
		refresh_button.pressed.connect(_on_refresh_pressed)
		vbox.add_child(refresh_button)

	return panel


func _make_result_label() -> Label:
	var is_challenger := _is_challenger()
	var my_score: int = int(_current_challenge.get("challenger_score" if is_challenger else "opponent_score", 0))
	var opponent_score: int = int(_current_challenge.get("opponent_score" if is_challenger else "challenger_score", 0))
	var label := Label.new()
	var key := "UI_SOCIAL_RESULT_WIN"
	if my_score < opponent_score:
		key = "UI_SOCIAL_RESULT_LOSS"
	elif my_score == opponent_score:
		key = "UI_SOCIAL_RESULT_TIE"
	label.text = tr(key).format({"my_score": my_score, "opponent_score": opponent_score})
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UiTokens.ACCENT_SOCIAL)
	return label


func _is_challenger() -> bool:
	return not NetworkManager.player_id.is_empty() \
		and str(_current_challenge.get("challenger_id", "")) == NetworkManager.player_id


func _my_score_submitted() -> bool:
	var field := "challenger_score" if _is_challenger() else "opponent_score"
	return typeof(_current_challenge.get(field)) != TYPE_NIL


func _on_category_pressed(category_id: String) -> void:
	_selected_category_id = category_id
	_rebuild_content()


func _on_create_pressed() -> void:
	if _selected_category_id.is_empty():
		return
	_status_text = tr("UI_SOCIAL_CREATING")
	_rebuild_content()
	NetworkManager.create_challenge(_selected_category_id)


func _on_challenge_created(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_status_text = ""
	_rebuild_content()


func _on_challenge_create_failed() -> void:
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_join_pressed(code_input: LineEdit) -> void:
	var code := code_input.text.strip_edges().to_upper()
	if code.is_empty():
		return
	_status_text = tr("UI_SOCIAL_JOINING")
	_rebuild_content()
	NetworkManager.join_challenge(code)


func _on_challenge_joined(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_status_text = ""
	_rebuild_content()


func _on_challenge_join_failed(_error_code: int) -> void:
	_status_text = tr("UI_SOCIAL_ERROR_JOIN")
	_rebuild_content()


func _on_refresh_pressed() -> void:
	NetworkManager.fetch_challenge(str(_current_challenge.get("code", "")))


func _on_challenge_fetched(challenge: Dictionary) -> void:
	_current_challenge = challenge
	_rebuild_content()


func _on_challenge_fetch_failed(_code: String) -> void:
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_copy_code_pressed(code: String) -> void:
	DisplayServer.clipboard_set(code)


func _on_new_challenge_pressed() -> void:
	_current_challenge = {}
	_rebuild_content()


func _on_play_pressed() -> void:
	var code := str(_current_challenge.get("code", ""))
	var category_id := str(_current_challenge.get("category", ""))
	GameManager.start_round(category_id, code)
	if not GameManager.has_questions():
		_status_text = tr("UI_EMPTY_QUESTIONS")
		_rebuild_content()
		return
	get_tree().change_scene_to_file(ScenePaths.QUIZ_GAME)


func _on_live_search_pressed() -> void:
	if _selected_category_id.is_empty():
		return
	_live_state = "searching"
	_rebuild_content()
	NetworkManager.start_live_matchmaking(_selected_category_id)


func _on_live_cancel_pressed() -> void:
	NetworkManager.stop_live_matchmaking()
	_live_state = "idle"
	_rebuild_content()


func _on_live_match_found(data: Dictionary) -> void:
	_live_opponent_name = str(data.get("opponent_name", ""))
	_live_my_score = 0
	_live_opponent_score = 0


func _on_live_question(data: Dictionary) -> void:
	_live_question = data
	_live_state = "question"
	_live_answered = false
	_live_last_reveal = {}
	_live_countdown = float(data.get("time_limit", 10.0))
	_rebuild_content()


func _on_live_choice_pressed(index: int) -> void:
	if _live_answered:
		return
	_live_answered = true
	NetworkManager.send_live_answer(int(_live_question.get("index", 0)), index)
	_rebuild_content()


func _on_live_reveal(data: Dictionary) -> void:
	_live_last_reveal = data
	_live_answered = true
	_live_my_score = int(data.get("your_result", {}).get("score", _live_my_score))
	_live_opponent_score = int(data.get("opponent_result", {}).get("score", _live_opponent_score))
	_rebuild_content()


func _on_live_match_over(data: Dictionary) -> void:
	_live_over_data = data
	_live_state = "over"
	_rebuild_content()


func _on_live_error(_reason: String) -> void:
	_live_state = "idle"
	_status_text = tr("UI_SOCIAL_ERROR_OFFLINE")
	_rebuild_content()


func _on_live_close_pressed() -> void:
	_live_state = "idle"
	_live_over_data = {}
	_rebuild_content()


func _on_locale_changed(_locale: String) -> void:
	_apply()
