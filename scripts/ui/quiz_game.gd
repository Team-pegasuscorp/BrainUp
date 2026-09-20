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


func _ready() -> void:
	if not GameManager.has_questions():
		ScenePaths.go_to_shell(get_tree(), ScenePaths.Tab.QUIZ)
		return

	SafeArea.fit_margins($MarginContainer)
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


func _category_name(category_id: String) -> String:
	for category in QuestionLoaderScript.get_categories(LocaleManager.get_content_locale()):
		if str(category.get("id", "")) == category_id:
			return str(category.get("name", category_id))
	return category_id


func _process(delta: float) -> void:
	if not accepting_input or _timer_label == null:
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


## Bar and number turn amber then red as time runs out.
func _update_timer_visuals() -> void:
	var state := 0
	if time_remaining <= TIMER_DANGER_SECONDS:
		state = 2
	elif time_remaining <= TIMER_WARN_SECONDS:
		state = 1
	if state != _timer_state:
		_timer_state = state
		var color := [_accent, UiTokens.FEEDBACK_TIMEOUT, UiTokens.FEEDBACK_WRONG][state] as Color
		timer_bar.add_theme_stylebox_override("fill", UiStyle.progress_fill(color))
		_timer_label.add_theme_color_override("font_color", color)
	_timer_label.text = str(maxi(ceili(time_remaining), 0))


func _show_current_question() -> void:
	_reset_answer_visuals()
	var question: Dictionary = GameManager.get_current_question()
	if question.is_empty():
		_finish_quiz()
		return

	progress_label.text = "%s %s" % [tr("UI_QUESTION"), GameManager.get_progress_label()]
	score_label.text = "%s: %d" % [tr("UI_SCORE"), GameManager.score]
	combo_label.text = "%s: x%d" % [tr("UI_COMBO"), max(GameManager.combo, 1)]
	question_label.text = question.get("text", "")
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
	_last_tick_second = 99
	_timer_state = -1
	question_start_time = Time.get_ticks_msec() / 1000.0
	timer_bar.value = 100.0
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

	await get_tree().create_timer(1.2).timeout

	if result.get("finished", false):
		_finish_quiz()
	else:
		_show_current_question()


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
	_reset_answer_visuals()
	GameManager.finish_round()
	get_tree().change_scene_to_file(ScenePaths.RESULTS)
