extends Control

## Ranked duel, full screen: search → category draft → questions → result.
## The server runs the match (see brainup-backend app/live_match.py); this screen only
## shows its messages and sends votes / answers. Mode comes from GameManager.selected_mode.

const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const UiFonts = preload("res://scripts/config/ui_fonts.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")

const PAGE_WIDTH := 680.0
const ROULETTE_SECONDS := 2.2
## Server's pause showing the colours before the reading phase (REVEAL_PAUSE_SECONDS).
const REVEAL_PAUSE := 1.5
const EXPLANATION_DELAY := 1.1
const JOKER_IDS: Array[String] = ["joker_5050", "joker_time"]

enum State { SEARCHING, DRAFT, PLAYING, WAITING, OVER, ERROR }

var _state: State = State.SEARCHING
var _mode: String = "classic"
var _accent: Color = UiTokens.ACCENT_QUIZ
var _category_names: Dictionary = {}

var _found: Dictionary = {}
var _opponent_name: String = ""
var _opponent_cosmetics: Dictionary = {}
var _opponent_trophies: int = 0
var _category: String = ""
var _my_score: int = 0
var _opponent_score: int = 0
var _my_lives: int = 0
var _opponent_lives: int = 0
var _my_clock: float = 0.0
var _opponent_clock: float = 0.0

var _draft_left: float = 0.0
var _draft_vote: String = ""
var _draft_tiles: Dictionary = {}
var _question: Dictionary = {}
var _question_left: float = 0.0
var _question_limit: float = 10.0
var _answered_index: int = -1
var _revealed: bool = false
var _over: Dictionary = {}
var _xp_gained: int = 0
var _error_key: String = ""
## Accepted friend invite this screen plays (empty = ranked matchmaking).
var _friend_challenge_id: String = ""
var _friend_name: String = ""
## Joker stock sent by the server at pairing, and the kinds already played this match.
var _jokers: Dictionary = {}
var _jokers_used: Dictionary = {}
var _joker_buttons: Dictionary = {}
var _removed_choices: Array[int] = []

var _margin: MarginContainer
var _body: VBoxContainer
var _timer_fill: Panel
var _timer_track: Panel
var _answer_buttons: Array[Button] = []
var _my_score_label: Label
var _opponent_score_label: Label
var _my_status_label: Label
var _opponent_status_label: Label
var _feedback_label: Label
var _question_card: PanelContainer
var _question_caption: Label
var _question_label: Label
var _question_hint: Label
var _tile_badges: Array[PanelContainer] = []
var _tile_letters: Array[Label] = []
var _tile_texts: Array[Label] = []
var _tile_markers: Array[HBoxContainer] = []
var _tap_catcher: Control
var _search_backdrop: Control
var _opponent_badge: Label
var _reading: bool = false
var _read_left: float = 0.0
var _read_total: float = 1.0
var _ready_sent: bool = false
var _opponent_is_ready: bool = false
var _fx: Array[Tween] = []


func _ready() -> void:
	_mode = str(GameManager.MODE_KEYS.get(GameManager.selected_mode, "classic"))
	_friend_challenge_id = str(GameManager.friend_challenge.get("id", ""))
	_friend_name = str(GameManager.friend_challenge.get("name", ""))
	_accent = UiTokens.MODE_ACCENTS[GameManager.selected_mode]
	for category in QuestionLoaderScript.get_categories(LocaleManager.get_content_locale()):
		_category_names[str(category.get("id", ""))] = str(category.get("name", ""))

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = Color.WHITE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/tab_page_bg.gdshader") as Shader
	mat.set_shader_parameter("accent", _accent)
	mat.set_shader_parameter("deep", UiTokens.BG_CREAM)
	bg.material = mat
	add_child(bg)

	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 18)
	_margin.add_child(_body)
	SafeArea.changed.connect(_apply_safe_area)
	_apply_safe_area()

	NetworkManager.live_match_found.connect(_on_match_found)
	NetworkManager.live_draft_result.connect(_on_draft_result)
	NetworkManager.live_match_start.connect(_on_match_start)
	NetworkManager.live_question.connect(_on_question)
	NetworkManager.live_reveal.connect(_on_reveal)
	NetworkManager.live_opponent_progress.connect(_on_opponent_progress)
	NetworkManager.live_player_done.connect(_on_player_done)
	NetworkManager.live_opponent_answered.connect(_on_opponent_answered)
	NetworkManager.live_opponent_ready.connect(_on_opponent_ready)
	NetworkManager.live_match_over.connect(_on_match_over)
	NetworkManager.live_error.connect(_on_error)
	NetworkManager.live_joker_result.connect(_on_joker_result)
	NetworkManager.live_opponent_joker.connect(_on_opponent_joker)
	_start_search()


func _apply_safe_area() -> void:
	_margin.add_theme_constant_override("margin_left", 20)
	_margin.add_theme_constant_override("margin_right", 20)
	_margin.add_theme_constant_override("margin_top", 20 + int(SafeArea.top))
	_margin.add_theme_constant_override("margin_bottom", 20 + int(SafeArea.bottom))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _state in [State.SEARCHING, State.OVER, State.ERROR]:
		_leave()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match _state:
		State.DRAFT:
			if _draft_left > 0.0:
				_draft_left = maxf(_draft_left - delta, 0.0)
				_set_timer_ratio(_draft_left / float((_found.get("draft", {}) as Dictionary).get("time_limit", 8.0)))
		State.PLAYING:
			if _reading and _read_left > 0.0:
				_read_left = maxf(_read_left - delta, 0.0)
				_set_timer_ratio(_read_left / _read_total)
			if not _revealed and _question_left > 0.0:
				_question_left = maxf(_question_left - delta, 0.0)
				_set_timer_ratio(_question_left / maxf(_question_limit, 0.01))
				if _mode == "time_attack":
					## One clock for the whole run: it only runs while a question is open.
					_my_clock = _question_left
					_refresh_header()


