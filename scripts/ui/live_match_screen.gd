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
const ProfileSnapshot = preload("res://scripts/profile/profile_snapshot.gd")

const PAGE_WIDTH := 680.0
const ROULETTE_SECONDS := 2.2
## Pause on the “opponent found” VS screen before the category draft.
const MATCHED_SECONDS := 5.0
## Fade between search and the match-found VS beat.
const PAGE_FADE_OUT := 0.2
const PAGE_FADE_IN := 0.3
## Hold on the drafted category after the roulette lands, before questions.
const DRAFT_RESULT_HOLD := 2.5
## Browse every duel screen with mock data (no server / no real match). Flip off for shipping.
const DEBUG_PREVIEW_FLOW := false
## Play preview: each tap on Play cycles category tint + mode aurora.
const DEBUG_PREVIEW_CATEGORIES: Array[String] = [
	"sport", "cinema", "history", "music", "geography", "science", "general", "television",
]
const DEBUG_PREVIEW_MODES: Array[String] = ["classic", "survival", "time_attack"]
## Server's pause showing the colours before the reading phase (REVEAL_PAUSE_SECONDS).
const REVEAL_PAUSE := 1.5
const EXPLANATION_DELAY := 1.1
## Server keeps accepting an answer briefly after the clock hits zero (live_match.py).
const ANSWER_GRACE_SECONDS := 2.0
const JOKER_IDS: Array[String] = ["joker_5050", "joker_time"]

enum State { SEARCHING, MATCHED, DRAFT, PLAYING, WAITING, OVER, ERROR }

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
var _pending_draft_choices: Array = []
var _matched_left: float = 0.0
var _draft_reveal_holding: bool = false
## True from draft_result until the post-roulette hold ends (queues an early first question).
var _awaiting_draft_hold: bool = false
var _pending_question: Dictionary = {}
var _page_fade: Tween
var _preview_category_i: int = 0
var _preview_mode_i: int = 0
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
var _tile_badge_discs: Array[PanelContainer] = []
var _tile_letters: Array[Label] = []
var _tile_texts: Array[Label] = []
var _tile_markers: Array[HBoxContainer] = []
var _tap_catcher: Control
var _search_backdrop: Control
var _page_bg: ColorRect
var _mode_bg_material: ShaderMaterial
var _brand_bg_material: Material
var _preview_bar: Control
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

	_brand_bg_material = load("res://themes/quizup_bg_material.tres") as Material
	_mode_bg_material = ShaderMaterial.new()
	_mode_bg_material.shader = load("res://shaders/tab_page_bg.gdshader") as Shader
	_mode_bg_material.set_shader_parameter("accent", _accent)
	_mode_bg_material.set_shader_parameter("deep", UiTokens.BG_CREAM)

	_page_bg = ColorRect.new()
	_page_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page_bg.color = UiTokens.BG_CREAM
	_set_page_bg_mode()
	add_child(_page_bg)

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
	if DEBUG_PREVIEW_FLOW:
		_debug_seed_preview_data()
		_debug_install_preview_bar()
		_debug_show_screen("search")
	else:
		_start_search()


func _set_page_bg_brand() -> void:
	if _page_bg == null:
		return
	_page_bg.color = UiTokens.BG_CREAM
	_page_bg.material = _brand_bg_material


func _set_page_bg_mode() -> void:
	if _page_bg == null:
		return
	_page_bg.color = Color.WHITE
	_page_bg.material = _mode_bg_material


func _debug_seed_preview_data() -> void:
	_opponent_name = "Alex"
	_opponent_cosmetics = ShopCatalog.demo_cosmetics_for("Alex")
	_opponent_trophies = 1248
	_pending_draft_choices = ["sport", "cinema", "history"]
	_draft_left = 8.0
	_draft_vote = ""
	_category = "sport"
	_my_score = 420
	_opponent_score = 380
	_my_lives = 2
	_opponent_lives = 1
	_my_clock = 42.0
	_opponent_clock = 38.0
	_found = {
		"draft": {"choices": _pending_draft_choices, "time_limit": 8.0},
		"lives": 3,
		"clock": 60.0,
	}
	_found["total_questions"] = 7
	_question = {
		"index": 2,
		"text": "Quelle est la capitale de la France ?",
		"choices": ["Lyon", "Paris", "Marseille", "Lille"],
		"time_limit": 10.0,
	}
	_question_limit = 10.0
	_question_left = 7.5
	_revealed = false
	_answered_index = -1
	_over = {
		"won": true,
		"draw": false,
		"friendly": false,
		"my_score": 420,
		"opponent_score": 380,
		"trophy_delta": 18,
		"xp": 45,
	}
	_xp_gained = 45
	_error_key = "UI_DUEL_ERROR_OFFLINE"


func _debug_install_preview_bar() -> void:
	if _preview_bar != null and is_instance_valid(_preview_bar):
		return
	_preview_bar = HBoxContainer.new()
	_preview_bar.name = "DebugPreviewBar"
	_preview_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_preview_bar.offset_top = -72
	_preview_bar.offset_bottom = -8
	_preview_bar.offset_left = 12
	_preview_bar.offset_right = -12
	_preview_bar.add_theme_constant_override("separation", 6)
	_preview_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_preview_bar)
	_preview_bar.move_to_front()
	var screens := [
		["search", "Search"],
		["matched", "Found"],
		["draft", "Draft"],
		["play", "Play"],
		["over", "Over"],
		["error", "Error"],
	]
	for entry in screens:
		var btn := Button.new()
		btn.text = str(entry[1])
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size.y = 56
		btn.add_theme_font_size_override("font_size", UiScale.font(14))
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, UiStyle.filled(Color(0.08, 0.1, 0.2, 0.92), 14))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			btn.add_theme_color_override(key, Color.WHITE)
		btn.pressed.connect(_debug_show_screen.bind(str(entry[0])))
		_preview_bar.add_child(btn)


