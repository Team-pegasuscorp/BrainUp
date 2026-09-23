extends Node

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const AchievementsCatalogScript = preload("res://scripts/profile/achievements_catalog.gd")
const DailyQuestsScript = preload("res://scripts/profile/daily_quests.gd")
const DailyChallengeScript = preload("res://scripts/profile/daily_challenge.gd")

const SAVE_PATH: String = "user://save.json"
## Legacy custom photo (before avatars became a fixed set); deleted on reset.
const PROFILE_AVATAR_PATH: String = "user://profile_avatar.png"
## Avatars the player can pick, from assets/avatars/demo/.
const PROFILE_AVATAR_IDS: Array[String] = GameAssets.DEMO_AVATAR_SLUGS
const DEFAULT_AVATAR_PATH: String = "res://assets/ui/default_avatar.svg"
const MAX_MATCH_HISTORY: int = 30

var player_name: String = UiTokens.DEFAULT_PLAYER_NAME
## Chosen avatar id from PROFILE_AVATAR_IDS ("" = default avatar).
var profile_avatar_id: String = ""
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
## Consecutive days played (see DayStreak); last_play_day is a local "YYYY-MM-DD".
var day_streak: int = 0
var best_day_streak: int = 0
var last_play_day: String = ""
var has_perfect_round: bool = false
var daily_state: Dictionary = {}
var daily_challenge_result: Dictionary = {}
## Best survival / time-attack runs: { mode: { category: {score, correct} } }.
var mode_records: Dictionary = {}
var sound_enabled: bool = true
var sound_volume: float = 0.8


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
	profile_avatar_id = str(parsed.get("profile_avatar_id", ""))
	if not PROFILE_AVATAR_IDS.has(profile_avatar_id):
		profile_avatar_id = ""
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
	day_streak = int(parsed.get("day_streak", day_streak))
	best_day_streak = int(parsed.get("best_day_streak", best_day_streak))
	last_play_day = str(parsed.get("last_play_day", last_play_day))
	has_perfect_round = bool(parsed.get("has_perfect_round", has_perfect_round))
	daily_state = parsed.get("daily_state", daily_state)
	daily_challenge_result = parsed.get("daily_challenge_result", daily_challenge_result)
	mode_records = parsed.get("mode_records", mode_records)
	sound_enabled = bool(parsed.get("sound_enabled", sound_enabled))
	sound_volume = clampf(float(parsed.get("sound_volume", sound_volume)), 0.0, 1.0)


func save_data() -> void:
	var data := {
		"player_name": player_name,
		"profile_avatar_id": profile_avatar_id,
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
		"day_streak": day_streak,
		"best_day_streak": best_day_streak,
		"last_play_day": last_play_day,
		"has_perfect_round": has_perfect_round,
		"daily_state": daily_state,
		"daily_challenge_result": daily_challenge_result,
		"mode_records": mode_records,
		"sound_enabled": sound_enabled,
		"sound_volume": sound_volume,
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


func set_sound_enabled(enabled: bool) -> void:
	sound_enabled = enabled
	save_data()


func set_sound_volume(volume: float) -> void:
	sound_volume = clampf(volume, 0.0, 1.0)
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
	return not profile_avatar_id.is_empty()


func get_profile_avatar_texture() -> Texture2D:
	return avatar_texture_for(profile_avatar_id)


## Texture for an avatar id; "" or an unknown id gives the default avatar.
func avatar_texture_for(avatar_id: String) -> Texture2D:
	if PROFILE_AVATAR_IDS.has(avatar_id):
		var tex := GameAssets.load_texture("res://assets/avatars/demo/%s.png" % avatar_id)
		if tex != null:
			return tex
	if ResourceLoader.exists(DEFAULT_AVATAR_PATH):
		var imported := load(DEFAULT_AVATAR_PATH) as Texture2D
		if imported != null:
			return imported
	if FileAccess.file_exists(DEFAULT_AVATAR_PATH):
		var image := Image.new()
		if image.load(DEFAULT_AVATAR_PATH) == OK:
			return ImageTexture.create_from_image(image)
	return null


func set_profile_avatar_id(avatar_id: String) -> void:
	profile_avatar_id = avatar_id if PROFILE_AVATAR_IDS.has(avatar_id) else ""
	save_data()


func clear_profile_avatar() -> void:
	profile_avatar_id = ""
	if FileAccess.file_exists(PROFILE_AVATAR_PATH):
		DirAccess.remove_absolute(PROFILE_AVATAR_PATH)
	save_data()


func record_match_result(
	category_id: String,
	score: int,
	correct_count: int,
	total_count: int,
	max_combo: int = 0,
	is_challenge: bool = false,
	mode: String = "classic",
	xp_cap: int = 0,
) -> int:
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

	## Survival and time attack have no win or loss: they leave the record untouched.
	var ranked := mode == "classic"
	var won := ranked and is_match_won(correct_count, total_count)
	if ranked:
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
		"mode": mode,
		"played_at": int(Time.get_unix_time_from_system()),
	})

	DailyQuestsScript.record_match(category_id, won, correct_count, max_combo, is_challenge, ranked)

	var gained_xp: int = correct_count * 10 + score / 10
	if xp_cap > 0:
		gained_xp = mini(gained_xp, xp_cap)
	add_xp(gained_xp)
	save_data()
	return gained_xp


