extends Node

const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ScoringSystemScript = preload("res://scripts/quiz/scoring_system.gd")

const QUESTIONS_PER_ROUND: int = 7
const QUESTION_TIME_SECONDS: float = 10.0

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


## `daily_date` (the server's date string) starts the shared daily challenge:
## same questions for everyone, ordered by that date.
func start_round(selected_category_id: String, challenge_code: String = "", daily_date: String = "") -> void:
	category_id = selected_category_id
	active_challenge_code = challenge_code
	active_daily_date = daily_date
	if not daily_date.is_empty():
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
	return "%d / %d" % [min(current_index + 1, questions.size()), questions.size()]


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
		points = ScoringSystemScript.calculate_points(elapsed_seconds, QUESTION_TIME_SECONDS, combo)
		score += points
	else:
		combo = 0

	answer_times.append(elapsed_seconds)
	current_index += 1

	return {
		"finished": current_index >= questions.size(),
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
	var won := SaveManager.is_match_won(correct_count, questions.size())
	var xp_gained := SaveManager.record_match_result(
		category_id,
		score,
		correct_count,
		questions.size(),
		max_combo,
		not active_challenge_code.is_empty(),
	)
	var is_daily := not active_daily_date.is_empty()
	if is_daily:
		xp_gained += SaveManager.record_daily_challenge(active_daily_date, score, correct_count, questions.size(), max_combo)
		NetworkManager.last_daily_result = {}
		NetworkManager.submit_daily_result(score, correct_count, questions.size(), max_combo)
	var progress_after: Dictionary = SaveManager.capture_progress()
	var new_achievements: Array[String] = []
	for achievement_id in progress_after.get("unlocked", []):
		if not progress_before.get("unlocked", []).has(achievement_id):
			new_achievements.append(achievement_id)

	var summary := {
		"category_id": category_id,
		"score": score,
		"correct_count": correct_count,
		"total_count": questions.size(),
		"max_combo": max_combo,
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
	}

	NetworkManager.submit_match(
		category_id,
		score,
		correct_count,
		questions.size(),
		max_combo,
		won,
	)
	if not active_challenge_code.is_empty():
		NetworkManager.submit_challenge_result(active_challenge_code, score, correct_count)
		active_challenge_code = ""
	active_daily_date = ""
	last_summary = summary
	return summary