func _debug_show_screen(screen_id: String) -> void:
	## Freeze auto-transitions while browsing layouts.
	_matched_left = 9999.0
	_draft_vote = ""
	_draft_reveal_holding = false
	_awaiting_draft_hold = false
	_pending_question = {}
	var rebuild := func() -> void:
		match screen_id:
			"search":
				_state = State.SEARCHING
				_set_page_bg_mode()
				_build_search()
			"matched":
				_state = State.MATCHED
				_build_matched()
			"draft":
				_state = State.DRAFT
				_draft_left = 8.0
				_build_draft(_pending_draft_choices)
			"play":
				_state = State.PLAYING
				_category = DEBUG_PREVIEW_CATEGORIES[_preview_category_i % DEBUG_PREVIEW_CATEGORIES.size()]
				_preview_category_i += 1
				_mode = DEBUG_PREVIEW_MODES[_preview_mode_i % DEBUG_PREVIEW_MODES.size()]
				_preview_mode_i += 1
				match _mode:
					"survival":
						_accent = UiTokens.MODE_ACCENTS[GameManager.Mode.SURVIVAL]
					"time_attack":
						_accent = UiTokens.MODE_ACCENTS[GameManager.Mode.TIME_ATTACK]
					_:
						_accent = UiTokens.MODE_ACCENTS[GameManager.Mode.CLASSIC]
				_build_playing()
				_show_question()
			"over":
				_state = State.OVER
				_build_over()
			"error":
				_state = State.ERROR
				_build_error()
		if _preview_bar != null and is_instance_valid(_preview_bar):
			_preview_bar.move_to_front()
	## Soft fade when flipping preview pages (same feel as search → found).
	if _body.get_child_count() > 0:
		_fade_rebuild(rebuild)
	else:
		rebuild.call()


func _fade_rebuild(rebuild: Callable) -> void:
	if _page_fade != null and is_instance_valid(_page_fade):
		_page_fade.kill()
	_page_fade = create_tween()
	_page_fade.tween_property(_margin, "modulate:a", 0.0, PAGE_FADE_OUT)
	_page_fade.tween_callback(func() -> void:
		rebuild.call()
		_margin.modulate.a = 0.0
	)
	_page_fade.tween_property(_margin, "modulate:a", 1.0, PAGE_FADE_IN)


func _apply_safe_area() -> void:
	_margin.add_theme_constant_override("margin_left", 20)
	_margin.add_theme_constant_override("margin_right", 20)
	_margin.add_theme_constant_override("margin_top", 20 + int(SafeArea.top))
	var bottom := 20 + int(SafeArea.bottom)
	if DEBUG_PREVIEW_FLOW:
		bottom += 72
	_margin.add_theme_constant_override("margin_bottom", bottom)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _state in [State.SEARCHING, State.OVER, State.ERROR]:
		_leave()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match _state:
		State.MATCHED:
			if DEBUG_PREVIEW_FLOW:
				pass
			elif _matched_left > 0.0:
				_matched_left = maxf(_matched_left - delta, 0.0)
				if _matched_left <= 0.0:
					_enter_draft()
		State.DRAFT:
			if DEBUG_PREVIEW_FLOW:
				pass
			elif _draft_left > 0.0 and _draft_vote.is_empty():
				_draft_left = maxf(_draft_left - delta, 0.0)
				_set_timer_ratio(_draft_left / float((_found.get("draft", {}) as Dictionary).get("time_limit", 8.0)))
		State.PLAYING:
			if DEBUG_PREVIEW_FLOW:
				return
			if _reading and _read_left > 0.0:
				_read_left = maxf(_read_left - delta, 0.0)
				_set_timer_ratio(_read_left / _read_total)
			if not _revealed and _question_left > 0.0:
				_question_left = maxf(_question_left - delta, 0.0)
				_set_timer_ratio(_question_left / maxf(_question_limit, 0.01))
				if _mode == "time_attack":
					## Match server grace: show 0 only when the window is really closed.
					var display_clock := maxf(_question_left - ANSWER_GRACE_SECONDS, 0.0)
					_my_clock = display_clock
					_refresh_header()
					if display_clock <= 0.0 and _answered_index < 0:
						for button in _answer_buttons:
							button.disabled = true


# --- Flow -------------------------------------------------------------------

