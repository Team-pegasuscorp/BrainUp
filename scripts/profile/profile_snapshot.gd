class_name ProfileSnapshot
extends RefCounted

const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const PlayerRanks = preload("res://scripts/profile/player_ranks.gd")
const AchievementsCatalog = preload("res://scripts/profile/achievements_catalog.gd")
const LeaderboardSnapshot = preload("res://scripts/profile/leaderboard_snapshot.gd")
const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const CountryFlags = preload("res://scripts/profile/country_flags.gd")
const TrophyLeagues = preload("res://scripts/profile/trophy_leagues.gd")

const USE_DEMO_WHEN_EMPTY: bool = true
## Force demo profile data (categories, history, stats) for layout testing.
const FORCE_DEMO_PROFILE: bool = true
const DAILY_GOAL_TARGET: int = 5
const HISTORY_OPPONENTS: Array[String] = ["Lucas", "Emma", "Noah", "Léa", "Hugo", "Chloé"]


static func build_full(locale: String) -> Dictionary:
	var data := _from_save(locale)
	if FORCE_DEMO_PROFILE or (USE_DEMO_WHEN_EMPTY and int(data.get("games_played", 0)) == 0):
		data = _merge_demo(data, locale)
	data["achievements"] = _build_achievements(data)
	data["ranking"] = _build_ranking(data, locale)
	data["daily_goal"] = _build_daily_goal(data)
	data["best_category"] = _pick_best_category(data.get("categories", []))
	data["win_distribution"] = _build_win_distribution(data)
	data["season"] = _build_season(data)
	## Preview: force display name to check hero layout.
	data["player_name"] = "Arknoid"
	return data


static func _from_save(locale: String) -> Dictionary:
	var games := _count_games()
	var questions := _count_questions()
	var correct := _count_correct()
	var accuracy := 0.0 if questions <= 0 else float(correct) / float(questions) * 100.0
	var win_rate := SaveManager.get_win_rate_percent()
	return {
		"player_name": SaveManager.player_name,
		"country": "France",
		"country_flag": CountryFlags.emoji_for("France"),
		"email_verified": SaveManager.email_verified,
		## Local player is online while the app session is active.
		## Social profiles will override this from presence / friends API later.
		"is_online": true,
		"level": SaveManager.level,
		"xp": SaveManager.xp,
		"xp_to_next": SaveManager.get_xp_for_next_level(),
		"xp_progress": SaveManager.get_xp_progress_ratio(),
		"xp_remaining": maxi(SaveManager.get_xp_for_next_level() - SaveManager.xp, 0),
		"rank_title_key": PlayerRanks.title_for_level(SaveManager.level),
		"avatar_texture": SaveManager.get_profile_avatar_texture(),
		"has_custom_avatar": SaveManager.has_custom_avatar(),
		"games_played": games,
		"wins": SaveManager.wins,
		"losses": SaveManager.losses,
		"win_rate_percent": win_rate,
		"correct_answers": correct,
		"questions_answered": questions,
		"accuracy_percent": accuracy,
		"current_win_streak": SaveManager.current_win_streak,
		"best_win_streak": SaveManager.best_win_streak,
		"best_score": _best_score(),
		"categories": _build_categories(locale),
		"history": _build_history(locale),
		"is_demo": false,
	}


static func _count_games() -> int:
	var total := 0
	for category_id in SaveManager.category_stats.keys():
		total += int(SaveManager.category_stats[category_id].get("games_played", 0))
	return total


static func _count_correct() -> int:
	var total := 0
	for category_id in SaveManager.category_stats.keys():
		total += int(SaveManager.category_stats[category_id].get("total_correct", 0))
	return total


static func _count_questions() -> int:
	var total := 0
	for category_id in SaveManager.category_stats.keys():
		total += int(SaveManager.category_stats[category_id].get("total_questions", 0))
	return total