# --- Flow -------------------------------------------------------------------

func _start_search() -> void:
	_state = State.SEARCHING
	_found = {}
	_over = {}
	_category = ""
	_my_score = 0
	_opponent_score = 0
	if _friend_challenge_id.is_empty():
		NetworkManager.start_live_matchmaking("", _mode)
	else:
		NetworkManager.start_friend_match(_friend_challenge_id)
	_build_search()
	if not _friend_challenge_id.is_empty():
		_feedback_text(tr("UI_DUEL_WAITING_FRIEND").format({"name": _friend_name}))


func _leave() -> void:
	NetworkManager.stop_live_matchmaking()
	var from_friend := not _friend_challenge_id.is_empty()
	GameManager.friend_challenge = {}
	GameManager.shell_tab_index = ScenePaths.Tab.SOCIAL if from_friend else ScenePaths.Tab.QUIZ
	get_tree().change_scene_to_file(ScenePaths.APP_SHELL)


func _on_match_found(data: Dictionary) -> void:
	_found = data
	_opponent_name = str(data.get("opponent_name", "?"))
	var cosmetics: Variant = data.get("opponent_cosmetics", {})
	_opponent_cosmetics = cosmetics if typeof(cosmetics) == TYPE_DICTIONARY else {}
	_opponent_trophies = int(data.get("opponent_trophies", 0))
	_my_lives = int(data.get("lives", 0))
	_opponent_lives = _my_lives
	_my_clock = float(data.get("clock", 0.0))
	_opponent_clock = _my_clock
	_category = str(data.get("category", ""))
	var stock: Variant = data.get("jokers", {})
	_jokers = stock if typeof(stock) == TYPE_DICTIONARY else {}
	_jokers_used = {}
	AudioManager.play("correct")
	var draft: Variant = data.get("draft")
	if typeof(draft) == TYPE_DICTIONARY and not (draft.get("choices", []) as Array).is_empty():
		_state = State.DRAFT
		_draft_vote = ""
		_draft_left = float(draft.get("time_limit", 8.0))
		_build_draft(draft.get("choices", []))


func _on_draft_vote(category_id: String) -> void:
	if _state != State.DRAFT or not _draft_vote.is_empty():
		return
	_draft_vote = category_id
	AudioManager.play("click")
	NetworkManager.send_draft_vote(category_id)
	_style_draft_tiles(category_id, "", "")
	_feedback("UI_DUEL_DRAFT_WAITING")


## Roulette over the voted tiles (or all three), landing on the server's pick.
func _on_draft_result(data: Dictionary) -> void:
	_category = str(data.get("category", ""))
	_draft_left = 0.0
	var mine := str(data.get("your_vote", ""))
	var theirs := str(data.get("opponent_vote", ""))
	var pool: Array[String] = []
	for vote in [mine, theirs]:
		if not vote.is_empty() and not pool.has(vote):
			pool.append(vote)
	if pool.size() < 2:
		pool.clear()
		for key in _draft_tiles.keys():
			pool.append(str(key))
	var steps := 12 if pool.size() > 1 else 1
	var tween := create_tween()
	for step in range(steps):
		var shown: String = pool[step % pool.size()] if step < steps - 1 else _category
		tween.tween_callback(func() -> void:
			_style_draft_tiles(shown, mine, theirs)
			AudioManager.play("click")
		)
		tween.tween_interval(ROULETTE_SECONDS / float(steps) * (0.6 + float(step) / float(steps)))
	tween.tween_callback(func() -> void:
		_style_draft_tiles(_category, mine, theirs)
		AudioManager.play("correct")
		_feedback_text(tr("UI_DUEL_DRAFT_RESULT").format({"category": _category_name(_category)}))
	)


func _on_match_start(data: Dictionary) -> void:
	_category = str(data.get("category", _category))


func _on_question(data: Dictionary) -> void:
	_question = data
	_revealed = false
	_answered_index = -1
	_question_limit = float(data.get("time_limit", 10.0))
	_question_left = _question_limit
	if _mode == "time_attack":
		_my_clock = float(data.get("clock", _question_limit))
		_question_left = _my_clock
		_question_limit = float(_found.get("clock", 60.0))
	if _state != State.PLAYING:
		_state = State.PLAYING
		_build_playing()
	_show_question()


func _on_answer_pressed(index: int) -> void:
	if _state != State.PLAYING or _revealed or _answered_index >= 0:
		return
	_answered_index = index
	AudioManager.play("click")
	NetworkManager.send_live_answer(int(_question.get("index", 0)), index)
	_refresh_jokers()
	for i in range(_answer_buttons.size()):
		_answer_buttons[i].disabled = true
		_style_answer(i, "picked" if i == index else ("dim" if _removed_choices.has(i) else "idle"))
	_pulse(_answer_buttons[index], 1.04)