func _start_search() -> void:
	_state = State.SEARCHING
	_found = {}
	_over = {}
	_category = ""
	_my_score = 0
	_opponent_score = 0
	_set_page_bg_mode()
	if not DEBUG_PREVIEW_FLOW:
		if _friend_challenge_id.is_empty():
			NetworkManager.start_live_matchmaking("", _mode)
		else:
			NetworkManager.start_friend_match(_friend_challenge_id)
	_build_search()
	if not _friend_challenge_id.is_empty() and not DEBUG_PREVIEW_FLOW:
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
	## Jokers only in friend duels (the server sends none in ranked and refuses them anyway).
	var stock: Variant = data.get("jokers", {})
	_jokers = stock if typeof(stock) == TYPE_DICTIONARY and bool(data.get("friendly", false)) else {}
	_jokers_used = {}
	AudioManager.play("correct")
	var draft: Variant = data.get("draft")
	if typeof(draft) == TYPE_DICTIONARY and not (draft.get("choices", []) as Array).is_empty():
		_pending_draft_choices = draft.get("choices", [])
		_draft_vote = ""
		## Chrono starts only once the draft page is shown — not during the VS beat.
		_draft_left = 0.0
		_draft_reveal_holding = false
		_awaiting_draft_hold = false
		_pending_question = {}
		_state = State.MATCHED
		_matched_left = MATCHED_SECONDS
		_fade_rebuild(_build_matched)


func _enter_draft() -> void:
	if _state != State.MATCHED:
		return
	_state = State.DRAFT
	var draft: Dictionary = _found.get("draft", {}) as Dictionary
	_draft_left = float(draft.get("time_limit", 8.0))
	_build_draft(_pending_draft_choices)


func _on_draft_vote(category_id: String) -> void:
	if _state != State.DRAFT or not _draft_vote.is_empty():
		return
	_draft_vote = category_id
	AudioManager.play("click")
	if not DEBUG_PREVIEW_FLOW:
		NetworkManager.send_draft_vote(category_id)
	_style_draft_tiles(category_id, "", "")
	_feedback("UI_DUEL_DRAFT_WAITING")


## Roulette over the voted tiles (or all three), landing on the server's pick.
func _on_draft_result(data: Dictionary) -> void:
	_category = str(data.get("category", ""))
	_draft_left = 0.0
	_awaiting_draft_hold = true
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
		_hold_draft_result()
	)


## Let the landed category sit a beat before the first question replaces the draft.
func _hold_draft_result() -> void:
	_draft_reveal_holding = true
	await get_tree().create_timer(DRAFT_RESULT_HOLD).timeout
	if not is_inside_tree():
		return
	_draft_reveal_holding = false
	_awaiting_draft_hold = false
	if not _pending_question.is_empty():
		var queued: Dictionary = _pending_question
		_pending_question = {}
		_begin_playing(queued)


func _on_match_start(data: Dictionary) -> void:
	_category = str(data.get("category", _category))


func _on_question(data: Dictionary) -> void:
	## Stay on the draft reveal until the hold finishes.
	if _awaiting_draft_hold or _draft_reveal_holding:
		_pending_question = data
		return
	_begin_playing(data)


func _begin_playing(data: Dictionary) -> void:
	_question = data
	_revealed = false
	_answered_index = -1
	_question_limit = float(data.get("time_limit", 10.0))
	_question_left = _question_limit
	if _mode == "time_attack":
		var limit := float(data.get("time_limit", _question_limit))
		var budget := float(data.get("clock", limit))
		## Server may grant at least 5 s per question even when the budget is lower.
		_my_clock = maxf(budget, limit)
		_question_limit = limit + ANSWER_GRACE_SECONDS
		_question_left = _question_limit
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
	_timer_fill.add_theme_stylebox_override("panel", _timer_fill_style(UiTokens.PODIUM_GOLD))
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
	_tile_badge_discs.clear()
	_tile_letters.clear()
	_tile_texts.clear()
	_tile_markers.clear()
	_draft_tiles.clear()
	_joker_buttons.clear()
	_timer_fill = null
	_feedback_label = null
	_my_score_label = null
	_opponent_score_label = null
	_my_status_label = null
	_opponent_status_label = null
	_opponent_badge = null


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

	_body.alignment = BoxContainer.ALIGNMENT_CENTER
	_body.add_theme_constant_override("separation", 18)

	## “Searching” at top; avatar → pseudo → trophies raised; mode tile lower.
	const AVATAR_SIDE := 360.0
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 12)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(column)

	var title_wrap := MarginContainer.new()
	title_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_wrap.add_theme_constant_override("margin_top", 20)
	column.add_child(title_wrap)
	var title := _title(tr("UI_DUEL_SEARCHING").to_upper(), 46)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("outline_size", 6)
	title_wrap.add_child(title)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.alignment = BoxContainer.ALIGNMENT_BEGIN
	identity.add_theme_constant_override("separation", 12)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## Avatar / pseudo / trophies — spacing under the title.
	var identity_shift := MarginContainer.new()
	identity_shift.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_shift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_shift.add_theme_constant_override("margin_top", 22)
	identity_shift.add_child(identity)
	column.add_child(identity_shift)

	var avatar_wrap := CenterContainer.new()
	avatar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_wrap.add_child(CosmeticsView.avatar(SaveManager.get_cosmetics(), AVATAR_SIDE))
	identity.add_child(avatar_wrap)

	## Pseudo + trophies sit 15 px lower under the avatar.
	var under_avatar := MarginContainer.new()
	under_avatar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	under_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under_avatar.add_theme_constant_override("margin_top", 15)
	identity.add_child(under_avatar)
	var under_col := VBoxContainer.new()
	under_col.add_theme_constant_override("separation", 12)
	under_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	under_avatar.add_child(under_col)

	var name_label := _title(SaveManager.player_name, UiTokens.PSEUDO_FONT_SIZE_HERO)
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(
			SaveManager.player_name,
			UiTokens.PSEUDO_FONT_SIZE_HERO + 6
		))
	)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("outline_size", 6)
	under_col.add_child(name_label)

	var worn_title := CosmeticsView.title_label(
		SaveManager.get_cosmetics(), 24, HORIZONTAL_ALIGNMENT_CENTER, true
	)
	if worn_title != null:
		worn_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		under_col.add_child(worn_title)

	## Keep room for a shop title line between pseudo and trophies.
	var trophy_shift := MarginContainer.new()
	trophy_shift.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trophy_shift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trophy_shift.add_theme_constant_override("margin_top", 22)
	trophy_shift.add_child(_search_trophy_block())
	under_col.add_child(trophy_shift)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var mode_shift := MarginContainer.new()
	mode_shift.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_shift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mode_shift.add_theme_constant_override("margin_top", -130)
	mode_shift.add_theme_constant_override("margin_bottom", 130)
	mode_shift.add_child(_mode_aurore_tile(_mode))
	column.add_child(mode_shift)

	var cancel := _search_cancel_tile()
	cancel.pressed.connect(_leave)
	_body.add_child(cancel)


