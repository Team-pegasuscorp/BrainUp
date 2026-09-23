class_name AchievementsCatalog
extends RefCounted


static func all() -> Array[Dictionary]:
	## Progression ladder first (profile tile shows the first 6), then advanced milestones.
	return [
		{
			"id": "first_match",
			"title_key": "UI_ACH_FIRST_MATCH",
			"desc_key": "UI_ACH_FIRST_MATCH_DESC",
			"icon": "🎮",
			"accent": Color(0.36, 0.75, 1.0, 1),
		},
		{
			"id": "first_win",
			"title_key": "UI_ACH_FIRST_WIN",
			"desc_key": "UI_ACH_FIRST_WIN_DESC",
			"icon": "🏆",
			"accent": Color(0.96, 0.75, 0.20, 1),
		},
		{
			"id": "streak_3",
			"title_key": "UI_ACH_STREAK_3",
			"desc_key": "UI_ACH_STREAK_3_DESC",
			"icon": "🔥",
			"accent": Color(1.0, 0.42, 0.28, 1),
		},
		{
			"id": "ten_matches",
			"title_key": "UI_ACH_TEN_MATCHES",
			"desc_key": "UI_ACH_TEN_MATCHES_DESC",
			"icon": "📚",
			"accent": Color(0.42, 0.361, 1.0, 1),
		},
		{
			"id": "level_5",
			"title_key": "UI_ACH_LEVEL_5",
			"desc_key": "UI_ACH_LEVEL_5_DESC",
			"icon": "🛡️",
			"accent": Color(0.071, 0.769, 0.722, 1),
		},
		{
			"id": "category_explorer",
			"title_key": "UI_ACH_EXPLORER",
			"desc_key": "UI_ACH_EXPLORER_DESC",
			"icon": "🧭",
			"accent": Color(0.91, 0.365, 0.604, 1),
		},
		{
			"id": "streak_5",
			"title_key": "UI_ACH_STREAK_5",
			"desc_key": "UI_ACH_STREAK_5_DESC",
			"icon": "5",
			"accent": Color(1.0, 0.48, 0.22, 1),
		},
		{
			"id": "wins_10",
			"title_key": "UI_ACH_WINS_10",
			"desc_key": "UI_ACH_WINS_10_DESC",
			"icon": "🔟",
			"accent": Color(0.20, 0.86, 0.48, 1),
		},
		{
			"id": "games_25",
			"title_key": "UI_ACH_GAMES_25",
			"desc_key": "UI_ACH_GAMES_25_DESC",
			"icon": "25",
			"accent": Color(0.36, 0.70, 1.0, 1),
		},
		{
			"id": "level_10",
			"title_key": "UI_ACH_LEVEL_10",
			"desc_key": "UI_ACH_LEVEL_10_DESC",
			"icon": "10",
			"accent": Color(0.45, 0.70, 1.0, 1),
		},
		{
			"id": "wins_25",
			"title_key": "UI_ACH_WINS_25",
			"desc_key": "UI_ACH_WINS_25_DESC",
			"icon": "25",
			"accent": Color(0.30, 0.78, 0.55, 1),
		},
		{
			"id": "games_50",
			"title_key": "UI_ACH_GAMES_50",
			"desc_key": "UI_ACH_GAMES_50_DESC",
			"icon": "50",
			"accent": Color(0.55, 0.45, 1.0, 1),
		},
		{
			"id": "categories_4",
			"title_key": "UI_ACH_CATEGORIES_4",
			"desc_key": "UI_ACH_CATEGORIES_4_DESC",
			"icon": "4️⃣",
			"accent": Color(0.91, 0.45, 0.70, 1),
		},
		{
			"id": "score_500",
			"title_key": "UI_ACH_SCORE_500",
			"desc_key": "UI_ACH_SCORE_500_DESC",
			"icon": "⭐",
			"accent": Color(0.941, 0.706, 0.161, 1),
		},
		{
			"id": "perfect_round",
			"title_key": "UI_ACH_PERFECT",
			"desc_key": "UI_ACH_PERFECT_DESC",
			"icon": "💎",
			"accent": Color(0.55, 0.75, 1.0, 1),
		},
		{
			"id": "precision",
			"title_key": "UI_ACH_PRECISION",
			"desc_key": "UI_ACH_PRECISION_DESC",
			"icon": "🎯",
			"accent": Color(0.96, 0.75, 0.20, 1),
		},
		{
			"id": "streak_10",
			"title_key": "UI_ACH_STREAK_10",
			"desc_key": "UI_ACH_STREAK_10_DESC",
			"icon": "10",
			"accent": Color(0.55, 0.32, 1.0, 1),
		},
		{
			"id": "games_100",
			"title_key": "UI_ACH_GAMES_100",
			"desc_key": "UI_ACH_GAMES_100_DESC",
			"icon": "100",
			"accent": Color(0.42, 0.55, 1.0, 1),
		},
		{
			"id": "categories_all",
			"title_key": "UI_ACH_CATEGORIES_ALL",
			"desc_key": "UI_ACH_CATEGORIES_ALL_DESC",
			"icon": "🌐",
			"accent": Color(0.20, 0.72, 0.85, 1),
		},
		{
			"id": "score_1000",
			"title_key": "UI_ACH_SCORE_1000",
			"desc_key": "UI_ACH_SCORE_1000_DESC",
			"icon": "💯",
			"accent": Color(1.0, 0.70, 0.20, 1),
		},
		{
			"id": "precision_90",
			"title_key": "UI_ACH_PRECISION_90",
			"desc_key": "UI_ACH_PRECISION_90_DESC",
			"icon": "90",
			"accent": Color(0.95, 0.55, 0.20, 1),
		},
		{
			"id": "fast",
			"title_key": "UI_ACH_FAST",
			"desc_key": "UI_ACH_FAST_DESC",
			"icon": "⚡",
			"accent": Color(0.96, 0.75, 0.20, 1),
		},
		{
			"id": "expert",
			"title_key": "UI_ACH_EXPERT",
			"desc_key": "UI_ACH_EXPERT_DESC",
			"icon": "⭐",
			"accent": Color(0.30, 0.62, 1.0, 1),
		},
		{
			"id": "golden_brain",
			"title_key": "UI_ACH_GOLDEN_BRAIN",
			"desc_key": "UI_ACH_GOLDEN_BRAIN_DESC",
			"icon": "🧠",
			"accent": Color(0.95, 0.30, 0.55, 1),
		},
		{
			"id": "unbeatable",
			"title_key": "UI_ACH_UNBEATABLE",
			"desc_key": "UI_ACH_UNBEATABLE_DESC",
			"icon": "👑",
			"accent": Color(0.96, 0.75, 0.20, 1),
		},
		{
			"id": "days_7",
			"title_key": "UI_ACH_DAYS_7",
			"desc_key": "UI_ACH_DAYS_7_DESC",
			"icon": "📅",
			"accent": Color(1.0, 0.62, 0.20, 1),
		},
		{
			"id": "days_30",
			"title_key": "UI_ACH_DAYS_30",
			"desc_key": "UI_ACH_DAYS_30_DESC",
			"icon": "🗓",
			"accent": Color(1.0, 0.45, 0.18, 1),
		},
	]


