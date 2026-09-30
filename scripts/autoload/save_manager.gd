extends Node

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")
const AchievementsCatalogScript = preload("res://scripts/profile/achievements_catalog.gd")
const DailyQuestsScript = preload("res://scripts/profile/daily_quests.gd")
const DailyChallengeScript = preload("res://scripts/profile/daily_challenge.gd")
const TrophySystemScript = preload("res://scripts/profile/trophy_system.gd")

const SAVE_PATH: String = "user://save.json"
## Legacy custom photo (before avatars became a fixed set); deleted on reset.
const PROFILE_AVATAR_PATH: String = "user://profile_avatar.png"
## Avatars the player can pick, from assets/avatars/demo/.
const PROFILE_AVATAR_IDS: Array[String] = GameAssets.DEMO_AVATAR_SLUGS
const DEFAULT_AVATAR_PATH: String = "res://assets/ui/default_avatar.svg"
const MAX_MATCH_HISTORY: int = 30
## Global player level: exponential XP bar (1→2 = 100; growth tuned softer than ×2.5).
const XP_LEVEL_BASE: int = 100
const XP_LEVEL_GROWTH: float = 2.15

var player_name: String = UiTokens.DEFAULT_PLAYER_NAME
## Chosen avatar id from PROFILE_AVATAR_IDS ("" = default avatar).
var profile_avatar_id: String = ""
var preferred_locale: String = ""
var email: String = ""
## True after the player confirms ownership of `email` (mail verification).
var email_verified: bool = false
var level: int = 1
## Lifetime XP earned (never decreases on level-up).
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
## Competitive trophies (versus matches) — drives league badge.
var trophies: int = 0
## Consecutive versus wins (resets on loss / draw). Used for streak cup bonuses.
var versus_win_streak: int = 0
## Consecutive versus losses (resets on win / draw). Consolation at 5.
var versus_loss_streak: int = 0
## Last settle breakdown (for UI); not persisted.
var last_trophy_match_delta: int = 0
var last_trophy_streak_bonus: int = 0
var last_trophy_loss_consolation: int = 0
var last_settled_trophy_match_id: String = ""
## Challenge codes already settled for competitive trophies (live only).
var settled_trophy_matches: Array = []
## Head-to-head vs friends: { friend_key: {wins, losses, draws, settled: [match_ids]} }.
## Friend challenges never award trophies (anti-farm); only this counter + XP.
var friend_rivalries: Dictionary = {}
var daily_state: Dictionary = {}
var daily_challenge_result: Dictionary = {}
## Best survival / time-attack runs: { mode: { category: {score, correct} } }.
var mode_records: Dictionary = {}
## Shop: soft currency, bought item ids and the equipped frame (see ShopCatalog).
## Local only for now — the server must own these before real purchases.
var coins: int = ShopCatalog.DEMO_START_COINS if ShopCatalog.SHOW_DEMO_ITEMS else 0
var owned_items: Array = []
var equipped_frame: String = ""
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
	var owned_raw: Variant = parsed.get("owned_items", [])
	owned_items = owned_raw if typeof(owned_raw) == TYPE_ARRAY else []
	coins = maxi(int(parsed.get("coins", coins)), 0)
	equipped_frame = str(parsed.get("equipped_frame", ""))
	if not is_item_owned(equipped_frame):
		equipped_frame = ""
	profile_avatar_id = str(parsed.get("profile_avatar_id", ""))
	if not can_use_avatar(profile_avatar_id):
		profile_avatar_id = ""
	preferred_locale = parsed.get("preferred_locale", preferred_locale)
	email = str(parsed.get("email", email))
	email_verified = bool(parsed.get("email_verified", email_verified))
	level = int(parsed.get("level", level))
	xp = int(parsed.get("xp", xp))
	if not bool(parsed.get("xp_is_total", false)):
		xp = _total_xp_to_reach_level(level) + xp
	_sync_level_from_total_xp()
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
	if parsed.has("trophies"):
		trophies = maxi(int(parsed.get("trophies", 0)), 0)
	else:
		## One-shot migrate: former UI used best_score as fake trophies.
		trophies = _best_score_global()
	versus_win_streak = maxi(int(parsed.get("versus_win_streak", 0)), 0)
	versus_loss_streak = maxi(int(parsed.get("versus_loss_streak", 0)), 0)
	var settled_raw: Variant = parsed.get("settled_trophy_matches", [])
	settled_trophy_matches = settled_raw if typeof(settled_raw) == TYPE_ARRAY else []
	var rivalries_raw: Variant = parsed.get("friend_rivalries", {})
	friend_rivalries = rivalries_raw if typeof(rivalries_raw) == TYPE_DICTIONARY else {}
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
		"xp_is_total": true,
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
		"trophies": trophies,
		"versus_win_streak": versus_win_streak,
		"versus_loss_streak": versus_loss_streak,
		"settled_trophy_matches": settled_trophy_matches,
		"friend_rivalries": friend_rivalries,
		"daily_state": daily_state,
		"daily_challenge_result": daily_challenge_result,
		"mode_records": mode_records,
		"coins": coins,
		"owned_items": owned_items,
		"equipped_frame": equipped_frame,
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