## VS beat between matchmaking and the category vote — brand navy, stacked heroes.
func _build_matched() -> void:
	_clear()
	_set_page_bg_brand()
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_theme_constant_override("separation", 12)

	## Same header level / size as “Recherche d'un adversaire”.
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_BEGIN
	column.add_theme_constant_override("separation", 16)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(column)

	var title_wrap := MarginContainer.new()
	title_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_wrap.add_theme_constant_override("margin_top", 20)
	column.add_child(title_wrap)
	var title := _title(tr("UI_DUEL_MATCH_FOUND").to_upper(), 46)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	title.add_theme_constant_override("outline_size", 6)
	title_wrap.add_child(title)

	## Heroes fill every leftover pixel under the title (page margins already on `_margin`).
	column.add_child(_matched_hero_stack())


## Full-width hero cards stacked with a tight VS strip between them.
func _matched_hero_stack() -> Control:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE

	stack.add_child(_matched_hero_card(
		SaveManager.player_name,
		SaveManager.get_cosmetics(),
		"🏆 %d" % _account_trophies(),
		_accent
	))

	var vs := Label.new()
	vs.text = "VS"
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vs.add_theme_font_size_override("font_size", UiScale.font(32))
	vs.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	vs.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	vs.add_theme_constant_override("outline_size", 4)
	stack.add_child(vs)

	stack.add_child(_matched_hero_card(
		_opponent_name,
		_opponent_cosmetics,
		"🏆 %d" % _opponent_trophies
	))
	return stack


## Large banner hero — expands to share remaining height with its twin.
func _matched_hero_card(
	display_name: String,
	cosmetics: Dictionary,
	value_text: String,
	highlight: Color = Color(0, 0, 0, 0)
) -> Control:
	const AVATAR := 180.0
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0, 0, 0, 0)
	border.set_corner_radius_all(22)
	if highlight.a > 0.02:
		border.set_border_width_all(3)
		border.border_color = highlight
	card.add_theme_stylebox_override("panel", border)

	var back := CosmeticsView.banner(str(cosmetics.get("banner", "")), Vector2.ZERO, 22)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.modulate = Color(0.82, 0.82, 0.86)
	card.add_child(back)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var avatar_box := CenterContainer.new()
	avatar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(avatar_box)
	avatar_box.add_child(CosmeticsView.avatar(cosmetics, AVATAR))

	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(display_name, UiTokens.PSEUDO_FONT_SIZE_HERO))
	)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("outline_size", 5)
	column.add_child(name_label)

	var worn := CosmeticsView.title_label(cosmetics, 20, HORIZONTAL_ALIGNMENT_CENTER, true)
	if worn != null:
		column.add_child(worn)

	if not value_text.is_empty():
		var value := Label.new()
		value.text = value_text
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", UiScale.font(30))
		value.add_theme_color_override("font_color", Color.WHITE)
		value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		value.add_theme_constant_override("outline_size", 4)
		column.add_child(value)
	return card