func _on_reveal(data: Dictionary) -> void:
	if _state != State.PLAYING:
		return
	_revealed = true
	_refresh_jokers()
	var question_index := int(data.get("index", 0))
	var correct := int(data.get("correct_index", -1))
	var mine: Dictionary = data.get("your_result", {})
	var theirs: Variant = data.get("opponent_result")
	var picked := int(mine.get("selected_index", -1))
	var their_pick := int((theirs as Dictionary).get("selected_index", -1)) if typeof(theirs) == TYPE_DICTIONARY else -1

	## Right answer glows, a wrong pick shakes, the rest steps back.
	for i in range(_answer_buttons.size()):
		_answer_buttons[i].disabled = true
		if i == correct:
			_style_answer(i, "correct")
			_pulse(_answer_buttons[i], 1.06)
		elif i == picked:
			_style_answer(i, "wrong")
			_shake(_answer_buttons[i])
		else:
			_style_answer(i, "dim")
	## Who picked what: each player's avatar lands on their tile.
	if picked >= 0 and picked < _tile_markers.size():
		_drop_marker(picked, SaveManager.get_cosmetics(), 0.0)
	if their_pick >= 0 and their_pick < _tile_markers.size():
		_drop_marker(their_pick, _opponent_cosmetics, 0.15)

	var is_correct := bool(mine.get("is_correct", false))
	AudioManager.play("correct" if is_correct else "wrong")
	var old_mine := _my_score
	var old_theirs := _opponent_score
	_my_score = int(mine.get("score", _my_score))
	if mine.has("lives"):
		_my_lives = int(mine["lives"])
	if mine.has("clock"):
		_my_clock = float(mine["clock"])
	if typeof(theirs) == TYPE_DICTIONARY:
		_opponent_score = int(theirs.get("score", _opponent_score))
		if theirs.has("lives"):
			_opponent_lives = int(theirs["lives"])
	_set_badge(_opponent_badge, "")
	var points := int(mine.get("points", 0))
	if points > 0:
		_feedback_text("+%d" % points)
		_feedback_label.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT)
	else:
		_feedback_text(tr("UI_DUEL_TIMEOUT") if picked < 0 else tr("UI_DUEL_WRONG"))
		_feedback_label.add_theme_color_override("font_color", UiTokens.FEEDBACK_WRONG)
	_pulse(_feedback_label, 1.2)
	_refresh_header()
	_count_up(_my_score_label, old_mine, _my_score)
	_count_up(_opponent_score_label, old_theirs, _opponent_score)

	## Synced modes: after the colours, the card turns into "Did you know?".
	var read_time := float(data.get("read_time", 0.0))
	var explanation := str(data.get("explanation", ""))
	if read_time > 0.0 and not explanation.is_empty():
		await get_tree().create_timer(EXPLANATION_DELAY).timeout
		if _state == State.PLAYING and _revealed and int(_question.get("index", -1)) == question_index:
			_show_explanation(explanation, read_time + REVEAL_PAUSE - EXPLANATION_DELAY)


func _show_explanation(text: String, seconds: float) -> void:
	_reading = true
	_ready_sent = false
	_read_total = maxf(seconds, 0.5)
	_read_left = _read_total
	var fade := _track(create_tween())
	fade.tween_property(_question_label, "modulate:a", 0.0, 0.15)
	fade.tween_callback(func() -> void:
		_question_caption.text = tr("UI_EXPLANATION_TITLE")
		_question_caption.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
		_question_label.text = text
		_question_label.add_theme_font_size_override("font_size", UiScale.font(20 if text.length() > 140 else 22))
		_question_hint.text = tr("UI_DUEL_TAP_READY")
	)
	fade.tween_property(_question_label, "modulate:a", 1.0, 0.2)
	_timer_fill.add_theme_stylebox_override("panel", UiStyle.filled(UiTokens.PODIUM_GOLD, 7))
	_tap_catcher.visible = true


## Tap during the explanation: "I'm done reading". The server moves on when both are.
func _on_ready_tap(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed) or not _reading or _ready_sent:
		return
	_ready_sent = true
	_tap_catcher.visible = false
	NetworkManager.send_live_ready(int(_question.get("index", 0)))
	AudioManager.play("click")
	_question_hint.text = "" if _opponent_is_ready else tr("UI_DUEL_WAITING_NAME").format({"name": _opponent_name})


func _on_opponent_answered(data: Dictionary) -> void:
	if _state != State.PLAYING or _revealed or int(data.get("index", -1)) != int(_question.get("index", -2)):
		return
	_set_badge(_opponent_badge, tr("UI_DUEL_OPPONENT_ANSWERED"))


func _on_opponent_ready(data: Dictionary) -> void:
	if int(data.get("index", -1)) != int(_question.get("index", -2)):
		return
	_opponent_is_ready = true
	_set_badge(_opponent_badge, tr("UI_DUEL_OPPONENT_READY"))
	if _reading and not _ready_sent:
		_question_hint.text = tr("UI_DUEL_OPPONENT_READY_TAP").format({"name": _opponent_name})


func _on_opponent_progress(data: Dictionary) -> void:
	_opponent_score = int(data.get("score", _opponent_score))
	_opponent_clock = float(data.get("clock", _opponent_clock))
	if _state == State.PLAYING or _state == State.WAITING:
		_refresh_header()


func _on_player_done(_data: Dictionary) -> void:
	_state = State.WAITING
	_set_timer_ratio(0.0)
	for button in _answer_buttons:
		button.disabled = true
	_feedback("UI_DUEL_WAITING_OPPONENT")


func _on_match_over(data: Dictionary) -> void:
	data["opponent_name"] = _opponent_name
	_over = data
	_my_score = int(data.get("your_score", _my_score))
	_opponent_score = int(data.get("opponent_score", _opponent_score))
	if bool(data.get("friendly", false)):
		_xp_gained = SaveManager.record_friend_duel_result(data)
	else:
		_xp_gained = SaveManager.record_duel_result(data)
	## Jokers spent during the match: refresh the stock from the server.
	if not _jokers_used.is_empty():
		NetworkManager.fetch_pass()
	var streak: Dictionary = DayStreak.record_play()
	if int(streak.get("xp", 0)) > 0:
		SaveManager.add_xp(int(streak["xp"]))
		_xp_gained += int(streak["xp"])
		SaveManager.save_data()
	_state = State.OVER
	AudioManager.play("correct" if bool(data.get("won", false)) else "wrong")
	_build_over()


