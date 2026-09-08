extends Node

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")

const SAVE_PATH: String = "user://save.json"
const PROFILE_AVATAR_PATH: String = "user://profile_avatar.png"
const DEFAULT_AVATAR_PATH: String = "res://assets/ui/default_avatar.svg"
const MAX_MATCH_HISTORY: int = 30

var player_name: String = UiTokens.DEFAULT_PLAYER_NAME
var preferred_locale: String = ""
var email: String = ""
## True after the player confirms ownership of `email` (mail verification).
var email_verified: bool = false
var level: int = 1
var xp: int = 0
var category_stats: Dictionary = {}
var leaderboard_rivals: Array = []
var match_history: Array = []
var wins: int = 0
var losses: int = 0
var current_win_streak: int = 0
var best_win_streak: int = 0
var has_perfect_round: bool = false


func _ready() -> void:
	load_data()


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	player_name = parsed.get("player_name", player_name)
	preferred_locale = parsed.get("preferred_locale", preferred_locale)
	email = str(parsed.get("email", email))
	email_verified = bool(parsed.get("email_verified", email_verified))
	level = int(parsed.get("level", level))
	xp = int(parsed.get("xp", xp))
	category_stats = parsed.get("category_stats", category_stats)
	leaderboard_rivals = parsed.get("leaderboard_rivals", leaderboard_rivals)
	match_history = parsed.get("match_history", match_history)
	wins = int(parsed.get("wins", wins))
	losses = int(parsed.get("losses", losses))
	current_win_streak = int(parsed.get("current_win_streak", current_win_streak))
	best_win_streak = int(parsed.get("best_win_streak", best_win_streak))
	has_perfect_round = bool(parsed.get("has_perfect_round", has_perfect_round))