func _build_draft(choices: Array) -> void:
	_clear()
	## Same brand navy canvas as the matched / search-adjacent screens.
	_set_page_bg_brand()
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_child(_face_off("🏆 %d" % _account_trophies(), "🏆 %d" % _opponent_trophies))
	_body.add_child(_title(tr("UI_DUEL_DRAFT_TITLE"), 26))
	_body.add_child(_timer_bar())
	_set_timer_ratio(1.0)
	## Unique aurora per offered category (same approach as category select).
	var accents: Array = []
	for raw in choices:
		accents.append(UiTokens.accent_for_category(str(raw)))
	var themes := AuroreTile.themes_closest_unique(accents)
	## The three choices stack as wide tiles that share the rest of the screen height.
	for i in range(choices.size()):
		var category_id := str(choices[i])
		var accent: Color = accents[i]
		var theme := str(themes[i]) if i < themes.size() else AuroreTile.theme_closest_to(accent)
		var tile := Button.new()
		tile.custom_minimum_size.y = 150
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.focus_mode = Control.FOCUS_NONE
		tile.clip_contents = true
		tile.set_meta("accent", accent)
		tile.pressed.connect(_on_draft_vote.bind(category_id))
		var chrome := _draft_aurore_chrome()
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			tile.add_theme_stylebox_override(state, chrome)
		var bg := AuroreTile.new()
		bg.name = "AuroreFill"
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg.aurore_theme = theme
		tile.add_child(bg)
		var pad := MarginContainer.new()
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.add_theme_constant_override("margin_left", 24)
		pad.add_theme_constant_override("margin_right", 24)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(pad)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 22)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_child(row)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(130, 130)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = GameAssets.category_texture(category_id)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.alignment = BoxContainer.ALIGNMENT_CENTER
		column.add_theme_constant_override("separation", 6)
		column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(column)
		var name_label := Label.new()
		name_label.text = _category_name(category_id)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", UiScale.font(26))
		name_label.add_theme_color_override("font_color", Color.WHITE)
		column.add_child(name_label)
		var votes := Label.new()
		votes.name = "Votes"
		votes.add_theme_font_size_override("font_size", UiScale.font(16))
		votes.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		column.add_child(votes)
		## Ring drawn above the aurore wash so the roulette contour stays readable.
		var ring := Panel.new()
		ring.name = "HighlightRing"
		ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_theme_stylebox_override("panel", _draft_highlight_ring(false))
		tile.add_child(ring)
		_body.add_child(tile)
		_draft_tiles[category_id] = tile
	_feedback_label = _subtitle("")
	_body.add_child(_feedback_label)
	_style_draft_tiles("", "", "")


## Transparent chrome so AuroreTile shows through.
func _draft_aurore_chrome() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(20)
	return style


## White contour for the roulette — applied on HighlightRing above the aurore.
func _draft_highlight_ring(lit: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(20)
	if lit:
		style.set_border_width_all(7)
		style.border_color = Color.WHITE
	else:
		style.set_border_width_all(0)
	return style


func _style_draft_tiles(highlight: String, mine: String, theirs: String) -> void:
	for key in _draft_tiles:
		var category_id := str(key)
		var tile: Button = _draft_tiles[key]
		var lit := category_id == highlight
		var ring := tile.get_node_or_null("HighlightRing") as Panel
		if ring != null:
			ring.add_theme_stylebox_override("panel", _draft_highlight_ring(lit))
			ring.visible = true
			ring.move_to_front()
		var bg := tile.get_node_or_null("AuroreFill") as AuroreTile
		if bg != null:
			## Roulette / pick: keep the lit tile bright, soften the others.
			if highlight.is_empty():
				bg.modulate = Color.WHITE
			else:
				bg.modulate = Color.WHITE if lit else Color(1, 1, 1, 0.55)
		tile.disabled = not _draft_vote.is_empty() or _draft_left <= 0.0
		var votes := tile.find_child("Votes", true, false) as Label
		if votes != null:
			var tags: Array[String] = []
			if category_id == mine:
				tags.append(tr("UI_DUEL_VOTE_YOU"))
			if category_id == theirs:
				tags.append(tr("UI_DUEL_VOTE_OPPONENT"))
			votes.text = " · ".join(tags)
			## Hidden while empty, so the category name stays centred on the icon.
			votes.visible = not tags.is_empty()


func _build_playing() -> void:
	_clear()
	_set_page_bg_brand()
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_theme_constant_override("separation", 14)
	_body.add_child(_play_face_off())
	_body.add_child(_timer_bar())

	_question_card = PanelContainer.new()
	_question_card.clip_contents = true
	var question_chrome := StyleBoxFlat.new()
	question_chrome.bg_color = Color(0, 0, 0, 0)
	question_chrome.set_corner_radius_all(20)
	_question_card.add_theme_stylebox_override("panel", question_chrome)
	_question_card.custom_minimum_size.y = 280
	## Card and answer tiles grow to fill the screen height (no empty band at the bottom).
	_question_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_question_card.size_flags_stretch_ratio = 1.6
	_body.add_child(_question_card)
	## Mode aurora wash (ocean / lave / jaune) behind the question copy.
	var question_bg := AuroreTile.new()
	question_bg.name = "AuroreFill"
	question_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	question_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	question_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	question_bg.aurore_theme = _mode_aurore_theme(_mode)
	_question_card.add_child(question_bg)
	var question_pad := MarginContainer.new()
	question_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		question_pad.add_theme_constant_override("margin_" + side, 16)
	_question_card.add_child(question_pad)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	question_pad.add_child(column)
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
	tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	## Nested discs (ring + white core) read sharper than a StyleBox border circle.
	const BADGE := 48.0
	const RING := 4
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(BADGE, BADGE)
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge)
	var ring_pad := MarginContainer.new()
	ring_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		ring_pad.add_theme_constant_override("margin_" + side, RING)
	badge.add_child(ring_pad)
	var disc := PanelContainer.new()
	disc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	disc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_pad.add_child(disc)
	var letter := Label.new()
	letter.text = ["A", "B", "C", "D"][index]
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", UiScale.font(18))
	disc.add_child(letter)
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
	_tile_badge_discs.append(disc)
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
		_timer_fill.add_theme_stylebox_override("panel", _timer_fill_style(_accent))
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
	var title := CosmeticsView.title_label(cosmetics, 12, align, true)
	if title != null:
		info.add_child(title)
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
	match _mode:
		"survival":
			_my_score_label.text = "%d · %s" % [_my_score, _hearts(_my_lives)]
			_opponent_score_label.text = "%d · %s" % [_opponent_score, _hearts(_opponent_lives)]
			var emoji_font := UiFonts.emoji_font()
			if emoji_font != null:
				_my_score_label.add_theme_font_override("font", emoji_font)
				_opponent_score_label.add_theme_font_override("font", emoji_font)
		"time_attack":
			_my_score_label.text = "%d · %d s" % [_my_score, ceili(_my_clock)]
			_opponent_score_label.text = "%d · %d s" % [_opponent_score, ceili(_opponent_clock)]
		_:
			_my_score_label.text = str(_my_score)
			_opponent_score_label.text = str(_opponent_score)


