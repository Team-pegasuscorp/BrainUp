extends Node

const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScoringSystemScript = preload("res://scripts/quiz/scoring_system.gd")

const QUESTIONS_PER_ROUND: int = 7
const QUESTION_TIME_SECONDS: float = 10.0

## Classic: 7 questions. Survival: go on until the lives run out.
## Time attack: as many answers as possible before a shared clock ends.
enum Mode { CLASSIC, SURVIVAL, TIME_ATTACK }
const MODE_KEYS := {Mode.CLASSIC: "classic", Mode.SURVIVAL: "survival", Mode.TIME_ATTACK: "time_attack"}
const SURVIVAL_LIVES: int = 3
const TIME_ATTACK_SECONDS: float = 60.0
## A wrong answer costs time, otherwise tapping at random would be the best strategy.
const TIME_ATTACK_WRONG_PENALTY: float = 5.0
## Long runs must not turn the combo bonus (and XP) into a farm.
const MODE_COMBO_CAP: int = 10
const MODE_XP_CAP: int = 300

var category_id: String = ""
var questions: Array[Dictionary] = []
var current_index: int = 0
var score: int = 0
var correct_count: int = 0
var combo: int = 0
var max_combo: int = 0
var answer_times: Array[float] = []
var last_summary: Dictionary = {}
var shell_tab_index: int = 0
var active_challenge_code: String = ""
var active_daily_date: String = ""
var mode: int = Mode.CLASSIC
## Mode picked on the category screen; kept for "play again".
var selected_mode: int = Mode.CLASSIC
var lives: int = 0


## `daily_date` (the server's date string) starts the shared daily challenge:
## same questions for everyone, ordered by that date.
func start_round(selected_category_id: String, challenge_code: String = "", daily_date: String = "", round_mode: int = Mode.CLASSIC) -> void:
	category_id = selected_category_id
	active_challenge_code = challenge_code
	active_daily_date = daily_date
	## Daily and challenges are always classic: everyone must play the same round.
	mode = round_mode if challenge_code.is_empty() and daily_date.is_empty() else Mode.CLASSIC
	lives = SURVIVAL_LIVES if mode == Mode.SURVIVAL else 0
	if mode != Mode.CLASSIC:
		## The whole category, shuffled: a run ends by lives or clock, not by count.
		questions = QuestionLoaderScript.load_questions_for_category(category_id, LocaleManager.get_content_locale(), 0)
	elif not daily_date.is_empty():
		questions = QuestionLoaderScript.load_daily_questions(
			category_id,
			LocaleManager.get_content_locale(),
			QUESTIONS_PER_ROUND,
			daily_date
		)
	else:
		var seed_value := challenge_code.hash() if not challenge_code.is_empty() else 0
		questions = QuestionLoaderScript.load_questions_for_category(
			category_id,
			LocaleManager.get_content_locale(),
			QUESTIONS_PER_ROUND,
			seed_value
		)
	current_index = 0
	score = 0
	correct_count = 0
	combo = 0
	max_combo = 0
	answer_times.clear()


func has_questions() -> bool:
	return not questions.is_empty()


func get_current_question() -> Dictionary:
	if current_index >= questions.size():
		return {}
	return questions[current_index]


func get_progress_label() -> String:
	if mode != Mode.CLASSIC:
		return str(current_index + 1)
	return "%d / %d" % [min(current_index + 1, questions.size()), questions.size()]


func mode_key() -> String:
	return str(MODE_KEYS.get(mode, "classic"))


## Time attack: the clock ran out, the question on screen does not count.
func end_time_attack() -> void:
	questions = questions.slice(0, current_index)