static func _best_score() -> int:
	var best := 0
	for category_id in SaveManager.category_stats.keys():
		best = max(best, int(SaveManager.category_stats[category_id].get("best_score", 0)))
	return best


static func _merge_demo(base: Dictionary, locale: String) -> Dictionary:
	var demo := base.duplicate(true)
	demo["is_demo"] = true
	demo["level"] = 27
	demo["xp"] = 2450
	demo["xp_to_next"] = 3000
	demo["xp_progress"] = 2450.0 / 3000.0
	demo["xp_remaining"] = 550
	demo["rank_title_key"] = PlayerRanks.title_for_level(27)
	demo["games_played"] = 1248
	demo["wins"] = 849
	demo["losses"] = 399
	demo["win_rate_percent"] = 68.0
	demo["correct_answers"] = 6120
	demo["questions_answered"] = 6652
	demo["accuracy_percent"] = 92.0
	demo["current_win_streak"] = 7
	demo["best_win_streak"] = 17
	demo["best_score"] = 980
	demo["has_perfect_round"] = false
	demo["country"] = "France"
	demo["country_flag"] = CountryFlags.emoji_for("France")
	demo["email_verified"] = true
	demo["is_online"] = true
	## Demo XP = total correct answers; one row per real category pack.
	demo["categories"] = _build_demo_categories(locale)
	demo["history"] = [
		_make_history_row("science", locale, 820, true, 15, 9, 0, "Lucas", 24, 2),
		_make_history_row("cinema", locale, 780, true, 18, 12, 0, "Emma", 18, 15),
		_make_history_row("sport", locale, 410, false, 8, 15, 1, "Theo", -12, 60),
		_make_history_row("geography", locale, 860, true, 20, 11, 3, "Chloé", 22, 180),
	]
	return demo


static func _build_demo_categories(locale: String) -> Array:
	## Preset stats for layout preview; every pack from QuestionLoader is included.
	var presets := {
		"sport": {"games": 412, "accuracy": 84.0, "correct": 118},
		"cinema": {"games": 386, "accuracy": 71.0, "correct": 93},
		"history": {"games": 450, "accuracy": 78.0, "correct": 108},
		"music": {"games": 398, "accuracy": 76.0, "correct": 88},
		"geography": {"games": 430, "accuracy": 81.0, "correct": 103},
		"science": {"games": 360, "accuracy": 69.0, "correct": 72},
		"general": {"games": 310, "accuracy": 74.0, "correct": 64},
		"television": {"games": 280, "accuracy": 66.0, "correct": 55},
	}
	var rows: Array = []
	for category in QuestionLoaderScript.get_categories(locale):
		var category_id: String = str(category.get("id", ""))
		if category_id.is_empty():
			continue
		var preset: Dictionary = presets.get(category_id, {
			"games": 120,
			"accuracy": 60.0,
			"correct": 30,
		})
		rows.append(_make_category_row(
			category_id,
			locale,
			int(preset.get("games", 0)),
			float(preset.get("accuracy", 0.0)),
			-1,
			-1,
			"none",
			int(preset.get("correct", 0))
		))
	_assign_medals(rows)
	return rows


static func _build_categories(locale: String) -> Array:
	var rows: Array = []
	for category in QuestionLoaderScript.get_categories(locale):
		var category_id: String = str(category.get("id", ""))
		var stats: Dictionary = SaveManager.get_category_stats(category_id)
		var games: int = int(stats.get("games_played", 0))
		var total_q: int = int(stats.get("total_questions", 0))
		var total_c: int = int(stats.get("total_correct", 0))
		var accuracy := 0.0 if total_q <= 0 else float(total_c) / float(total_q) * 100.0
		rows.append(_make_category_row(category_id, locale, games, accuracy, -1, -1, "none", total_c))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("total_correct", 0)) > int(b.get("total_correct", 0))
	)
	_assign_medals(rows)
	return rows