func _on_error(reason: String) -> void:
	if _state == State.OVER:
		return
	_state = State.ERROR
	match reason:
		"aborted":
			_error_key = "UI_DUEL_ERROR_ABORTED"
		"friend_absent":
			_error_key = "UI_DUEL_ERROR_FRIEND_ABSENT"
		"invite_invalid":
			_error_key = "UI_DUEL_ERROR_INVITE_INVALID"
		_:
			_error_key = "UI_DUEL_ERROR_OFFLINE"
	_build_error()


# --- Screens ----------------------------------------------------------------

func _clear() -> void:
	_kill_fx()
	for child in _body.get_children():
		child.queue_free()
	if _tap_catcher != null and is_instance_valid(_tap_catcher):
		_tap_catcher.queue_free()
	_tap_catcher = null
	if _search_backdrop != null and is_instance_valid(_search_backdrop):
		_search_backdrop.queue_free()
	_search_backdrop = null
	_reading = false
	_answer_buttons.clear()
	_tile_badges.clear()
	_tile_letters.clear()
	_tile_texts.clear()
	_tile_markers.clear()
	_draft_tiles.clear()
	_joker_buttons.clear()
	_timer_fill = null
	_feedback_label = null


func _build_search() -> void:
	_clear()
	## Full-bleed player banner behind the search UI.
	_search_backdrop = Control.new()
	_search_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_search_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var banner := CosmeticsView.banner(SaveManager.get_equipped_banner(), Vector2.ZERO, 0)
	banner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search_backdrop.add_child(banner)
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0, 0, 0, 0.32)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_search_backdrop.add_child(veil)
	add_child(_search_backdrop)
	## Sit above the page shader, under the content margin.
	move_child(_search_backdrop, 1)

	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_theme_constant_override("separation", 14)

	## Stage fills the height; avatar bottom sits above mid, copy + mode underneath.
	const AVATAR_SIDE := 280.0
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(stage)

	var avatar := CosmeticsView.avatar(SaveManager.get_cosmetics(), AVATAR_SIDE)
	avatar.anchor_left = 0.5
	avatar.anchor_right = 0.5
	avatar.anchor_top = 0.5
	avatar.anchor_bottom = 0.5
	avatar.offset_left = -AVATAR_SIDE * 0.5
	avatar.offset_right = AVATAR_SIDE * 0.5
	avatar.offset_top = -AVATAR_SIDE - 200.0
	avatar.offset_bottom = -200.0
	stage.add_child(avatar)

	var identity := VBoxContainer.new()
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_theme_constant_override("separation", 10)
	identity.anchor_left = 0.0
	identity.anchor_right = 1.0
	identity.anchor_top = 0.5
	identity.anchor_bottom = 0.5
	identity.offset_top = 14.0 - 200.0
	identity.grow_horizontal = Control.GROW_DIRECTION_BOTH
	stage.add_child(identity)

	var name_label := _title(SaveManager.player_name, 28)
	name_label.add_theme_font_size_override(
		"font_size", UiScale.font(UiTokens.pseudo_font_size(SaveManager.player_name, 28))
	)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("outline_size", 5)
	identity.add_child(name_label)

	var trophies := _title("🏆 %d" % SaveManager.trophies, 24)
	trophies.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	trophies.add_theme_constant_override("outline_size", 4)
	identity.add_child(trophies)

	var title := _title(tr("UI_DUEL_SEARCHING").to_upper(), 40)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("outline_size", 6)
	identity.add_child(title)

	var mode_wrap := CenterContainer.new()
	mode_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(mode_wrap)
	mode_wrap.add_child(_mode_badge(_mode))

	var cancel := _button(tr("UI_DUEL_CANCEL"), Color(1, 1, 1, 0.18), Color.WHITE)
	cancel.pressed.connect(_leave)
	_body.add_child(cancel)


func _build_draft(choices: Array) -> void:
	_clear()
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_child(_face_off("🏆 %d" % SaveManager.trophies, "🏆 %d" % _opponent_trophies))
	_body.add_child(_title(tr("UI_DUEL_DRAFT_TITLE"), 26))
	_body.add_child(_subtitle(tr("UI_DUEL_DRAFT_HINT")))
	_body.add_child(_timer_bar())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_body.add_child(row)
	var width := (PAGE_WIDTH - 24.0) / 3.0
	for raw in choices:
		var category_id := str(raw)
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(width, 230)
		tile.focus_mode = Control.FOCUS_NONE
		tile.pressed.connect(_on_draft_vote.bind(category_id))
		var column := VBoxContainer.new()
		column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 8)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(column)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(110, 110)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = GameAssets.category_texture(category_id)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(icon)
		var name_label := Label.new()
		name_label.text = _category_name(category_id)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", UiScale.font(17))
		name_label.add_theme_color_override("font_color", Color.WHITE)
		column.add_child(name_label)
		var votes := Label.new()
		votes.name = "Votes"
		votes.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		votes.add_theme_font_size_override("font_size", UiScale.font(13))
		votes.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		column.add_child(votes)
		row.add_child(tile)
		_draft_tiles[category_id] = tile
	_feedback_label = _subtitle("")
	_body.add_child(_feedback_label)
	_style_draft_tiles("", "", "")