func get_xp_in_current_level() -> int:
	return maxi(0, xp - _total_xp_to_reach_level(level))


func get_xp_progress_ratio() -> float:
	var needed := _xp_for_next_level()
	if needed <= 0:
		return 0.0
	return clampf(float(get_xp_in_current_level()) / float(needed), 0.0, 1.0)


func has_custom_avatar() -> bool:
	return not profile_avatar_id.is_empty()


func get_profile_avatar_texture() -> Texture2D:
	return avatar_texture_for(profile_avatar_id)


## Texture for an avatar id; "" or an unknown id gives the default avatar.
func avatar_texture_for(avatar_id: String) -> Texture2D:
	var shop_item := ShopCatalog.get_item(avatar_id)
	if str(shop_item.get("kind", "")) == ShopCatalog.KIND_AVATAR:
		var shop_tex := ShopCatalog.avatar_texture(shop_item)
		if shop_tex != null:
			return shop_tex
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
	profile_avatar_id = avatar_id if can_use_avatar(avatar_id) else ""
	save_data()


## Free starter avatars, or a shop avatar the player bought.
func can_use_avatar(avatar_id: String) -> bool:
	return PROFILE_AVATAR_IDS.has(avatar_id) or (
		str(ShopCatalog.get_item(avatar_id).get("kind", "")) == ShopCatalog.KIND_AVATAR
		and is_item_owned(avatar_id)
	)


## Free catalogue items (price 0) count as owned.
func is_item_owned(item_id: String) -> bool:
	var item := ShopCatalog.get_item(item_id)
	if item.is_empty():
		return false
	return int(item.get("price", 0)) <= 0 or owned_items.has(item_id)


## Local purchase. Returns false if unknown, already owned or too expensive.
## TODO(server): move to a backend route once coins are earned server-side.
func buy_item(item_id: String) -> bool:
	var item := ShopCatalog.get_item(item_id)
	if item.is_empty() or is_item_owned(item_id):
		return false
	var price := int(item.get("price", 0))
	if coins < price:
		return false
	coins -= price
	owned_items.append(item_id)
	save_data()
	return true


func get_equipped_frame() -> String:
	return equipped_frame if not equipped_frame.is_empty() else ShopCatalog.default_frame_id()


func equip_item(item_id: String) -> void:
	if not is_item_owned(item_id):
		return
	match str(ShopCatalog.get_item(item_id).get("kind", "")):
		ShopCatalog.KIND_FRAME:
			equipped_frame = item_id
			save_data()
		ShopCatalog.KIND_AVATAR:
			set_profile_avatar_id(item_id)


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


