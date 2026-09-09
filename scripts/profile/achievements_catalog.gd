class_name AchievementsCatalog
extends RefCounted


static func all() -> Array[Dictionary]:
	## Recent mock set first (profile tile shows the first 6), then the full catalog.
	return [
		{
			"id": "streak_10",
			"title_key": "UI_ACH_STREAK_10",
			"desc_key": "UI_ACH_STREAK_10_DESC",
			"icon": "10",
			"accent": Color(0.55, 0.32, 1.0, 1),
		},
		{
			"id": "unbeatable",
			"title_key": "UI_ACH_UNBEATABLE",
			"desc_key": "UI_ACH_UNBEATABLE_DESC",
			"icon": "👑",
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
			"id": "precision",
			"title_key": "UI_ACH_PRECISION",
			"desc_key": "UI_ACH_PRECISION_DESC",
			"icon": "🎯",
			"accent": Color(0.96, 0.75, 0.20, 1),
		},
		{
			"id": "fast",
			"title_key": "UI_ACH_FAST",
			"desc_key": "UI_ACH_FAST_DESC",
			"icon": "⚡",
			"accent": Color(0.96, 0.75, 0.20, 1),
		},
		{
			"id": "golden_brain",
			"title_key": "UI_ACH_GOLDEN_BRAIN",
			"desc_key": "UI_ACH_GOLDEN_BRAIN_DESC",
			"icon": "🧠",
			"accent": Color(0.95, 0.30, 0.55, 1),
		},
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
	]


static func is_unlocked(achievement_id: String, stats: Dictionary) -> bool:
	match achievement_id:
		"streak_10":
			return stats.get("best_win_streak", 0) >= 10
		"unbeatable":
			return stats.get("wins", 0) >= 100
		"expert":
			return stats.get("level", 1) >= 20
		"precision":
			return float(stats.get("accuracy_percent", 0.0)) >= 75.0
		"fast":
			return stats.get("has_perfect_round", false)
		"golden_brain":
			return stats.get("wins", 0) >= 50
		"first_match":
			return stats.get("games_played", 0) >= 1
		"first_win":
			return stats.get("wins", 0) >= 1
		"streak_3":
			return stats.get("best_win_streak", 0) >= 3
		"ten_matches":
			return stats.get("games_played", 0) >= 10
		"score_500":
			return stats.get("best_score", 0) >= 500
		"perfect_round":
			return stats.get("has_perfect_round", false)
		"level_5":
			return stats.get("level", 1) >= 5
		"category_explorer":
			return stats.get("categories_played", 0) >= 2
	return false
