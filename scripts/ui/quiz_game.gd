extends Control

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const UiStyle = preload("res://scripts/config/ui_style.gd")
const PressScaleUtil = preload("res://scripts/ui/press_scale.gd")
const ScenePaths = preload("res://scripts/config/scene_paths.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")

const ANSWER_HEIGHT := 92.0
const ANSWER_RADIUS := 24
## Card style margins + inner margin around the question text, per axis.
const QUESTION_PADDING := 68.0
const TIMER_WARN_SECONDS := 5.0
const TIMER_DANGER_SECONDS := 3.0
## Time attack: the shared clock turns amber then red over its last seconds.
const CLOCK_WARN_SECONDS := 15.0
const CLOCK_DANGER_SECONDS := 5.0
## Time attack keeps the pace: short feedback, no explanation.
const TIME_ATTACK_FEEDBACK := 0.35
## Survival: a right answer moves on quickly; mistakes get their explanation.
const SURVIVAL_FEEDBACK := 0.8
## After an answer the card shows the explanation for a reading time that grows with
## its length; a tap anywhere moves on sooner.
const EXPLANATION_DELAY := 0.7
const READ_BASE_SECONDS := 3.0
const READ_SECONDS_PER_CHAR := 0.035
const READ_MIN_SECONDS := 4.0
const READ_MAX_SECONDS := 10.0
## Room kept in the card for the caption above and the hint below the explanation.
const EXPLANATION_CHROME := 76.0

@onready var progress_label: Label = %ProgressLabel
@onready var score_label: Label = %ScoreLabel
@onready var combo_label: Label = %ComboLabel
@onready var question_label: Label = %QuestionLabel
@onready var feedback_label: Label = %FeedbackLabel
@onready var timer_bar: ProgressBar = %TimerBar
@onready var question_panel: PanelContainer = %QuestionPanel
@onready var answers_grid: GridContainer = %AnswersGrid
@onready var header_row: HBoxContainer = $MarginContainer/VBox/HeaderHBox
@onready var answer_buttons: Array[Button] = [
	%AnswerButton1,
	%AnswerButton2,
	%AnswerButton3,
	%AnswerButton4,
]

var time_remaining: float = 0.0
var question_start_time: float = 0.0
var accepting_input: bool = true
var _feedback_tweens: Array[Tween] = []
var _last_tick_second: int = 99
var _accent: Color = UiTokens.ACCENT_QUIZ
var _timer_label: Label
var _timer_state: int = -1
var _explain_caption: Label
var _tap_hint: Label
var _tap_catcher: Control
var _skip_requested: bool = false
var _time_attack: bool = false
var _survival: bool = false
## Time attack's shared clock, running from the first question to the end.
var _clock: float = 0.0
var _clock_over: bool = false
var _finished: bool = false
var _lives_label: Label


func _ready() -> void:
	if not GameManager.has_questions():
		ScenePaths.go_to_shell(get_tree(), ScenePaths.Tab.QUIZ)
		return

	SafeArea.fit_margins($MarginContainer)
	_time_attack = GameManager.mode == GameManager.Mode.TIME_ATTACK
	_survival = GameManager.mode == GameManager.Mode.SURVIVAL
	_clock = GameManager.TIME_ATTACK_SECONDS
	if _survival:
		## Hearts get their own red label in front of "Question N".
		_lives_label = Label.new()
		_lives_label.add_theme_color_override("font_color", UiTokens.FEEDBACK_WRONG)
		_lives_label.add_theme_font_size_override("font_size", UiScale.font(22))
		header_row.add_child(_lives_label)
		header_row.move_child(_lives_label, 0)
	_accent = UiTokens.accent_for_category(GameManager.category_id)
	_build_category_header()

	answers_grid.columns = 1
	answers_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answers_grid.add_theme_constant_override("v_separation", 14)
	for index in range(answer_buttons.size()):
		var button: Button = answer_buttons[index]
		PressScaleUtil.wire(button, self)
		button.pressed.connect(_on_answer_pressed.bind(index))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_FILL
		button.custom_minimum_size = Vector2(0, ANSWER_HEIGHT)
		button.add_theme_font_size_override("font_size", UiScale.font(24))

	timer_bar.custom_minimum_size = Vector2(0, 18)
	timer_bar.add_theme_stylebox_override("background", UiStyle.progress_bg())
	combo_label.add_theme_color_override("font_color", UiTokens.ACCENT_QUIZ)
	for label in [progress_label]:
		label.add_theme_font_size_override("font_size", UiScale.font(18))
	for label in [score_label, combo_label]:
		label.add_theme_font_size_override("font_size", UiScale.font(22))

	question_panel.add_theme_stylebox_override("panel", UiStyle.card(_accent))
	question_label.add_theme_font_size_override("font_size", UiScale.font(32))
	question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	question_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feedback_label.add_theme_font_size_override("font_size", UiScale.font(24))
	_build_explanation_nodes()
	_show_current_question()