## Clash-style settle for a finished 1v1. Returns total signed delta incl. streak bonus
## (0 if already settled / invalid). Opponent trophies unknown → equal baseline.
func settle_versus_trophies(
	match_id: String,
	my_score: int,
	opponent_score: int,
	opponent_trophies: int = -1
) -> int:
	var id := str(match_id).strip_edges()
	if id.is_empty():
		return 0
	## Idempotent: same match can be queried again for UI without wiping the breakdown.
	if settled_trophy_matches.has(id):
		if id == last_settled_trophy_match_id:
			return last_trophy_match_delta + last_trophy_streak_bonus + last_trophy_loss_consolation
		return 0
	var opp_cups := opponent_trophies if opponent_trophies >= 0 else trophies
	var match_delta := TrophySystemScript.calculate_delta(trophies, opp_cups, my_score, opponent_score)
	last_trophy_match_delta = match_delta
	last_trophy_streak_bonus = 0
	last_trophy_loss_consolation = 0

	if my_score > opponent_score:
		versus_win_streak += 1
		versus_loss_streak = 0
		last_trophy_streak_bonus = TrophySystemScript.streak_bonus(versus_win_streak)
	elif my_score < opponent_score:
		versus_win_streak = 0
		versus_loss_streak += 1
		last_trophy_loss_consolation = TrophySystemScript.loss_streak_consolation(versus_loss_streak)
	else:
		## Draw breaks both streaks.
		versus_win_streak = 0
		versus_loss_streak = 0

	var total := match_delta + last_trophy_streak_bonus + last_trophy_loss_consolation
	trophies = maxi(trophies + total, 0)
	settled_trophy_matches.append(id)
	last_settled_trophy_match_id = id
	while settled_trophy_matches.size() > 80:
		settled_trophy_matches.pop_front()
	save_data()
	return total


## Friend-challenge H2H (no trophies). Idempotent per match_id.
func record_friend_rivalry(
	friend_key: String,
	my_score: int,
	opponent_score: int,
	match_id: String
) -> Dictionary:
	var key := str(friend_key).strip_edges()
	var id := str(match_id).strip_edges()
	if key.is_empty() or id.is_empty():
		return get_friend_rivalry(key)
	var row: Dictionary = get_friend_rivalry(key)
	var settled: Array = row.get("settled", [])
	if typeof(settled) != TYPE_ARRAY:
		settled = []
	if settled.has(id):
		return row
	if my_score > opponent_score:
		row["wins"] = int(row.get("wins", 0)) + 1
	elif my_score < opponent_score:
		row["losses"] = int(row.get("losses", 0)) + 1
	else:
		row["draws"] = int(row.get("draws", 0)) + 1
	settled.append(id)
	while settled.size() > 40:
		settled.pop_front()
	row["settled"] = settled
	friend_rivalries[key] = row
	save_data()
	return row


func get_friend_rivalry(friend_key: String) -> Dictionary:
	var key := str(friend_key).strip_edges()
	if key.is_empty():
		return {"wins": 0, "losses": 0, "draws": 0, "settled": []}
	var raw: Variant = friend_rivalries.get(key, {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {"wins": 0, "losses": 0, "draws": 0, "settled": []}
	return {
		"wins": int(raw.get("wins", 0)),
		"losses": int(raw.get("losses", 0)),
		"draws": int(raw.get("draws", 0)),
		"settled": raw.get("settled", []),
	}


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
		"xp": get_xp_in_current_level(),
		"xp_needed": _xp_for_next_level(),
		"unlocked": unlocked,
	}


func get_achievement_stats() -> Dictionary:
	var questions := 0
	var correct := 0
	var categories_played := 0
	var category_correct := {}
	for category_id in category_stats.keys():
		var stats: Dictionary = category_stats[category_id]
		questions += int(stats.get("total_questions", 0))
		correct += int(stats.get("total_correct", 0))
		category_correct[category_id] = int(stats.get("total_correct", 0))
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
		"category_correct": category_correct,
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
	if amount <= 0:
		return
	xp += amount
	_sync_level_from_total_xp()


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


func _xp_cost_for_level(from_level: int) -> int:
	return maxi(1, int(round(float(XP_LEVEL_BASE) * pow(XP_LEVEL_GROWTH, from_level - 1))))


func _xp_for_next_level() -> int:
	return _xp_cost_for_level(level)


func _total_xp_to_reach_level(target_level: int) -> int:
	var total := 0
	for n in range(1, maxi(target_level, 1)):
		total += _xp_cost_for_level(n)
	return total


func _sync_level_from_total_xp() -> void:
	var lvl := 1
	while xp >= _total_xp_to_reach_level(lvl + 1):
		lvl += 1
	level = lvl