func _hearts(lives: int) -> String:
	var total := int(_found.get("lives", 3))
	return "❤️".repeat(maxi(lives, 0)) + "🖤".repeat(maxi(total - maxi(lives, 0), 0))


func _build_over() -> void:
	_clear()
	_set_page_bg_mode()
	_body.alignment = BoxContainer.ALIGNMENT_BEGIN
	var won := bool(_over.get("won", false))
	var draw := bool(_over.get("draw", false))
	var friendly := bool(_over.get("friendly", false))
	var mood := UiTokens.PODIUM_GOLD if won else (Color(0.75, 0.82, 1.0, 1) if draw else Color(1.0, 0.5, 0.5, 1))

	_body.add_child(_spacer())
	var key := "UI_DUEL_DRAW" if draw else ("UI_DUEL_WIN" if won else "UI_DUEL_LOSS")
	var title := _title(tr(key), 58)
	title.add_theme_color_override("font_color", mood)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.35))
	title.add_theme_constant_override("outline_size", 8)
	_body.add_child(title)
	_body.add_child(_subtitle("%s · %s" % [_category_name(_category), _mode_name()]))
	var face := _face_off(str(_my_score), str(_opponent_score), UiTokens.PODIUM_GOLD if won else Color(0, 0, 0, 0))
	_body.add_child(face)

	## Rewards card: one row per gain, revealed one after the other.
	var card := PanelContainer.new()
	var card_style := UiStyle.filled(Color(0, 0, 0, 0.26), 24)
	card_style.content_margin_left = 22
	card_style.content_margin_right = 22
	card_style.content_margin_top = 16
	card_style.content_margin_bottom = 16
	card.add_theme_stylebox_override("panel", card_style)
	_body.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)
	if friendly:
		var rivalry := SaveManager.get_friend_rivalry(str(_over.get("opponent_id", "")))
		rows.add_child(_reward_row("🤝", tr("UI_DUEL_REWARD_FRIENDLY"),
			"%d - %d" % [int(rivalry.get("wins", 0)), int(rivalry.get("losses", 0))],
			Color.WHITE, tr("UI_DUEL_REWARD_FRIENDLY_HINT")))
	else:
		var delta := int(_over.get("trophy_delta", 0))
		var detail := "%s %d" % [tr("UI_DUEL_TOTAL"), int(_over.get("trophies", SaveManager.trophies))]
		var bonus := int(_over.get("trophy_streak_bonus", 0)) + int(_over.get("trophy_loss_consolation", 0))
		if bonus > 0:
			detail += "  ·  " + tr("UI_DUEL_REWARD_STREAK").format({"bonus": bonus})
		rows.add_child(_reward_row("🏆", tr("UI_DUEL_REWARD_TROPHIES"), "%s%d" % ["+" if delta > 0 else "", delta],
			UiTokens.FEEDBACK_CORRECT if delta > 0 else (UiTokens.FEEDBACK_WRONG if delta < 0 else Color.WHITE), detail))
	rows.add_child(_reward_row("⭐", tr("UI_DUEL_REWARD_XP"), "+%d" % _xp_gained, Color(0.55, 0.85, 1.0, 1), ""))
	## Coins are credited by the server (shop.record_duel); the balance shown is the server's.
	var coins := int(_over.get("coins_gained", 0))
	if coins > 0:
		var coins_detail := "%s %d" % [tr("UI_DUEL_TOTAL"), int(_over.get("coins", SaveManager.coins))]
		var league_coins := int(_over.get("league_coins", 0))
		if league_coins > 0:
			coins_detail += "  ·  " + tr("UI_DUEL_REWARD_LEAGUE").format({"bonus": league_coins})
		rows.add_child(_reward_row("🧠", tr("UI_DUEL_REWARD_COINS"), "+%d" % coins, Color(0.97, 0.78, 0.26, 1), coins_detail))
	var pass_xp := int(_over.get("pass_xp", 0))
	if pass_xp > 0:
		rows.add_child(_reward_row("🎟", tr("UI_DUEL_REWARD_PASS"), "+%d" % pass_xp, Color(1.0, 0.78, 0.2, 1), ""))
		NetworkManager.fetch_pass()

	_body.add_child(_spacer())
	var back := _button(tr("UI_BACK"), Color(1, 1, 1, 0.14), Color.WHITE)
	back.pressed.connect(_leave)
	_body.add_child(back)

	## Title pops, then the reward rows slide in one by one.
	title.pivot_offset = Vector2(PAGE_WIDTH * 0.5, 40)
	title.scale = Vector2(0.6, 0.6)
	title.modulate.a = 0.0
	var tween := _track(create_tween())
	tween.tween_property(title, "modulate:a", 1.0, 0.18)
	tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for row in rows.get_children():
		(row as Control).modulate.a = 0.0
		tween.tween_property(row, "modulate:a", 1.0, 0.22).set_delay(0.08)
		tween.tween_callback(AudioManager.play.bind("click"))