func _style_draft_tiles(highlight: String, mine: String, theirs: String) -> void:
	for key in _draft_tiles:
		var category_id := str(key)
		var tile: Button = _draft_tiles[key]
		var accent := UiTokens.accent_for_category(category_id)
		var lit := category_id == highlight
		var style := UiStyle.filled(accent.darkened(0.15) if lit else Color(accent.r, accent.g, accent.b, 0.22), 20)
		style.set_border_width_all(4 if lit else 2)
		style.border_color = Color.WHITE if lit else Color(accent.r, accent.g, accent.b, 0.6)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.5 if lit else 0.1)
		style.shadow_size = 16 if lit else 4
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			tile.add_theme_stylebox_override(state, style)
		tile.disabled = not _draft_vote.is_empty() or _draft_left <= 0.0
		var votes := tile.find_child("Votes", true, false) as Label
		if votes != null:
			var tags: Array[String] = []
			if category_id == mine:
				tags.append(tr("UI_DUEL_VOTE_YOU"))
			if category_id == theirs:
				tags.append(tr("UI_DUEL_VOTE_OPPONENT"))
			votes.text = " · ".join(tags)


func _build_playing() -> void:
	_clear()
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_theme_constant_override("separation", 14)
	_body.add_child(_duel_header())
	_body.add_child(_subtitle("%s · %s" % [_category_name(_category), _mode_name()]))
	_body.add_child(_timer_bar())

	_question_card = PanelContainer.new()
	_question_card.add_theme_stylebox_override("panel", UiStyle.profile_surface(_accent, true, 20))
	_question_card.custom_minimum_size.y = 280
	_body.add_child(_question_card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_question_card.add_child(column)
	_question_caption = Label.new()
	_question_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_caption.add_theme_font_size_override("font_size", UiScale.font(14))
	column.add_child(_question_caption)
	_question_label = Label.new()
	_question_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_question_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(_question_label)
	_question_hint = Label.new()
	_question_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_hint.add_theme_font_size_override("font_size", UiScale.font(14))
	_question_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.65))
	column.add_child(_question_hint)

	for i in range(4):
		var tile := _make_answer_tile(i)
		_body.add_child(tile)
		_answer_buttons.append(tile)
	var jokers := _joker_row()
	if jokers != null:
		_body.add_child(jokers)
	_feedback_label = _title("", 26)
	_body.add_child(_feedback_label)

	## Full-screen catcher: any tap during the explanation means "ready".
	_tap_catcher = Control.new()
	_tap_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tap_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_catcher.visible = false
	_tap_catcher.gui_input.connect(_on_ready_tap)
	add_child(_tap_catcher)
	_refresh_header()


## Answer tile: letter badge, text, and a slot where the players' avatars land.
func _make_answer_tile(index: int) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size.y = 108
	tile.focus_mode = Control.FOCUS_NONE
	tile.pressed.connect(_on_answer_pressed.bind(index))
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_right", 12)
	tile.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(46, 46)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	var letter := Label.new()
	letter.text = ["A", "B", "C", "D"][index]
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", UiScale.font(18))
	badge.add_child(letter)
	var text := Label.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", UiScale.font(21))
	row.add_child(text)
	var markers := HBoxContainer.new()
	markers.add_theme_constant_override("separation", -10)
	markers.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(markers)
	_tile_badges.append(badge)
	_tile_letters.append(letter)
	_tile_texts.append(text)
	_tile_markers.append(markers)
	return tile


func _show_question() -> void:
	_kill_fx()
	_reading = false
	_ready_sent = false
	_opponent_is_ready = false
	if _tap_catcher != null:
		_tap_catcher.visible = false
	var index := int(_question.get("index", 0))
	var total := int(_found.get("total_questions", 0))
	_question_caption.text = (
		tr("UI_DUEL_QUESTION_OF").format({"n": index + 1, "total": total}) if total > 0
		else tr("UI_DUEL_QUESTION_N").format({"n": index + 1})
	).to_upper()
	_question_caption.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_question_label.text = str(_question.get("text", ""))
	_question_label.add_theme_font_size_override("font_size", UiScale.font(24 if _question_label.text.length() < 90 else 21))
	_question_hint.text = ""
	var choices: Array = _question.get("choices", [])
	for i in range(_answer_buttons.size()):
		_tile_texts[i].text = str(choices[i]) if i < choices.size() else ""
		_answer_buttons[i].disabled = i >= choices.size()
		for marker in _tile_markers[i].get_children():
			marker.queue_free()
		_style_answer(i, "idle")
	_removed_choices.clear()
	_refresh_jokers()
	if _feedback_label != null:
		_feedback_label.text = ""
	_set_badge(_opponent_badge, "")
	if _timer_fill != null:
		_timer_fill.add_theme_stylebox_override("panel", UiStyle.filled(_accent, 7))
	_set_timer_ratio(_question_left / maxf(_question_limit, 0.01))
	_animate_question_in()