## Level, XP bar and unlocked achievement ids at this instant.
## Taken before and after a match so the results screen can show what changed.
func capture_progress() -> Dictionary:
	var unlocked: Array[String] = []
	var unlock_stats := get_achievement_stats()
	for achievement in AchievementsCatalogScript.all():
		var achievement_id := str(achievement.get("id", ""))
		if AchievementsCatalogScript.is_unlocked(achievement_id, unlock_stats):
			unlocked.append(achievement_id)
	return {
		"level": level,
		"xp": xp,
		"xp_needed": _xp_for_next_level(),
		"unlocked": unlocked,
	}


func get_achievement_stats() -> Dictionary:
	var questions := 0
	var correct := 0
	var categories_played := 0
	for category_id in category_stats.keys():
		var stats: Dictionary = category_stats[category_id]
		questions += int(stats.get("total_questions", 0))
		correct += int(stats.get("total_correct", 0))
		if int(stats.get("games_played", 0)) > 0:
			categories_played += 1
	return {
		"games_played": get_games_played_total(),
		"wins": wins,
		"best_win_streak": best_win_streak,
		"best_day_streak": best_day_streak,
		"best_score": _best_score_global(),
		"has_perfect_round": has_perfect_round,
		"level": level,
		"categories_played": categories_played,
		"accuracy_percent": 0.0 if questions <= 0 else float(correct) / float(questions) * 100.0,
	}


## Stores today's shared-challenge result. Only the first play of a day counts;
## returns the bonus XP granted (0 on a repeat).
func record_daily_challenge(date: String, score: int, correct_count: int, total_count: int, max_combo: int = 0) -> int:
	if str(daily_challenge_result.get("date", "")) == date:
		return 0
	daily_challenge_result = {
		"date": date,
		"score": score,
		"correct_count": correct_count,
		"total_count": total_count,
		"max_combo": max_combo,
	}
	add_xp(DailyChallengeScript.BONUS_XP)
	save_data()
	return DailyChallengeScript.BONUS_XP


## Returns {previous, is_record} and stores the run if it beats the best score.
func record_mode_result(mode: String, category_id: String, score: int, correct_count: int) -> Dictionary:
	var by_category: Dictionary = mode_records.get(mode, {})
	var previous: Dictionary = by_category.get(category_id, {})
	var is_record := score > int(previous.get("score", 0))
	if is_record:
		by_category[category_id] = {"score": score, "correct": correct_count}
		mode_records[mode] = by_category
	return {"previous_score": int(previous.get("score", 0)), "previous_correct": int(previous.get("correct", 0)), "is_record": is_record}


func get_mode_record(mode: String, category_id: String) -> Dictionary:
	return (mode_records.get(mode, {}) as Dictionary).get(category_id, {})


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
	## Prefer names that match assets/avatars/demo portraits.
	return ["Lucas", "Emma", "Noah", "Léa", "Hugo", "Chloé", "Adam", "Sarah", "Maya"]


func _xp_for_next_level() -> int:
	return 100 + (level - 1) * 25
