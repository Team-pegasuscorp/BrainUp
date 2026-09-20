extends RefCounted
## Daily quests: three objectives per local calendar day, generated from the date so
## they are stable across restarts, tracked from real matches and claimed for XP.
## State lives in SaveManager.daily_state (persisted with the rest of the save).

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const ProfileSnapshot = preload("res://scripts/profile/profile_snapshot.gd")

const QUEST_COUNT := 3


static func today_key() -> String:
	var date := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


## Rolls the quests over when the day changed. Returns true if it regenerated.
static func ensure_today() -> bool:
	var state: Dictionary = SaveManager.daily_state
	var today := today_key()
	if str(state.get("date", "")) == today and not (state.get("quests", []) as Array).is_empty():
		return false
	SaveManager.daily_state = {
		"date": today,
		"quests": _generate(today),
		"progress": {},
		"claimed": {},
		"win_streak": 0,
		"categories_played": [],
	}
	SaveManager.save_data()
	return true


static func record_match(
	category_id: String,
	won: bool,
	correct_count: int,
	max_combo: int,
	is_challenge: bool,
) -> void:
	ensure_today()
	var state: Dictionary = SaveManager.daily_state
	var progress: Dictionary = state["progress"]
	var played: Array = state["categories_played"]
	if not played.has(category_id):
		played.append(category_id)
	state["win_streak"] = int(state.get("win_streak", 0)) + 1 if won else 0

	for quest in state["quests"]:
		var quest_id := str(quest["id"])
		var current := int(progress.get(quest_id, 0))
		match str(quest["type"]):
			"category_games":
				if category_id == str(quest.get("category", "")):
					current += 1
			"win_games":
				if won:
					current += 1
			"win_streak":
				current = maxi(current, int(state["win_streak"]))
			"correct_answers":
				current += correct_count
			"combo":
				current = maxi(current, max_combo)
			"play_challenge":
				if is_challenge:
					current += 1
			"categories_variety":
				current = played.size()
			"play_games":
				current += 1
		progress[quest_id] = current


## Quests ready for display (localised text, clamped progress, claim state).
static func get_quests(locale: String) -> Array:
	ensure_today()
	var state: Dictionary = SaveManager.daily_state
	var rows: Array = []
	for quest in state["quests"]:
		var quest_id := str(quest["id"])
		var target := int(quest["target"])
		var current := clampi(int(state["progress"].get(quest_id, 0)), 0, target)
		var type := str(quest["type"])
		var category_name := _category_name(str(quest.get("category", "")), locale)
		var params := {"n": target, "category": category_name}
		rows.append({
			"id": quest_id,
			"type": type,
			"icon": _icon_for(quest),
			"accent": _accent_for(quest),
			"title": _text("UI_DAILY_%s_TITLE" % type.to_upper()).format(params),
			"desc": _text("UI_DAILY_%s_DESC" % type.to_upper()).format(params),
			"current": current,
			"target": target,
			"xp": int(quest["xp"]),
			"completed": current >= target,
			"claimed": bool(state["claimed"].get(quest_id, false)),
		})
	return rows


## Pays out a finished quest once. Returns the XP granted (0 if not claimable).
static func claim(quest_id: String, locale: String) -> int:
	for row in get_quests(locale):
		if str(row["id"]) != quest_id:
			continue
		if not bool(row["completed"]) or bool(row["claimed"]):
			return 0
		SaveManager.daily_state["claimed"][quest_id] = true
		SaveManager.add_xp(int(row["xp"]))
		SaveManager.save_data()
		return int(row["xp"])
	return 0


static func claimable_count(locale: String) -> int:
	var count := 0
	for row in get_quests(locale):
		if bool(row["completed"]) and not bool(row["claimed"]):
			count += 1
	return count


static func seconds_until_reset() -> int:
	var now := Time.get_time_dict_from_system()
	var elapsed := int(now["hour"]) * 3600 + int(now["minute"]) * 60 + int(now["second"])
	return maxi(86400 - elapsed, 0)


static func _generate(day: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day)
	var category_ids: Array[String] = []
	for category in QuestionLoaderScript.get_categories("en"):
		var category_id := str(category.get("id", ""))
		if not category_id.is_empty():
			category_ids.append(category_id)
	if category_ids.is_empty():
		category_ids = ["sport", "cinema", "history"]

	var quests: Array = []
	quests.append({
		"id": "q0", "type": "category_games", "xp": 50,
		"category": category_ids[rng.randi_range(0, category_ids.size() - 1)],
		"target": rng.randi_range(2, 3),
	})
	match rng.randi_range(0, 3):
		0:
			quests.append({"id": "q1", "type": "win_streak", "xp": 100, "target": rng.randi_range(2, 3)})
		1:
			quests.append({"id": "q1", "type": "correct_answers", "xp": 75, "target": 15 + 5 * rng.randi_range(0, 1)})
		2:
			quests.append({"id": "q1", "type": "combo", "xp": 75, "target": rng.randi_range(4, 5)})
		_:
			quests.append({"id": "q1", "type": "win_games", "xp": 75, "target": rng.randi_range(2, 3)})
	match rng.randi_range(0, 2):
		0:
			quests.append({"id": "q2", "type": "play_challenge", "xp": 100, "target": 1})
		1:
			quests.append({"id": "q2", "type": "categories_variety", "xp": 50, "target": 3})
		_:
			quests.append({"id": "q2", "type": "play_games", "xp": 50, "target": 5})
	return quests


static func _category_name(category_id: String, locale: String) -> String:
	if category_id.is_empty():
		return ""
	for category in QuestionLoaderScript.get_categories(locale):
		if str(category.get("id", "")) == category_id:
			return str(category.get("name", category_id))
	return category_id


static func _icon_for(quest: Dictionary) -> String:
	match str(quest["type"]):
		"category_games":
			return ProfileSnapshot.category_icon(str(quest.get("category", "")))
		"win_games":
			return "🏆"
		"win_streak":
			return "🔥"
		"correct_answers":
			return "✅"
		"combo":
			return "⚡"
		"play_challenge":
			return "👥"
		"categories_variety":
			return "🧭"
		_:
			return "🎮"


static func _accent_for(quest: Dictionary) -> Color:
	match str(quest["type"]):
		"category_games":
			return UiTokens.accent_for_category(str(quest.get("category", "")))
		"win_games":
			return Color(0.941, 0.706, 0.161, 1)
		"win_streak":
			return Color(1.0, 0.45, 0.18, 1)
		"correct_answers":
			return UiTokens.FEEDBACK_CORRECT
		"combo":
			return Color(0.36, 0.75, 1.0, 1)
		"play_challenge":
			return Color(0.95, 0.28, 0.55, 1)
		"categories_variety":
			return Color(0.55, 0.35, 0.95, 1)
		_:
			return UiTokens.ACCENT_HOME


static func _text(key: String) -> String:
	return TranslationServer.translate(key)