## Question card drops in, then the four tiles pop one after the other.
func _animate_question_in() -> void:
	_question_card.pivot_offset = _question_card.size * 0.5
	_question_card.modulate.a = 0.0
	_question_card.scale = Vector2(0.94, 0.94)
	var tween := _track(create_tween().set_parallel(true))
	tween.tween_property(_question_card, "modulate:a", 1.0, 0.22)
	tween.tween_property(_question_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var quick := _mode == "time_attack"
	for i in range(_answer_buttons.size()):
		var tile := _answer_buttons[i]
		tile.pivot_offset = Vector2(tile.size.x * 0.5, tile.size.y * 0.5)
		tile.modulate.a = 0.0
		tile.scale = Vector2(0.9, 0.9)
		var delay := (0.05 if quick else 0.15) + float(i) * (0.04 if quick else 0.08)
		tween.tween_property(tile, "modulate:a", 1.0, 0.18).set_delay(delay)
		tween.tween_property(tile, "scale", Vector2.ONE, 0.26).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Compact face-off for the match: avatar, name, score and lives / clock per side.
func _duel_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var mine := _header_side(SaveManager.player_name, SaveManager.get_cosmetics(), false)
	var theirs := _header_side(_opponent_name, _opponent_cosmetics, true)
	_my_score_label = mine.get_meta("score")
	_my_status_label = mine.get_meta("status")
	_opponent_score_label = theirs.get_meta("score")
	_opponent_status_label = theirs.get_meta("status")
	_opponent_badge = theirs.get_meta("badge")
	row.add_child(mine)
	var vs := Label.new()
	vs.text = "VS"
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.size_flags_vertical = Control.SIZE_FILL
	vs.add_theme_font_size_override("font_size", UiScale.font(20))
	vs.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	row.add_child(vs)
	row.add_child(theirs)
	return row


func _header_side(display_name: String, cosmetics: Dictionary, mirrored: bool) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var clear := StyleBoxFlat.new()
	clear.bg_color = Color(0, 0, 0, 0)
	card.add_theme_stylebox_override("panel", clear)
	var back := CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2(0, 104), 16)
	back.modulate = Color(0.75, 0.75, 0.8)
	card.add_child(back)
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	card.add_child(pad)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_END if mirrored else BoxContainer.ALIGNMENT_BEGIN
	pad.add_child(row)
	var avatar := CosmeticsView.avatar(cosmetics, 76)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var align := HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = align
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", UiScale.font(17))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	info.add_child(name_label)
	var score := Label.new()
	score.horizontal_alignment = align
	score.add_theme_font_size_override("font_size", UiScale.font(26))
	score.add_theme_color_override("font_color", Color.WHITE)
	score.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	score.add_theme_constant_override("outline_size", 4)
	info.add_child(score)
	var status := Label.new()
	status.horizontal_alignment = align
	status.add_theme_font_size_override("font_size", UiScale.font(15))
	status.add_theme_color_override("font_color", Color.WHITE)
	## Hearts need the emoji font; the time attack clock stays in the text font (digits).
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null and _mode == "survival":
		status.add_theme_font_override("font", emoji_font)
	info.add_child(status)
	if mirrored:
		row.add_child(info)
		row.add_child(avatar)
	else:
		row.add_child(avatar)
		row.add_child(info)
	var badge := Label.new()
	badge.horizontal_alignment = align
	badge.add_theme_font_size_override("font_size", UiScale.font(13))
	badge.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	info.add_child(badge)
	card.set_meta("score", score)
	card.set_meta("status", status)
	card.set_meta("badge", badge)
	return card


func _refresh_header() -> void:
	if _my_score_label == null or not is_instance_valid(_my_score_label):
		return
	_my_score_label.text = str(_my_score)
	_opponent_score_label.text = str(_opponent_score)
	match _mode:
		"survival":
			_my_status_label.text = _hearts(_my_lives)
			_opponent_status_label.text = _hearts(_opponent_lives)
		"time_attack":
			_my_status_label.text = "%d s" % ceili(_my_clock)
			_opponent_status_label.text = "%d s" % ceili(_opponent_clock)


func _hearts(lives: int) -> String:
	var total := int(_found.get("lives", 3))
	return "❤️".repeat(maxi(lives, 0)) + "🖤".repeat(maxi(total - maxi(lives, 0), 0))


func _build_over() -> void:
	_clear()
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	var won := bool(_over.get("won", false))
	var draw := bool(_over.get("draw", false))
	var key := "UI_DUEL_DRAW" if draw else ("UI_DUEL_WIN" if won else "UI_DUEL_LOSS")
	var title := _title(tr(key), 42)
	title.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD if won else Color.WHITE)
	_body.add_child(title)
	_body.add_child(_subtitle("%s · %s" % [_category_name(_category), _mode_name()]))
	_body.add_child(_face_off(
		str(_my_score), str(_opponent_score), UiTokens.PODIUM_GOLD if won else Color(0, 0, 0, 0)
	))

	var friendly := bool(_over.get("friendly", false))
	var delta := int(_over.get("trophy_delta", 0))
	if friendly:
		var rivalry := SaveManager.get_friend_rivalry(str(_over.get("opponent_id", "")))
		_body.add_child(_subtitle(tr("UI_DUEL_FRIENDLY_RECORD").format({
			"wins": int(rivalry.get("wins", 0)), "losses": int(rivalry.get("losses", 0)),
		})))
	var cups := _title("%s%d 🏆   ·   %s %d" % [
		"+" if delta > 0 else "", delta, tr("UI_DUEL_TOTAL"), int(_over.get("trophies", SaveManager.trophies))
	], 26)
	cups.add_theme_color_override("font_color", UiTokens.FEEDBACK_CORRECT if delta > 0 else (UiTokens.FEEDBACK_WRONG if delta < 0 else Color.WHITE))
	if not friendly:
		_body.add_child(cups)
	var bonus := int(_over.get("trophy_streak_bonus", 0)) + int(_over.get("trophy_loss_consolation", 0))
	if bonus > 0:
		_body.add_child(_subtitle(tr("UI_DUEL_STREAK_BONUS").format({"bonus": bonus})))
	_body.add_child(_subtitle("+%d XP" % _xp_gained))
	var pass_xp := int(_over.get("pass_xp", 0))
	if pass_xp > 0:
		var pass_line := _title(tr("UI_DUEL_PASS_XP").format({"xp": pass_xp}), 20)
		pass_line.add_theme_color_override("font_color", Color(1.0, 0.78, 0.2, 1))
		_body.add_child(pass_line)
		NetworkManager.fetch_pass()

	## A friend invite is played once: a rematch is a new invite from the Social tab.
	if _friend_challenge_id.is_empty():
		var again := _button(tr("UI_DUEL_PLAY_AGAIN"), _accent, UiTokens.INK)
		again.pressed.connect(_start_search)
		_body.add_child(again)
	var back := _button(tr("UI_BACK"), Color(1, 1, 1, 0.14), Color.WHITE)
	back.pressed.connect(_leave)
	_body.add_child(back)