## Category icon + name on the left, big countdown on the right.
func _build_category_header() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var category_id := GameManager.category_id
	row.add_child(GameAssets.make_circular_icon_display(GameAssets.category_texture(category_id), "🧠", 56.0))

	var name_label := Label.new()
	name_label.text = _category_name(category_id)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", UiScale.font(26))
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	row.add_child(name_label)

	_timer_label = Label.new()
	_timer_label.custom_minimum_size = Vector2(64, 0)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_timer_label.add_theme_font_size_override("font_size", UiScale.font(44))
	row.add_child(_timer_label)

	var column := header_row.get_parent()
	column.add_child(row)
	column.move_child(row, 0)


## Caption, hint and a full-screen tap catcher, only visible while an explanation is read.
func _build_explanation_nodes() -> void:
	var margin := question_label.get_parent()
	_explain_caption = Label.new()
	_explain_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_explain_caption.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_explain_caption.add_theme_font_size_override("font_size", UiScale.font(16))
	_explain_caption.add_theme_color_override("font_color", _accent)
	_explain_caption.visible = false
	margin.add_child(_explain_caption)

	_tap_hint = Label.new()
	_tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap_hint.size_flags_vertical = Control.SIZE_SHRINK_END
	_tap_hint.add_theme_font_size_override("font_size", UiScale.font(14))
	_tap_hint.add_theme_color_override("font_color", UiTokens.INK_MUTED)
	_tap_hint.visible = false
	margin.add_child(_tap_hint)

	_tap_catcher = Control.new()
	_tap_catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tap_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_catcher.visible = false
	_tap_catcher.gui_input.connect(_on_tap_catcher_input)
	add_child(_tap_catcher)


func _on_tap_catcher_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		_skip_requested = true


func _category_name(category_id: String) -> String:
	for category in QuestionLoaderScript.get_categories(LocaleManager.get_content_locale()):
		if str(category.get("id", "")) == category_id:
			return str(category.get("name", category_id))
	return category_id


func _process(delta: float) -> void:
	if _timer_label == null:
		return
	if _time_attack:
		_process_clock(delta)
		return
	if not accepting_input:
		return

	time_remaining -= delta
	timer_bar.value = (time_remaining / GameManager.QUESTION_TIME_SECONDS) * 100.0
	_update_timer_visuals()

	## Countdown ticks for the last three seconds.
	var whole_seconds := ceili(time_remaining)
	if whole_seconds <= 3 and whole_seconds > 0 and whole_seconds != _last_tick_second:
		_last_tick_second = whole_seconds
		AudioManager.play("tick", 1.0 + float(3 - whole_seconds) * 0.15)
		_pulse(_timer_label, 1.3)

	if time_remaining <= 0.0:
		_submit_answer(-1)


## Time attack: one clock for the whole run, running during feedback too.
func _process_clock(delta: float) -> void:
	if _clock_over:
		return
	_clock -= delta
	timer_bar.value = (maxf(_clock, 0.0) / GameManager.TIME_ATTACK_SECONDS) * 100.0
	_update_timer_visuals()
	var whole_seconds := ceili(_clock)
	if whole_seconds <= 5 and whole_seconds > 0 and whole_seconds != _last_tick_second:
		_last_tick_second = whole_seconds
		AudioManager.play("tick", 1.0 + float(5 - whole_seconds) * 0.1)
		_pulse(_timer_label, 1.3)
	if _clock <= 0.0:
		_clock_over = true
		accepting_input = false
		AudioManager.play("timeout")
		GameManager.end_time_attack()
		_finish_quiz()