static func category_corrects_to_complete_level(level: int) -> int:
	## Cost in correct answers to finish this level (exponential).
	## Level 1 = 10, level 2 = 25, level 3 ≈ 63, …
	if level <= 0:
		return 0
	var base := float(maxi(UiTokens.CATEGORY_LEVEL_BASE_CORRECTS, 1))
	var growth := maxf(UiTokens.CATEGORY_LEVEL_GROWTH, 1.01)
	return maxi(1, int(round(base * pow(growth, float(level - 1)))))


static func category_level_from_correct(total_correct: int) -> int:
	## Current level from cumulative correct answers (starts at 1 while filling the first bar).
	if total_correct < 0:
		total_correct = 0
	var remaining := total_correct
	var level := 1
	var max_level := maxi(UiTokens.CATEGORY_LEVEL_MAX, 1)
	while level < max_level:
		var need := category_corrects_to_complete_level(level)
		if remaining < need:
			return level
		remaining -= need
		level += 1
	return max_level


static func category_progress_from_correct(total_correct: int) -> float:
	## Fill of the current level bar (0→1 within the level).
	if total_correct < 0:
		total_correct = 0
	var level := category_level_from_correct(total_correct)
	var spent := 0
	for prev in range(1, level):
		spent += category_corrects_to_complete_level(prev)
	var into_level := total_correct - spent
	var need := category_corrects_to_complete_level(level)
	if need <= 0:
		return 0.0
	if level >= UiTokens.CATEGORY_LEVEL_MAX:
		return 1.0
	return clampf(float(into_level) / float(need), 0.0, 1.0)


static func category_mastery_from_correct(total_correct: int) -> int:
	## Coarse 1–4 band from the same correct-answer XP.
	if total_correct <= 0:
		return 0
	var level := category_level_from_correct(total_correct)
	if level <= 2:
		return 1
	if level <= 4:
		return 2
	if level <= 6:
		return 3
	return 4


static func _make_category_row(
	category_id: String,
	locale: String,
	games: int,
	accuracy: float,
	mastery: int = -1,
	display_level: int = -1,
	medal: String = "none",
	total_correct: int = -1
) -> Dictionary:
	if total_correct < 0:
		## Demo rows often omit totals — approximate from games × accuracy.
		total_correct = int(round(float(games) * accuracy / 100.0)) if games > 0 else 0
	if display_level < 0:
		display_level = category_level_from_correct(total_correct)
	if mastery < 0:
		mastery = category_mastery_from_correct(total_correct)
	return {
		"id": category_id,
		"name": _resolve_category_name(category_id, locale),
		"icon": _category_icon(category_id),
		"games_played": games,
		"total_correct": total_correct,
		"accuracy_percent": accuracy,
		"mastery_level": mastery,
		"display_level": display_level,
		"medal": medal,
		"mastery_label_key": "UI_MASTERY_%d" % mastery,
		"mastery_progress": category_progress_from_correct(total_correct),
		"win_rate_percent": accuracy,
	}


static func _assign_medals(rows: Array) -> void:
	var ranked: Array = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		row["medal"] = "none"
		if int(row.get("games_played", 0)) <= 0:
			continue
		ranked.append(row)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("accuracy_percent", 0.0)) > float(b.get("accuracy_percent", 0.0))
	)
	## Only the top 3 get medals.
	var medals := ["gold", "silver", "bronze"]
	for i in range(mini(ranked.size(), medals.size())):
		ranked[i]["medal"] = medals[i]
	## Keep list order: best accuracy first (gold → silver → bronze → …).
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_played := int(a.get("games_played", 0)) > 0
		var b_played := int(b.get("games_played", 0)) > 0
		if a_played != b_played:
			return a_played
		return float(a.get("accuracy_percent", 0.0)) > float(b.get("accuracy_percent", 0.0))
	)


static func _category_icon(category_id: String) -> String:
	match category_id:
		"sport":
			return "⚽"
		"cinema":
			return "🎬"
		"history":
			return "📜"
		"science":
			return "🧪"
		"geography":
			return "🌍"
		"music":
			return "🎵"
		"general":
			return "💡"
		"television":
			return "📺"
		_:
			return "🧠"


