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
const DAILY_GOAL_TARGET: int = 5
const HISTORY_OPPONENTS: Array[String] = ["Lucas", "Emma", "Noah", "Léa", "Hugo", "Chloé"]


static func build_full(locale: String) -> Dictionary:
	var data := _from_save(locale)
	if USE_DEMO_WHEN_EMPTY and int(data.get("games_played", 0)) == 0:
		data = _merge_demo(data, locale)
	data["achievements"] = _build_achievements(data)
	data["ranking"] = _build_ranking(data, locale)
	data["daily_goal"] = _build_daily_goal(data)
	data["best_category"] = _pick_best_category(data.get("categories", []))
	data["win_distribution"] = _build_win_distribution(data)
	data["season"] = _build_season(data)
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
	demo["country"] = "France"
	demo["country_flag"] = CountryFlags.emoji_for("France")
	demo["email_verified"] = true
	demo["is_online"] = true
	demo["categories"] = [
		_make_category_row("sport", locale, 412, 84.0, 4, 24, "gold"),
		_make_category_row("cinema", locale, 386, 71.0, 3, 19, "bronze"),
		_make_category_row("history", locale, 450, 78.0, 4, 22, "silver"),
	]
	demo["history"] = [
		_make_history_row("sport", locale, 820, true, 15, 24, 0, "Lucas", 24),
		_make_history_row("cinema", locale, 510, false, 9, 20, 3, "Emma", -12),
		_make_history_row("history", locale, 740, true, 14, 22, 8, "Noah", 18),
		_make_history_row("sport", locale, 630, true, 12, 20, 26, "Léa", 9),
	]
	return demo


static func _build_categories(locale: String) -> Array:
	var rows: Array = []
	for category in QuestionLoaderScript.get_categories(locale):
		var category_id: String = str(category.get("id", ""))
		var stats: Dictionary = SaveManager.get_category_stats(category_id)
		var games: int = int(stats.get("games_played", 0))
		var total_q: int = int(stats.get("total_questions", 0))
		var total_c: int = int(stats.get("total_correct", 0))
		var accuracy := 0.0 if total_q <= 0 else float(total_c) / float(total_q) * 100.0
		var mastery := 0 if games <= 0 else clampi(int(games / 3) + int(accuracy / 30.0), 1, 4)
		var display_level := 0 if games <= 0 else clampi(int(games * 0.18) + int(accuracy / 8.0), 1, 99)
		rows.append(_make_category_row(category_id, locale, games, accuracy, mastery, display_level))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("accuracy_percent", 0.0)) > float(b.get("accuracy_percent", 0.0))
	)
	_assign_medals(rows)
	return rows


static func _make_category_row(
	category_id: String,
	locale: String,
	games: int,
	accuracy: float,
	mastery: int,
	display_level: int = -1,
	medal: String = "none"
) -> Dictionary:
	if display_level < 0:
		display_level = 0 if games <= 0 else clampi(int(games * 0.18) + int(accuracy / 8.0), 1, 99)
	return {
		"id": category_id,
		"name": _resolve_category_name(category_id, locale),
		"icon": _category_icon(category_id),
		"games_played": games,
		"accuracy_percent": accuracy,
		"mastery_level": mastery,
		"display_level": display_level,
		"medal": medal,
		"mastery_label_key": "UI_MASTERY_%d" % mastery,
		"mastery_progress": clampf(float(games) / 12.0, 0.12, 1.0) if games > 0 else 0.0,
		"win_rate_percent": accuracy,
	}


static func _assign_medals(rows: Array) -> void:
	var ranked: Array = []
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("games_played", 0)) <= 0:
			row["medal"] = "none"
			continue
		ranked.append(row)
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("accuracy_percent", 0.0)) > float(b.get("accuracy_percent", 0.0))
	)
	var medals := ["gold", "silver", "bronze"]
	for i in range(mini(ranked.size(), medals.size())):
		ranked[i]["medal"] = medals[i]


static func _category_icon(category_id: String) -> String:
	match category_id:
		"sport":
			return "⚽"
		"cinema":
			return "🎬"
		"history":
			return "📜"
		_:
			return "🧠"


static func _make_history_row(
	category_id: String,
	locale: String,
	score: int,
	won: bool,
	correct: int,
	total: int,
	age_hours: int,
	opponent: String = "",
	points_delta: int = 0
) -> Dictionary:
	if opponent.is_empty():
		opponent = HISTORY_OPPONENTS[absi(hash("%s-%s-%d" % [category_id, locale, score])) % HISTORY_OPPONENTS.size()]
	if points_delta == 0:
		points_delta = (correct * 4) if won else -maxi(total - correct, 1) * 3
	return {
		"category_id": category_id,
		"category_name": _resolve_category_name(category_id, locale),
		"score": score,
		"won": won,
		"correct_count": correct,
		"total_count": total,
		"age_hours": age_hours,
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
		var age_hours := int(max(float(now - played_at) / 3600.0, 0.0))
		var won := bool(raw.get("won", false))
		var correct := int(raw.get("correct_count", 0))
		var total := int(raw.get("total_count", 0))
		rows.append(_make_history_row(
			str(raw.get("category_id", "")),
			locale,
			int(raw.get("score", 0)),
			won,
			correct,
			total,
			age_hours,
			HISTORY_OPPONENTS[index % HISTORY_OPPONENTS.size()],
			0
		))
		index += 1
	return rows


static func _build_achievements(data: Dictionary) -> Array:
	var unlock_stats := {
		"games_played": data.get("games_played", 0),
		"wins": data.get("wins", 0),
		"best_win_streak": data.get("best_win_streak", 0),
		"best_score": data.get("best_score", 0),
		"has_perfect_round": SaveManager.has_perfect_round,
		"level": data.get("level", 1),
		"categories_played": _count_categories_played_from_data(data),
	}
	var rows: Array = []
	for achievement in AchievementsCatalog.all():
		rows.append({
			"id": achievement.get("id", ""),
			"title_key": achievement.get("title_key", ""),
			"desc_key": achievement.get("desc_key", ""),
			"icon": achievement.get("icon", "?"),
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
			"color": UiTokens.accent_for_category(str(row.get("id", ""))),
		})
	return out


static func _build_season(data: Dictionary) -> Dictionary:
	var ranking: Dictionary = data.get("ranking", {})
	var wins := int(data.get("wins", 0))
	var rate := float(data.get("win_rate_percent", 0.0))
	var points := int(ranking.get("points", data.get("best_score", 0)))
	if data.get("is_demo", false):
		return {
			"number": 3,
			"points": 2845,
			"wins": 76,
			"win_rate": 59.0,
			"best_rank": 184,
		}
	return {
		"number": maxi(1, int(data.get("level", 1) / 8) + 1),
		"points": points,
		"wins": wins,
		"win_rate": rate,
		"best_rank": int(ranking.get("rank", 0)),
	}