static func is_unlocked(achievement_id: String, stats: Dictionary) -> bool:
	var progress := progress_for(achievement_id, stats)
	return int(progress.get("current", 0)) >= int(progress.get("target", 1))


## Returns { current, target } for progress bars (target always >= 1).
static func progress_for(achievement_id: String, stats: Dictionary) -> Dictionary:
	match achievement_id:
		"streak_10":
			return _clamp_progress(int(stats.get("best_win_streak", 0)), 10)
		"streak_5":
			return _clamp_progress(int(stats.get("best_win_streak", 0)), 5)
		"unbeatable":
			return _clamp_progress(int(stats.get("wins", 0)), 100)
		"expert":
			return _clamp_progress(int(stats.get("level", 1)), 20)
		"precision":
			return _clamp_progress(int(round(float(stats.get("accuracy_percent", 0.0)))), 75)
		"precision_90":
			return _clamp_progress(int(round(float(stats.get("accuracy_percent", 0.0)))), 90)
		"fast":
			return _clamp_progress(1 if stats.get("has_perfect_round", false) else 0, 1)
		"golden_brain":
			return _clamp_progress(int(stats.get("wins", 0)), 50)
		"first_match":
			return _clamp_progress(int(stats.get("games_played", 0)), 1)
		"first_win":
			return _clamp_progress(int(stats.get("wins", 0)), 1)
		"streak_3":
			return _clamp_progress(int(stats.get("best_win_streak", 0)), 3)
		"ten_matches":
			return _clamp_progress(int(stats.get("games_played", 0)), 10)
		"games_25":
			return _clamp_progress(int(stats.get("games_played", 0)), 25)
		"games_50":
			return _clamp_progress(int(stats.get("games_played", 0)), 50)
		"games_100":
			return _clamp_progress(int(stats.get("games_played", 0)), 100)
		"wins_10":
			return _clamp_progress(int(stats.get("wins", 0)), 10)
		"wins_25":
			return _clamp_progress(int(stats.get("wins", 0)), 25)
		"score_500":
			return _clamp_progress(int(stats.get("best_score", 0)), 500)
		"score_1000":
			return _clamp_progress(int(stats.get("best_score", 0)), 1000)
		"perfect_round":
			return _clamp_progress(1 if stats.get("has_perfect_round", false) else 0, 1)
		"level_5":
			return _clamp_progress(int(stats.get("level", 1)), 5)
		"level_10":
			return _clamp_progress(int(stats.get("level", 1)), 10)
		"category_explorer":
			return _clamp_progress(int(stats.get("categories_played", 0)), 2)
		"days_7":
			return _clamp_progress(int(stats.get("best_day_streak", 0)), 7)
		"days_30":
			return _clamp_progress(int(stats.get("best_day_streak", 0)), 30)
		"categories_4":
			return _clamp_progress(int(stats.get("categories_played", 0)), 4)
		"categories_all":
			return _clamp_progress(int(stats.get("categories_played", 0)), 8)
	return {"current": 0, "target": 1}


static func _clamp_progress(current: int, target: int) -> Dictionary:
	var safe_target := maxi(target, 1)
	return {
		"current": clampi(current, 0, safe_target),
		"target": safe_target,
	}