static func _make_history_row(
	category_id: String,
	locale: String,
	score: int,
	won: bool,
	my_score: int,
	opponent_score: int,
	age_hours: int,
	opponent: String = "",
	points_delta: int = 0,
	age_minutes: int = -1
) -> Dictionary:
	if opponent.is_empty():
		opponent = HISTORY_OPPONENTS[absi(hash("%s-%s-%d" % [category_id, locale, score])) % HISTORY_OPPONENTS.size()]
	if points_delta == 0:
		points_delta = (my_score * 4) if won else -maxi(opponent_score, 1) * 3
	if age_minutes < 0:
		age_minutes = maxi(age_hours, 0) * 60
	return {
		"category_id": category_id,
		"category_name": _resolve_category_name(category_id, locale),
		"score": score,
		"won": won,
		"correct_count": my_score,
		"total_count": my_score + opponent_score,
		"my_score": my_score,
		"opponent_score": opponent_score,
		"age_hours": age_hours,
		"age_minutes": age_minutes,
		"opponent": opponent,
		"points_delta": points_delta,
	}


static func _build_history(locale: String) -> Array:
	var rows: Array = []
	var now := int(Time.get_unix_time_from_system())
	var index := 0
	for raw in SaveManager.match_history:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var played_at := int(raw.get("played_at", now))
		var age_seconds := maxi(now - played_at, 0)
		var age_minutes := int(age_seconds / 60.0)
		var age_hours := int(age_seconds / 3600.0)
		var won := bool(raw.get("won", false))
		var correct := int(raw.get("correct_count", 0))
		var total := int(raw.get("total_count", 0))
		var theirs := maxi(total - correct, 0)
		rows.append(_make_history_row(
			str(raw.get("category_id", "")),
			locale,
			int(raw.get("score", 0)),
			won,
			correct,
			theirs,
			age_hours,
			HISTORY_OPPONENTS[index % HISTORY_OPPONENTS.size()],
			0,
			age_minutes
		))
		index += 1
	return rows


static func _build_achievements(data: Dictionary) -> Array:
	var unlock_stats := {
		"games_played": data.get("games_played", 0),
		"wins": data.get("wins", 0),
		"best_win_streak": data.get("best_win_streak", 0),
		"best_score": data.get("best_score", 0),
		"has_perfect_round": data.get("has_perfect_round", SaveManager.has_perfect_round),
		"level": data.get("level", 1),
		"categories_played": _count_categories_played_from_data(data),
		"accuracy_percent": data.get("accuracy_percent", 0.0),
	}
	var rows: Array = []
	for achievement in AchievementsCatalog.all():
		rows.append({
			"id": achievement.get("id", ""),
			"title_key": achievement.get("title_key", ""),
			"desc_key": achievement.get("desc_key", ""),
			"icon": achievement.get("icon", "?"),
			"accent": achievement.get("accent", UiTokens.ACCENT_PROFILE),
			"unlocked": AchievementsCatalog.is_unlocked(str(achievement.get("id", "")), unlock_stats),
		})
	return rows


static func _build_ranking(data: Dictionary, locale: String) -> Dictionary:
	var board := LeaderboardSnapshot.build("all", locale)
	var rank := int(board.get("player_rank", 0))
	var points := int(data.get("best_score", 0))
	if data.get("is_demo", false):
		rank = 184
		points = 2845
	elif rank <= 0:
		rank = maxi(1, 220 - int(data.get("level", 1)) * 3)
		points = maxi(points, int(data.get("wins", 0)) * 12)
	var weekly_delta := 23 if data.get("is_demo", false) else clampi(int(data.get("current_win_streak", 0)) * 3, -18, 42)
	## League badge follows trophy count (thresholds still provisional).
	var league: Dictionary = TrophyLeagues.for_trophies(points)
	return {
		"rank": rank,
		"points": points,
		"weekly_delta": weekly_delta,
		"league_key": str(league.get("title_key", "UI_LEAGUE_BRONZE")),
		"league_icon": str(league.get("icon", "🥉")),
		"league_id": str(league.get("id", "bronze")),
		"league_thresholds_provisional": bool(league.get("thresholds_provisional", true)),
	}