## One gain on the end screen: icon, label (+ small detail), value on the right.
func _reward_row(icon: String, label_text: String, value: String, value_color: Color, detail: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var badge := Label.new()
	badge.text = icon
	badge.custom_minimum_size = Vector2(44, 44)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", UiScale.font(26))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		badge.add_theme_font_override("font", emoji_font)
	row.add_child(badge)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.add_theme_font_size_override("font_size", UiScale.font(19))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	texts.add_child(name_label)
	if not detail.is_empty():
		var detail_label := Label.new()
		detail_label.text = detail
		detail_label.add_theme_font_size_override("font_size", UiScale.font(14))
		detail_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		texts.add_child(detail_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.add_theme_font_size_override("font_size", UiScale.font(28))
	value_label.add_theme_color_override("font_color", value_color)
	row.add_child(value_label)
	return row


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _build_error() -> void:
	_clear()
	_set_page_bg_mode()
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


## Same face-off tiles as draft (fixed size); scores replace trophies.
func _play_face_off() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _face_off(str(_my_score), str(_opponent_score), _accent)
	var mine := row.get_child(0) as Control
	var theirs := row.get_child(2) as Control
	_my_score_label = mine.get_meta("value") as Label if mine.has_meta("value") else null
	_opponent_score_label = theirs.get_meta("value") as Label if theirs.has_meta("value") else null
	_my_status_label = null
	_opponent_status_label = null
	col.add_child(row)
	## Fixed-height status slot under the tiles so “prêt / a répondu” never reflows the page.
	var badge_slot := Control.new()
	badge_slot.custom_minimum_size.y = UiScale.font(22)
	badge_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(badge_slot)
	_opponent_badge = Label.new()
	_opponent_badge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_opponent_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_opponent_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_opponent_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_opponent_badge.add_theme_font_size_override("font_size", UiScale.font(13))
	_opponent_badge.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	_opponent_badge.modulate.a = 0.0
	badge_slot.add_child(_opponent_badge)
	return col


func _timer_bar() -> Control:
	_timer_track = Panel.new()
	_timer_track.custom_minimum_size.y = 14
	_timer_track.add_theme_stylebox_override("panel", _timer_fill_style(Color(1, 1, 1, 0.14)))
	_timer_fill = Panel.new()
	_timer_fill.add_theme_stylebox_override("panel", _timer_fill_style(_accent))
	_timer_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_timer_track.add_child(_timer_fill)
	_set_timer_ratio(1.0)
	return _timer_track


## Flat bar chip — no UiStyle.filled coloured glow.
func _timer_fill_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(7)
	return style


func _set_timer_ratio(ratio: float) -> void:
	if _timer_fill == null or not is_instance_valid(_timer_fill):
		return
	_timer_fill.anchor_right = clampf(ratio, 0.0, 1.0)
	_timer_fill.offset_right = 0


func _style_answer(index: int, look: String) -> void:
	var tile := _answer_buttons[index]
	## White answer tiles; mode tint on the letter chip / hover ring / pick.
	var fill := Color(1, 1, 1, 0.96)
	var ink := UiTokens.INK
	var badge_fill := Color.WHITE
	var badge_ink := _accent.darkened(0.12)
	var border := Color(0, 0, 0, 0)
	tile.modulate.a = 1.0
	match look:
		"picked":
			fill = _accent
			ink = Color.WHITE
			badge_fill = Color.WHITE
			badge_ink = _accent.darkened(0.2)
		"correct":
			fill = UiTokens.FEEDBACK_CORRECT
			ink = Color.WHITE
			badge_fill = Color.WHITE
			badge_ink = UiTokens.FEEDBACK_CORRECT.darkened(0.25)
			border = Color(1, 1, 1, 0.9)
		"wrong":
			fill = UiTokens.FEEDBACK_WRONG
			ink = Color.WHITE
			badge_fill = Color.WHITE
			badge_ink = UiTokens.FEEDBACK_WRONG.darkened(0.2)
		"dim":
			tile.modulate.a = 0.45
	var style := UiStyle.filled(fill, 20)
	## Soft drop only — no coloured glow around the tiles.
	style.shadow_color = Color(0, 0, 0, 0.2)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0, 2)
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
	## Outer disc = mode ring; inner disc = white core (no soft StyleBox border).
	var ring_color := _accent
	if look == "correct":
		ring_color = UiTokens.FEEDBACK_CORRECT
	elif look == "wrong":
		ring_color = UiTokens.FEEDBACK_WRONG
	elif look == "picked":
		ring_color = _accent
	_tile_badges[index].add_theme_stylebox_override("panel", _circle_style(ring_color, 24))
	_tile_badge_discs[index].add_theme_stylebox_override("panel", _circle_style(badge_fill, 20))


## Sharp anti-aliased disc — no shadow / border glow.
func _circle_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(0)
	style.shadow_size = 0
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	return style


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
	## Survival / time attack keep lives or clock on the same line — just pulse.
	if _mode != "classic":
		_refresh_header()
		_pulse(label, 1.25)
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


## Untyped on purpose: a late opponent message can arrive after a rebuild freed the
## label, and a typed Label argument would fail before the validity check runs.
func _set_badge(target: Variant, text: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	var label := target as Label
	label.text = text
	## Keep the reserved slot; only fade the copy so layout never jumps.
	label.modulate.a = 0.0 if text.is_empty() else 1.0
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


## Cancel tile — fruits aurora (red/magenta), not a duel-mode wash (ocean/lave/jaune).
func _search_cancel_tile() -> Button:
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 78
	button.focus_mode = Control.FOCUS_NONE
	button.text = ""
	var chrome := StyleBoxFlat.new()
	chrome.bg_color = Color(0, 0, 0, 0)
	chrome.set_corner_radius_all(22)
	chrome.content_margin_left = 0
	chrome.content_margin_right = 0
	chrome.content_margin_top = 0
	chrome.content_margin_bottom = 0
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, chrome)

	var bg := AuroreTile.new()
	bg.name = "AuroreFill"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.aurore_theme = "fruits"
	button.add_child(bg)

	var label := Label.new()
	label.text = tr("UI_DUEL_CANCEL")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiScale.font(22))
	label.add_theme_color_override("font_color", Color.WHITE)
	button.add_child(label)
	PressScaleUtil.wire(button, self)
	return button