## Bar and number turn amber then red as time runs out.
func _update_timer_visuals() -> void:
	var shown := _clock if _time_attack else time_remaining
	var danger := CLOCK_DANGER_SECONDS if _time_attack else TIMER_DANGER_SECONDS
	var warn := CLOCK_WARN_SECONDS if _time_attack else TIMER_WARN_SECONDS
	var state := 0
	if shown <= danger:
		state = 2
	elif shown <= warn:
		state = 1
	if state != _timer_state:
		_timer_state = state
		var color := [_accent, UiTokens.FEEDBACK_TIMEOUT, UiTokens.FEEDBACK_WRONG][state] as Color
		timer_bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(color))
		_timer_label.add_theme_color_override("font_color", color)
	_timer_label.text = str(maxi(ceili(shown), 0))


## "Question 3 / 7"; survival also refreshes the hearts left.
func _progress_text() -> String:
	if _lives_label != null:
		_lives_label.text = "♥".repeat(GameManager.lives) + "♡".repeat(maxi(GameManager.SURVIVAL_LIVES - GameManager.lives, 0)) + " "
	return "%s %s" % [tr("UI_QUESTION"), GameManager.get_progress_label()]


func _show_current_question() -> void:
	_reset_answer_visuals()
	var question: Dictionary = GameManager.get_current_question()
	if question.is_empty():
		_finish_quiz()
		return

	progress_label.text = _progress_text()
	score_label.text = "%s: %d" % [tr("UI_SCORE"), GameManager.score]
	combo_label.text = "%s: x%d" % [tr("UI_COMBO"), max(GameManager.combo, 1)]
	question_label.text = question.get("text", "")
	question_label.modulate.a = 1.0
	_explain_caption.visible = false
	_tap_hint.visible = false
	_timer_state = -1
	feedback_label.text = ""
	feedback_label.modulate = UiTokens.NEUTRAL

	var choices: Array = question.get("choices", [])
	for index in range(answer_buttons.size()):
		var button: Button = answer_buttons[index]
		button.modulate = UiTokens.NEUTRAL
		if index < choices.size():
			button.text = str(choices[index])
			button.visible = true
			button.disabled = false
		else:
			button.visible = false

	time_remaining = GameManager.QUESTION_TIME_SECONDS
	if not _time_attack:
		_last_tick_second = 99
		timer_bar.value = 100.0
	_timer_state = -1
	question_start_time = Time.get_ticks_msec() / 1000.0
	_update_timer_visuals()
	accepting_input = true
	_animate_question_in()
	_fit_texts()


## Question card fades in, then the answers cascade one after another.
func _animate_question_in() -> void:
	question_panel.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	_feedback_tweens.append(tween)
	tween.tween_property(question_panel, "modulate:a", 1.0, 0.22)
	var order := 0
	for button in answer_buttons:
		if not button.visible:
			continue
		button.modulate.a = 0.0
		tween.tween_property(button, "modulate:a", 1.0, 0.2).set_delay(0.1 + float(order) * 0.07)
		order += 1


## The question page never scrolls, so long texts shrink until they fit their box.
func _fit_texts() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	question_label.add_theme_font_size_override("font_size", _largest_fitting(
		question_label.text, question_label,
		question_panel.size.x - QUESTION_PADDING, _question_room(),
		[36, 32, 28, 25, 22, 19, 16]
	))
	for button in answer_buttons:
		if not button.visible:
			continue
		button.add_theme_font_size_override("font_size", _largest_fitting(
			button.text, button,
			button.size.x - 44.0, button.size.y - 20.0,
			[28, 25, 22, 19, 16]
		))


## Height left for the question text once everything else on the page has its space.
## (Measured from the other rows, not from the card: the card grows with its text.)
func _question_room() -> float:
	var frame: MarginContainer = $MarginContainer
	var column: VBoxContainer = $MarginContainer/VBox
	## Screen height minus the frame margins: the column itself can be stretched past
	## the screen when its content overflows, so it cannot be used as the reference.
	var screen_room := size.y - float(frame.get_theme_constant("margin_top") + frame.get_theme_constant("margin_bottom"))
	var used := 0.0
	var rows := 0
	for child in column.get_children():
		if not (child is Control) or not child.visible:
			continue
		rows += 1
		if child != question_panel:
			used += (child as Control).get_combined_minimum_size().y
	used += float(column.get_theme_constant("separation")) * float(maxi(rows - 1, 0))
	## Small safety margin: text metrics and label layout differ by a few pixels.
	return screen_room - used - QUESTION_PADDING - 14.0