func save_data() -> void:
	var data := {
		"player_name": player_name,
		"preferred_locale": preferred_locale,
		"email": email,
		"email_verified": email_verified,
		"level": level,
		"xp": xp,
		"category_stats": category_stats,
		"leaderboard_rivals": leaderboard_rivals,
		"match_history": match_history,
		"wins": wins,
		"losses": losses,
		"current_win_streak": current_win_streak,
		"best_win_streak": best_win_streak,
		"has_perfect_round": has_perfect_round,
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: unable to write save file")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func get_preferred_locale() -> String:
	return preferred_locale


func set_preferred_locale(locale: String) -> void:
	preferred_locale = locale
	save_data()


func set_player_name(name: String) -> void:
	var trimmed := name.strip_edges()
	player_name = trimmed if not trimmed.is_empty() else UiTokens.DEFAULT_PLAYER_NAME
	save_data()


func set_email(address: String) -> void:
	email = address.strip_edges().to_lower()
	## Changing email invalidates prior verification until confirmed again.
	email_verified = false
	save_data()


func set_email_verified(verified: bool) -> void:
	email_verified = verified
	save_data()


func get_xp_for_next_level() -> int:
	return _xp_for_next_level()


func get_xp_progress_ratio() -> float:
	var needed := _xp_for_next_level()
	if needed <= 0:
		return 0.0
	return clampf(float(xp) / float(needed), 0.0, 1.0)


func has_custom_avatar() -> bool:
	return FileAccess.file_exists(PROFILE_AVATAR_PATH)


func get_profile_avatar_texture() -> Texture2D:
	if has_custom_avatar():
		var image := Image.load_from_file(PROFILE_AVATAR_PATH)
		if image != null:
			return ImageTexture.create_from_image(image)
	if ResourceLoader.exists(DEFAULT_AVATAR_PATH):
		return load(DEFAULT_AVATAR_PATH) as Texture2D
	return null


func set_profile_avatar_from_file(source_path: String) -> bool:
	var image := Image.new()
	if image.load(source_path) != OK:
		return false
	image.resize(UiTokens.PROFILE_AVATAR_SIZE, UiTokens.PROFILE_AVATAR_SIZE, Image.INTERPOLATE_LANCZOS)
	if image.save_png(PROFILE_AVATAR_PATH) != OK:
		return false
	save_data()
	return true


func clear_profile_avatar() -> void:
	if FileAccess.file_exists(PROFILE_AVATAR_PATH):
		DirAccess.remove_absolute(PROFILE_AVATAR_PATH)
	save_data()


func record_match_result(
	category_id: String,
	score: int,
	correct_count: int,
	total_count: int,
	max_combo: int = 0,
) -> void:
	if not category_stats.has(category_id):
		category_stats[category_id] = {
			"games_played": 0,
			"best_score": 0,
			"total_correct": 0,
			"total_questions": 0,
		}

	var stats: Dictionary = category_stats[category_id]
	stats["games_played"] = int(stats.get("games_played", 0)) + 1
	stats["best_score"] = max(int(stats.get("best_score", 0)), score)
	stats["total_correct"] = int(stats.get("total_correct", 0)) + correct_count
	stats["total_questions"] = int(stats.get("total_questions", 0)) + total_count
	category_stats[category_id] = stats

	var won := is_match_won(correct_count, total_count)
	if won:
		wins += 1
		current_win_streak += 1
		best_win_streak = max(best_win_streak, current_win_streak)
	else:
		losses += 1
		current_win_streak = 0

	if total_count > 0 and correct_count >= total_count:
		has_perfect_round = true

	_prepend_match_history({
		"category_id": category_id,
		"score": score,
		"correct_count": correct_count,
		"total_count": total_count,
		"max_combo": max_combo,
		"won": won,
		"played_at": int(Time.get_unix_time_from_system()),
	})

	var gained_xp: int = correct_count * 10 + score / 10
	add_xp(gained_xp)
	save_data()


func get_win_rate_percent() -> float:
	var total := wins + losses
	if total <= 0:
		return 0.0
	return float(wins) / float(total) * 100.0


func _prepend_match_history(entry: Dictionary) -> void:
	match_history.insert(0, entry)
	if match_history.size() > MAX_MATCH_HISTORY:
		match_history = match_history.slice(0, MAX_MATCH_HISTORY)


func is_match_won(correct_count: int, total_count: int) -> bool:
	if total_count <= 0:
		return false
	return correct_count * 2 > total_count


func add_xp(amount: int) -> void:
	xp += amount
	while xp >= _xp_for_next_level():
		xp -= _xp_for_next_level()
		level += 1


func get_category_stats(category_id: String) -> Dictionary:
	return category_stats.get(category_id, {
		"games_played": 0,
		"best_score": 0,
		"total_correct": 0,
		"total_questions": 0,
	})


func get_games_played_total() -> int:
	var total := 0
	for category_id in category_stats.keys():
		total += int(category_stats[category_id].get("games_played", 0))
	return total


func get_leaderboard_score(category_filter: String) -> int:
	if category_filter.is_empty() or category_filter == "all":
		return _best_score_global()
	return int(get_category_stats(category_filter).get("best_score", 0))


func ensure_leaderboard_rivals() -> void:
	if not leaderboard_rivals.is_empty():
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = 9282
	var category_ids: Array[String] = []
	for category in QuestionLoaderScript.get_categories("en"):
		var category_id := str(category.get("id", ""))
		if not category_id.is_empty():
			category_ids.append(category_id)
	if category_ids.is_empty():
		category_ids = ["sport", "cinema", "history"]
	for rival_name in _rival_names():
		var scores := {"all": 0}
		for category_id in category_ids:
			var score := rng.randi_range(280, 620)
			scores[category_id] = score
			scores["all"] = max(int(scores["all"]), score)
		leaderboard_rivals.append({
			"id": rival_name.to_lower(),
			"name": rival_name,
			"level": rng.randi_range(2, 12),
			"scores": scores,
		})
	save_data()


func _best_score_global() -> int:
	var best := 0
	for category_id in category_stats.keys():
		best = max(best, int(category_stats[category_id].get("best_score", 0)))
	return best


func _rival_names() -> Array[String]:
	return ["Nova", "Kira", "Milo", "Zara", "Theo", "Luna", "Axel", "Iris", "Leo"]


func _xp_for_next_level() -> int:
	return 100 + (level - 1) * 25