static func _build_daily_goal(data: Dictionary) -> Dictionary:
	var played_today := mini(int(data.get("current_win_streak", 0)) + 1, DAILY_GOAL_TARGET)
	if data.get("is_demo", false):
		played_today = 3
	elif int(data.get("games_played", 0)) > 0:
		played_today = mini(int(data.get("games_played", 0)) % (DAILY_GOAL_TARGET + 1), DAILY_GOAL_TARGET)
	return {
		"current": played_today,
		"target": DAILY_GOAL_TARGET,
		"remaining": maxi(DAILY_GOAL_TARGET - played_today, 0),
		"progress": clampf(float(played_today) / float(DAILY_GOAL_TARGET), 0.0, 1.0),
	}


static func _count_categories_played_from_data(data: Dictionary) -> int:
	var count := 0
	for row in data.get("categories", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("games_played", 0)) > 0:
			count += 1
	return count


static func _resolve_category_name(category_id: String, locale: String) -> String:
	for category in QuestionLoaderScript.get_categories(locale):
		if category.get("id", "") == category_id:
			return str(category.get("name", category_id))
	## Demo-only fake categories (not in question packs yet).
	var is_fr := str(locale).begins_with("fr")
	match category_id:
		"science":
			return "Sciences" if is_fr else "Science"
		"geography":
			return "Géographie" if is_fr else "Geography"
		"music":
			return "Musique" if is_fr else "Music"
		_:
			return category_id


static func _pick_best_category(categories: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_acc := -1.0
	for row in categories:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("games_played", 0)) <= 0:
			continue
		var acc := float(row.get("accuracy_percent", 0.0))
		if acc > best_acc:
			best_acc = acc
			best = row
	return best


static func _build_win_distribution(data: Dictionary) -> Array:
	var categories: Array = data.get("categories", [])
	var total_wins := int(data.get("wins", 0))
	var weights: Array = []
	var total := 0.0
	for row in categories:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var games := float(row.get("games_played", 0))
		if games <= 0.0:
			continue
		var weight := games * maxf(float(row.get("accuracy_percent", 0.0)), 1.0)
		weights.append({"row": row, "weight": weight})
		total += weight
	if total <= 0.0:
		return []
	var out: Array = []
	for item in weights:
		var row: Dictionary = item.row
		var ratio := float(item.weight) / total
		out.append({
			"id": row.get("id", ""),
			"name": row.get("name", ""),
			"icon": row.get("icon", "🧠"),
			"ratio": ratio,
			"percent": int(round(ratio * 100.0)),
			"wins": int(round(ratio * float(total_wins))),
			"color": UiTokens.accent_for_category(str(row.get("id", ""))),
		})
	return out


static func _build_season(data: Dictionary) -> Dictionary:
	## Seasons are not shipped yet — locked for real profiles.
	## Demo profile previews the unlocked tile so we can polish the layout early.
	var ranking: Dictionary = data.get("ranking", {})
	var wins := int(data.get("wins", 0))
	var rate := float(data.get("win_rate_percent", 0.0))
	var points := int(ranking.get("points", data.get("best_score", 0)))
	var season := {
		"unlocked": false,
		"number": maxi(1, int(data.get("level", 1) / 8) + 1),
		"points": points,
		"wins": wins,
		"win_rate": rate,
		"best_rank": int(ranking.get("rank", 0)),
	}
	if data.get("is_demo", false):
		season["number"] = 12
		season["points"] = 2845
		season["wins"] = 68
		season["win_rate"] = 63.0
		season["best_rank"] = 184
	return season