## Biggest of `sizes` (base sizes, scaled like the rest of the UI) whose wrapped
## text fits in width x height.
func _largest_fitting(text: String, control: Control, width: float, height: float, sizes: Array) -> int:
	var font := control.get_theme_font("font")
	var spacing := float(control.get_theme_constant("line_spacing"))
	for base in sizes:
		var size := UiScale.font(int(base))
		var measured := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, maxf(width, 1.0), size)
		## Labels add their line spacing between lines; the raw measure does not.
		var lines := maxi(roundi(measured.y / font.get_height(size)), 1)
		if measured.y + spacing * float(lines) <= height:
			return size
	return UiScale.font(int(sizes[sizes.size() - 1]))


func _on_answer_pressed(selected_index: int) -> void:
	if not accepting_input:
		return
	_submit_answer(selected_index)


func _submit_answer(selected_index: int) -> void:
	if not accepting_input:
		return
	accepting_input = false

	for button in answer_buttons:
		button.disabled = true

	var question: Dictionary = GameManager.get_current_question()
	var correct_index: int = int(question.get("correct_index", -1))
	var elapsed: float = (Time.get_ticks_msec() / 1000.0) - question_start_time
	var result: Dictionary = GameManager.submit_answer(selected_index, elapsed)
	_show_feedback(result, selected_index, correct_index)

	if _time_attack:
		if not result.get("is_correct", false):
			_clock -= GameManager.TIME_ATTACK_WRONG_PENALTY
			feedback_label.text = "%s  −%d s" % [tr("UI_WRONG"), int(GameManager.TIME_ATTACK_WRONG_PENALTY)]
			_shake(_timer_label)
		await get_tree().create_timer(TIME_ATTACK_FEEDBACK).timeout
		## The clock may have run out meanwhile and already ended the round.
		if not is_inside_tree() or _clock_over:
			return
	else:
		progress_label.text = _progress_text()
		var explanation := _explanation_for(question)
		## Survival only explains mistakes, so a good run keeps its rhythm.
		if _survival and result.get("is_correct", false):
			explanation = ""
		if explanation.is_empty():
			await get_tree().create_timer(SURVIVAL_FEEDBACK if _survival else 1.2).timeout
		else:
			await get_tree().create_timer(EXPLANATION_DELAY).timeout
			await _read_explanation(explanation)
		if not is_inside_tree():
			return

	if result.get("finished", false):
		_finish_quiz()
	else:
		_show_current_question()


## Old imported questions only say "the correct answer is: X": nothing to learn there.
func _explanation_for(question: Dictionary) -> String:
	var text := str(question.get("explanation", "")).strip_edges()
	for filler in ["The correct answer is", "La bonne réponse est"]:
		if text.begins_with(filler):
			return ""
	return text


## Swaps the question for its explanation and drains the timer bar as a reading
## gauge. Returns when the time is up or the player taps anywhere.
func _read_explanation(text: String) -> void:
	var fade := create_tween()
	_feedback_tweens.append(fade)
	fade.tween_property(question_label, "modulate:a", 0.0, 0.15)
	await fade.finished
	if not is_inside_tree():
		return

	question_label.text = text
	_explain_caption.text = tr("UI_EXPLANATION_TITLE")
	_tap_hint.text = tr("UI_EXPLANATION_TAP")
	_explain_caption.visible = true
	_tap_hint.visible = true
	question_label.add_theme_font_size_override("font_size", _largest_fitting(
		text, question_label,
		question_panel.size.x - QUESTION_PADDING, _question_room() - EXPLANATION_CHROME,
		[28, 25, 22, 19, 16]
	))
	var fade_in := create_tween()
	_feedback_tweens.append(fade_in)
	fade_in.tween_property(question_label, "modulate:a", 1.0, 0.2)

	timer_bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(_accent))
	_timer_label.text = ""
	var duration := clampf(READ_BASE_SECONDS + float(text.length()) * READ_SECONDS_PER_CHAR, READ_MIN_SECONDS, READ_MAX_SECONDS)
	var elapsed := 0.0
	_skip_requested = false
	_tap_catcher.visible = true
	while elapsed < duration and not _skip_requested:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		elapsed += get_process_delta_time()
		timer_bar.value = (1.0 - elapsed / duration) * 100.0
	_tap_catcher.visible = false