func _mode_name() -> String:
	match _mode:
		"survival":
			return tr("UI_MODE_SURVIVAL")
		"time_attack":
			return tr("UI_MODE_TIME_ATTACK")
	return tr("UI_MODE_CLASSIC")


## Trophy count shown on the account (same source as Quiz / Profil league tiles).
func _account_trophies() -> int:
	var snapshot: Dictionary = ProfileSnapshot.build_full(LocaleManager.get_content_locale())
	var ranking: Dictionary = snapshot.get("ranking", {})
	return int(ranking.get("points", SaveManager.trophies))


## Trophy chip under the avatar — larger than the old plain label.
func _search_trophy_block() -> Control:
	var wrap := CenterContainer.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.38)
	style.set_corner_radius_all(28)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.22)
	panel.add_theme_stylebox_override("panel", style)
	wrap.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var emoji := Label.new()
	emoji.text = "🏆"
	emoji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emoji.add_theme_font_size_override("font_size", UiScale.font(36))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		emoji.add_theme_font_override("font", emoji_font)
	row.add_child(emoji)

	var value := Label.new()
	value.text = str(_account_trophies())
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", UiScale.font(36))
	value.add_theme_color_override("font_color", Color.WHITE)
	value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	value.add_theme_constant_override("outline_size", 4)
	row.add_child(value)
	return wrap


func _mode_aurore_theme(mode: String) -> String:
	match mode:
		"survival":
			return "lave"
		"time_attack":
			return "jaune"
		_:
			return "ocean"


## Mode indicator — same size / layout as Quiz `_mode_tile` (ocean / lave / jaune).
func _mode_aurore_tile(mode: String) -> Control:
	var key := "UI_MODE_CLASSIC"
	var hint_key := "UI_DUEL_TILE_CLASSIC_HINT"
	var icon := "🎯"
	match mode:
		"survival":
			key = "UI_MODE_SURVIVAL"
			hint_key = "UI_DUEL_TILE_SURVIVAL_HINT"
			icon = "❤️"
		"time_attack":
			key = "UI_MODE_TIME_ATTACK"
			hint_key = "UI_DUEL_TILE_TIME_ATTACK_HINT"
			icon = "⏱️"

	var tile := PanelContainer.new()
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.custom_minimum_size.y = 156
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chrome := StyleBoxFlat.new()
	chrome.bg_color = Color(0, 0, 0, 0)
	chrome.set_corner_radius_all(22)
	chrome.content_margin_left = 0
	chrome.content_margin_right = 0
	chrome.content_margin_top = 0
	chrome.content_margin_bottom = 0
	tile.add_theme_stylebox_override("panel", chrome)

	var bg := AuroreTile.new()
	bg.name = "AuroreFill"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.aurore_theme = _mode_aurore_theme(mode)
	tile.add_child(bg)

	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 18)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 16)
	tile.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_child(row)

	const ICON := 88.0
	var icon_slot := Control.new()
	icon_slot.custom_minimum_size = Vector2(ICON, ICON)
	icon_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_slot)
	var icon_bg := Panel.new()
	icon_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(1, 1, 1, 0.18)
	icon_style.set_corner_radius_all(int(ICON * 0.5))
	icon_bg.add_theme_stylebox_override("panel", icon_style)
	icon_slot.add_child(icon_bg)
	var emoji := Label.new()
	emoji.text = icon
	emoji.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emoji.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emoji.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emoji.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emoji.add_theme_font_size_override("font_size", UiScale.font(38))
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null:
		emoji.add_theme_font_override("font", emoji_font)
	icon_slot.add_child(emoji)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 6)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(texts)

	var name_label := Label.new()
	name_label.text = tr(key).to_upper()
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", UiScale.font(28))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	texts.add_child(name_label)

	var hint := Label.new()
	hint.text = tr(hint_key)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.max_lines_visible = 2
	hint.add_theme_font_size_override("font_size", UiScale.font(17))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.78))
	texts.add_child(hint)
	return tile


func _category_name(category_id: String) -> String:
	return str(_category_names.get(category_id, category_id))