func submit_answer(selected_index: int, elapsed_seconds: float) -> Dictionary:
	var question: Dictionary = get_current_question()
	if question.is_empty():
		return {"finished": true}

	var is_timeout: bool = selected_index < 0
	var is_correct: bool = not is_timeout and selected_index == int(question.get("correct_index", -1))
	var points: int = 0

	if is_correct:
		correct_count += 1
		combo += 1
		max_combo = max(max_combo, combo)
		var scoring_combo := combo if mode == Mode.CLASSIC else mini(combo, MODE_COMBO_CAP)
		points = ScoringSystemScript.calculate_points(elapsed_seconds, QUESTION_TIME_SECONDS, scoring_combo)
		score += points
	else:
		combo = 0
		if mode == Mode.SURVIVAL:
			lives -= 1

	answer_times.append(elapsed_seconds)
	current_index += 1

	var out_of_lives := mode == Mode.SURVIVAL and lives <= 0
	return {
		"finished": current_index >= questions.size() or out_of_lives,
		"lives": lives,
		"is_correct": is_correct,
		"is_timeout": is_timeout,
		"points": points,
		"combo": combo,
	}


func finish_round() -> Dictionary:
	var average_time: float = 0.0
	if not answer_times.is_empty():
		var total_time: float = 0.0
		for value in answer_times:
			total_time += value
		average_time = total_time / answer_times.size()

	var progress_before: Dictionary = SaveManager.capture_progress()
	var is_classic := mode == Mode.CLASSIC
	## Modes end early: only the questions actually answered count.
	var total_count := questions.size() if is_classic else current_index
	var won := SaveManager.is_match_won(correct_count, total_count) if is_classic else false
	var record: Dictionary = {} if is_classic else SaveManager.record_mode_result(mode_key(), category_id, score, correct_count)
	var xp_gained := SaveManager.record_match_result(
		category_id,
		score,
		correct_count,
		total_count,
		max_combo,
		not active_challenge_code.is_empty(),
		mode_key(),
		0 if is_classic else MODE_XP_CAP,
	)
	var is_daily := not active_daily_date.is_empty()
	if is_daily:
		xp_gained += SaveManager.record_daily_challenge(active_daily_date, score, correct_count, questions.size(), max_combo)
		NetworkManager.last_daily_result = {}
		NetworkManager.submit_daily_result(score, correct_count, questions.size(), max_combo)
	var day_streak: Dictionary = DayStreak.record_play()
	if int(day_streak.get("xp", 0)) > 0:
		SaveManager.add_xp(int(day_streak["xp"]))
		xp_gained += int(day_streak["xp"])
	SaveManager.save_data()
	var progress_after: Dictionary = SaveManager.capture_progress()
	var new_achievements: Array[String] = []
	for achievement_id in progress_after.get("unlocked", []):
		if not progress_before.get("unlocked", []).has(achievement_id):
			new_achievements.append(achievement_id)

	var summary := {
		"category_id": category_id,
		"score": score,
		"correct_count": correct_count,
		"total_count": total_count,
		"max_combo": max_combo,
		"mode": mode_key(),
		"record": record,
		"average_time": average_time,
		"won": won,
		"xp_gained": xp_gained,
		"level_before": int(progress_before.get("level", 1)),
		"level_after": int(progress_after.get("level", 1)),
		"xp_before": int(progress_before.get("xp", 0)),
		"xp_after": int(progress_after.get("xp", 0)),
		"xp_needed_before": int(progress_before.get("xp_needed", 100)),
		"xp_needed_after": int(progress_after.get("xp_needed", 100)),
		"new_achievements": new_achievements,
		"is_daily": is_daily,
		"day_streak": day_streak,
	}

	## Survival/time-attack scores are not comparable with classic rounds:
	## keep them off the shared leaderboard.
	if is_classic:
		NetworkManager.submit_match(
			category_id,
			score,
			correct_count,
			total_count,
			max_combo,
			won,
		)
	if not active_challenge_code.is_empty():
		NetworkManager.submit_challenge_result(active_challenge_code, score, correct_count)
		active_challenge_code = ""
	active_daily_date = ""
	last_summary = summary
	return summary