func _build_error() -> void:
	_clear()
	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_child(_title(tr(_error_key).format({"name": _friend_name}), 24))
	if _friend_challenge_id.is_empty():
		var again := _button(tr("UI_DUEL_PLAY_AGAIN"), _accent, UiTokens.INK)
		again.pressed.connect(_start_search)
		_body.add_child(again)
	var back := _button(tr("UI_BACK"), Color(1, 1, 1, 0.14), Color.WHITE)
	back.pressed.connect(_leave)
	_body.add_child(back)


# --- Jokers -----------------------------------------------------------------

## Row of joker buttons under the answers; null when the player owns none.
func _joker_row() -> Control:
	var total := 0
	for joker_id in JOKER_IDS:
		total += int(_jokers.get(joker_id, 0))
	if total <= 0:
		return null
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	for joker_id in JOKER_IDS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(200, 64)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", UiScale.font(19))
		button.add_theme_color_override("font_color", Color.WHITE)
		button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.45))
		var fill := Color(0.55, 0.32, 0.95, 1)
		button.add_theme_stylebox_override("normal", UiStyle.filled(fill, 32))
		button.add_theme_stylebox_override("hover", UiStyle.filled(fill.lightened(0.12), 32))
		button.add_theme_stylebox_override("pressed", UiStyle.filled(fill.darkened(0.15), 32))
		button.add_theme_stylebox_override("disabled", UiStyle.filled(Color(1, 1, 1, 0.12), 32))
		button.pressed.connect(_on_joker_pressed.bind(joker_id))
		PressScaleUtil.wire(button, self)
		row.add_child(button)
		_joker_buttons[joker_id] = button
	_refresh_jokers()
	return row


## A joker can be played once per match, while a question is open and unanswered.
func _refresh_jokers() -> void:
	var open := _state == State.PLAYING and not _revealed and _answered_index < 0 and not _question.is_empty()
	for joker_id in _joker_buttons.keys():
		var button: Button = _joker_buttons[joker_id]
		if not is_instance_valid(button):
			continue
		var count := int(_jokers.get(joker_id, 0))
		var label := "50/50" if joker_id == "joker_5050" else "+5 s"
		button.text = "%s  ×%d" % [label, count]
		button.disabled = not open or count <= 0 or _jokers_used.has(joker_id)


func _on_joker_pressed(joker_id: String) -> void:
	if _jokers_used.has(joker_id) or int(_jokers.get(joker_id, 0)) <= 0:
		return
	## Marked used right away so a double tap cannot send it twice.
	_jokers_used[joker_id] = true
	NetworkManager.send_joker(int(_question.get("index", 0)), joker_id)
	_refresh_jokers()


func _on_joker_result(data: Dictionary) -> void:
	var joker_id := str(data.get("joker", ""))
	if not bool(data.get("ok", false)):
		## Refused (question closed meanwhile or stock empty): the joker was not spent.
		if int(data.get("index", -1)) == int(_question.get("index", -2)) and not _revealed:
			_jokers_used.erase(joker_id)
		_refresh_jokers()
		return
	_jokers[joker_id] = int(data.get("left", maxi(int(_jokers.get(joker_id, 1)) - 1, 0)))
	_jokers_used[joker_id] = true
	if int(data.get("index", -1)) != int(_question.get("index", -2)) or _revealed:
		_refresh_jokers()
		return
	if joker_id == "joker_5050":
		for raw in data.get("removed", []):
			var i := int(raw)
			if i < 0 or i >= _answer_buttons.size():
				continue
			_removed_choices.append(i)
			_answer_buttons[i].disabled = true
			_style_answer(i, "dim")
			_tile_texts[i].text = ""
	else:
		var bonus := float(data.get("bonus", 5.0))
		_question_left += bonus
		_question_limit = maxf(_question_limit, _question_left)
		_feedback_text("+%d s" % int(bonus))
		_feedback_label.add_theme_color_override("font_color", Color(0.75, 0.6, 1.0, 1))
		_pulse(_feedback_label, 1.2)
	AudioManager.play("correct")
	_refresh_jokers()


func _on_opponent_joker(data: Dictionary) -> void:
	if _state != State.PLAYING:
		return
	_set_badge(_opponent_badge, "50/50" if str(data.get("joker", "")) == "joker_5050" else "+5 s")


# --- Building blocks --------------------------------------------------------

func _face_off(my_value: String, opponent_value: String, highlight: Color = Color(0, 0, 0, 0)) -> Control:
	return CosmeticsView.face_off(
		SaveManager.player_name, SaveManager.get_cosmetics(), my_value,
		_opponent_name, _opponent_cosmetics, opponent_value,
		PAGE_WIDTH, highlight
	)


func _timer_bar() -> Control:
	_timer_track = Panel.new()
	_timer_track.custom_minimum_size.y = 14
	_timer_track.add_theme_stylebox_override("panel", UiStyle.filled(Color(1, 1, 1, 0.14), 7))
	_timer_fill = Panel.new()
	_timer_fill.add_theme_stylebox_override("panel", UiStyle.filled(_accent, 7))
	_timer_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_timer_track.add_child(_timer_fill)
	_set_timer_ratio(1.0)
	return _timer_track


func _set_timer_ratio(ratio: float) -> void:
	if _timer_fill == null or not is_instance_valid(_timer_fill):
		return
	_timer_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	_timer_fill.offset_right = 0