func _show_feedback(result: Dictionary, selected_index: int, correct_index: int) -> void:
	if result.get("is_timeout", false):
		feedback_label.text = tr("UI_TIME_UP")
		feedback_label.modulate = UiTokens.FEEDBACK_TIMEOUT
		AudioManager.play("timeout")
	elif result.get("is_correct", false):
		feedback_label.text = "%s +%d" % [tr("UI_CORRECT"), result.get("points", 0)]
		feedback_label.modulate = UiTokens.FEEDBACK_CORRECT
		## Each consecutive hit climbs a little higher (capped at ~an octave).
		AudioManager.play("correct", 1.0 + minf(float(result.get("combo", 1)) - 1.0, 8.0) * 0.06)
	else:
		feedback_label.text = tr("UI_WRONG")
		feedback_label.modulate = UiTokens.FEEDBACK_WRONG
		AudioManager.play("wrong")

	score_label.text = "%s: %d" % [tr("UI_SCORE"), GameManager.score]
	combo_label.text = "%s: x%d" % [tr("UI_COMBO"), max(GameManager.combo, 1)]
	_pulse(score_label, 1.25)

	## Everything that is neither the right answer nor the player's pick fades back.
	for index in range(answer_buttons.size()):
		if index != correct_index and index != selected_index:
			answer_buttons[index].modulate.a = 0.45

	if correct_index >= 0 and correct_index < answer_buttons.size():
		_paint_answer(answer_buttons[correct_index], UiTokens.FEEDBACK_CORRECT)
		_pulse(answer_buttons[correct_index], 1.05)

	if (
		selected_index >= 0
		and selected_index < answer_buttons.size()
		and selected_index != correct_index
	):
		_paint_answer(answer_buttons[selected_index], UiTokens.FEEDBACK_WRONG)
		_shake(answer_buttons[selected_index])


## Every state shares one box so a disabled button never falls back to the theme.
func _style_answer_default(button: Button) -> void:
	var idle := _answer_box(Color.WHITE, Color(0, 0, 0, 0))
	var active := _answer_box(Color.WHITE, _accent)
	button.add_theme_stylebox_override("normal", idle)
	button.add_theme_stylebox_override("disabled", idle)
	button.add_theme_stylebox_override("focus", idle)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("pressed", active)
	_set_answer_text_color(button, UiTokens.INK)


func _paint_answer(button: Button, color: Color) -> void:
	var box := _answer_box(color, Color(0, 0, 0, 0))
	for state in ["normal", "disabled", "focus", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, box)
	_set_answer_text_color(button, Color.WHITE)


func _answer_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := UiStyle.card(_accent, ANSWER_RADIUS)
	box.bg_color = fill
	box.content_margin_left = 22
	box.content_margin_right = 22
	if border.a > 0.0:
		box.set_border_width_all(3)
		box.border_color = border
	return box


func _set_answer_text_color(button: Button, color: Color) -> void:
	for slot in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		button.add_theme_color_override(slot, color)


func _pulse(control: Control, amount: float) -> void:
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	_feedback_tweens.append(tween)
	tween.tween_property(control, "scale", Vector2(amount, amount), 0.09)
	tween.tween_property(control, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _shake(control: Control) -> void:
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	_feedback_tweens.append(tween)
	for angle in [0.025, -0.025, 0.015, -0.015, 0.0]:
		tween.tween_property(control, "rotation", angle, 0.05)


func _reset_answer_visuals() -> void:
	for tween in _feedback_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_feedback_tweens.clear()
	for button in answer_buttons:
		if is_instance_valid(button):
			button.modulate = UiTokens.NEUTRAL
			button.scale = Vector2.ONE
			button.rotation = 0.0
			_style_answer_default(button)
	if _timer_label != null:
		_timer_label.scale = Vector2.ONE
	score_label.scale = Vector2.ONE


func _finish_quiz() -> void:
	## Time attack can end from the clock and from the last answer in the same frame.
	if _finished:
		return
	_finished = true
	_clock_over = true
	_reset_answer_visuals()
	GameManager.finish_round()
	get_tree().change_scene_to_file(ScenePaths.RESULTS)