func _style_answer(index: int, look: String) -> void:
	var tile := _answer_buttons[index]
	var fill := Color(1, 1, 1, 0.96)
	var ink := UiTokens.INK
	var badge_fill := Color(_accent.r, _accent.g, _accent.b, 0.18)
	var badge_ink := _accent.darkened(0.25)
	var border := Color(0, 0, 0, 0)
	tile.modulate.a = 1.0
	match look:
		"picked":
			fill = _accent
			badge_fill = Color(1, 1, 1, 0.3)
			badge_ink = UiTokens.INK
		"correct":
			fill = UiTokens.FEEDBACK_CORRECT
			ink = Color.WHITE
			badge_fill = Color(1, 1, 1, 0.25)
			badge_ink = Color.WHITE
			border = Color(1, 1, 1, 0.9)
		"wrong":
			fill = UiTokens.FEEDBACK_WRONG
			ink = Color.WHITE
			badge_fill = Color(1, 1, 1, 0.25)
			badge_ink = Color.WHITE
		"dim":
			tile.modulate.a = 0.45
	var style := UiStyle.filled(fill, 20)
	style.shadow_color = Color(0, 0, 0, 0.18)
	style.shadow_size = 6
	style.shadow_offset = Vector2(0, 3)
	if border.a > 0.0:
		style.set_border_width_all(3)
		style.border_color = border
	var hover := style.duplicate() as StyleBoxFlat
	if look == "idle":
		hover.set_border_width_all(3)
		hover.border_color = _accent
	for state in ["normal", "focus", "disabled"]:
		tile.add_theme_stylebox_override(state, style)
	tile.add_theme_stylebox_override("hover", hover)
	tile.add_theme_stylebox_override("pressed", hover)
	_tile_texts[index].add_theme_color_override("font_color", ink)
	_tile_letters[index].add_theme_color_override("font_color", badge_ink)
	_tile_badges[index].add_theme_stylebox_override("panel", UiStyle.filled(badge_fill, 23))


## Small framed avatar that lands on the tile a player picked.
func _drop_marker(index: int, cosmetics: Dictionary, delay: float) -> void:
	var marker := CosmeticsView.avatar(cosmetics, 44)
	marker.pivot_offset = Vector2(22, 22)
	marker.scale = Vector2.ZERO
	_tile_markers[index].add_child(marker)
	var tween := _track(create_tween())
	tween.tween_interval(delay)
	tween.tween_property(marker, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _count_up(label: Label, from: int, to: int) -> void:
	if label == null or from == to:
		return
	var tween := _track(create_tween())
	tween.tween_method(func(value: float) -> void: label.text = str(int(value)), float(from), float(to), 0.5)
	label.pivot_offset = label.size * 0.5
	tween.parallel().tween_property(label, "scale", Vector2(1.25, 1.25), 0.12)
	tween.tween_property(label, "scale", Vector2.ONE, 0.2)


func _pulse(control: Control, amount: float) -> void:
	if control == null:
		return
	control.pivot_offset = control.size * 0.5
	var tween := _track(create_tween())
	tween.tween_property(control, "scale", Vector2(amount, amount), 0.09)
	tween.tween_property(control, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	var tween := _track(create_tween())
	for angle in [0.03, -0.03, 0.02, -0.02, 0.0]:
		tween.tween_property(control, "rotation", angle, 0.05)


func _set_badge(label: Label, text: String) -> void:
	if label == null or not is_instance_valid(label):
		return
	label.text = text
	if not text.is_empty():
		_pulse(label, 1.3)


func _track(tween: Tween) -> Tween:
	_fx.append(tween)
	return tween


func _kill_fx() -> void:
	for tween in _fx:
		if tween != null and tween.is_valid():
			tween.kill()
	_fx.clear()
	for tile in _answer_buttons:
		tile.scale = Vector2.ONE
		tile.rotation = 0.0


func _feedback(key: String) -> void:
	_feedback_text(tr(key))


func _feedback_text(text: String) -> void:
	if _feedback_label != null and is_instance_valid(_feedback_label):
		_feedback_label.text = text


func _title(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", UiScale.font(size))
	label.add_theme_color_override("font_color", Color.WHITE)
	return label


func _subtitle(text: String) -> Label:
	var label := _title(text, 17)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	return label


func _button(text: String, fill: Color, ink: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 68
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", UiScale.font(20))
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, UiStyle.filled(fill, 22))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, ink)
	PressScaleUtil.wire(button, self)
	return button


func _mode_name() -> String:
	match _mode:
		"survival":
			return tr("UI_MODE_SURVIVAL")
		"time_attack":
			return tr("UI_MODE_TIME_ATTACK")
	return tr("UI_MODE_CLASSIC")


## Same coloured mode chip as home “last matches” / history rows.
func _mode_badge(mode: String) -> Control:
	var key := "UI_MODE_CLASSIC"
	var icon := "🎯"
	var accent := UiTokens.ACCENT_MODE_CLASSIC
	match mode:
		"survival":
			key = "UI_MODE_SURVIVAL"
			icon = "❤️"
			accent = UiTokens.ACCENT_MODE_SURVIVAL
		"time_attack":
			key = "UI_MODE_TIME_ATTACK"
			icon = "⏱️"
			accent = UiTokens.ACCENT_MODE_TIME_ATTACK
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_border_width_all(0)
	style.set_corner_radius_all(14)
	style.content_margin_left = 16
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	badge.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	badge.add_child(row)
	var icon_label := Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", UiScale.font(22))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		icon_label.add_theme_font_override("font", emoji_font)
	row.add_child(icon_label)
	var label := Label.new()
	label.text = tr(key).to_upper()
	label.add_theme_font_size_override("font_size", UiScale.font(18))
	label.add_theme_color_override("font_color", Color(0.10, 0.08, 0.12, 1))
	row.add_child(label)
	return badge


func _category_name(category_id: String) -> String:
	return str(_category_names.get(category_id, category_id))
