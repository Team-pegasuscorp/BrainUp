class_name LeaderboardSnapshot
extends RefCounted

const PlayerRanks = preload("res://scripts/profile/player_ranks.gd")
const QuestionLoaderScript = preload("res://scripts/quiz/question_loader.gd")

## Demo names must match assets/avatars/demo/*.png slugs where possible.
const DEMO_GLOBAL_NAMES: Array[String] = [
	"Lucas", "Emma", "Theo", "Hugo", "Noah", "Léa", "Chloé", "Adam", "Sarah", "Maya", "Yanis", "Jade",
]
const DEMO_FRIEND_NAMES: Array[String] = [
	"Lucas", "Emma", "Theo", "Hugo", "Noah", "Léa", "Chloé", "Adam", "Sarah", "Maya", "Yanis",
]
const DEMO_FRIENDS_MIN := 12
const USE_DEMO_WHEN_EMPTY: bool = true
## Force the padded global demo (player at DEMO_PLAYER_RANK) even if the save has games.
const FORCE_DEMO_BOARD: bool = true

## After the podium: show ranks 4..6, then optionally a gap + context around the player.
const REST_NEAR_COUNT := 3
const REST_CONTEXT := 2
## Boards this small show every row after the podium (no gap).
const REST_FULL_MAX := 12
## Global demo pads the board so deep-rank UX is visible; player is forced to this rank.
const DEMO_GLOBAL_PAD_TO := 520
const DEMO_PLAYER_RANK := 20


static func build(category_filter: String, locale: String) -> Dictionary:
	var filter := _normalize_filter(category_filter)
	var entries: Array[Dictionary] = []

	if FORCE_DEMO_BOARD or (USE_DEMO_WHEN_EMPTY and _total_games_played() == 0):
		entries = _demo_entries(filter, locale, DEMO_GLOBAL_NAMES, true, true)
	else:
		SaveManager.ensure_leaderboard_rivals()
		entries = _live_entries(filter, locale)

	return _pack_board(entries, filter)


static func build_friends(locale: String) -> Dictionary:
	var entries: Array[Dictionary] = []
	if FORCE_DEMO_BOARD or (USE_DEMO_WHEN_EMPTY and _total_games_played() == 0):
		entries = _demo_entries("all", locale, DEMO_FRIEND_NAMES, true, false)
	else:
		## Friends board reuses rival subset until online friends API exists.
		SaveManager.ensure_leaderboard_rivals()
		entries.append(_player_entry("all", locale))
		var rivals: Array = SaveManager.leaderboard_rivals
		var need := maxi(DEMO_FRIENDS_MIN - 1, 0)
		var limit := mini(rivals.size(), need)
		for i in range(limit):
			if typeof(rivals[i]) != TYPE_DICTIONARY:
				continue
			entries.append(_rival_entry(rivals[i], "all", locale))
	return _pack_board(entries, "friends")


static func available_filters(locale: String) -> Array[Dictionary]:
	var filters: Array[Dictionary] = [
		{"id": "all", "label": _tr("UI_LEADERBOARD_FILTER_ALL")},
	]
	for category in QuestionLoaderScript.get_categories(locale):
		filters.append({
			"id": str(category.get("id", "")),
			"label": str(category.get("name", "")),
		})
	return filters


static func _pack_board(entries: Array[Dictionary], filter: String) -> Dictionary:
	entries.sort_custom(_sort_entries)
	for index in range(entries.size()):
		entries[index]["rank"] = index + 1

	var player_rank := 0
	for entry in entries:
		if entry.get("is_player", false):
			player_rank = int(entry.get("rank", 0))
			break

	var podium: Array[Dictionary] = []
	for index in range(mini(3, entries.size())):
		podium.append(entries[index])

	return {
		"entries": entries,
		"podium": podium,
		"rest": _windowed_rest(entries, player_rank),
		"player_rank": player_rank,
		"total_count": entries.size(),
		"is_demo": FORCE_DEMO_BOARD or (USE_DEMO_WHEN_EMPTY and _total_games_played() == 0),
		"filter": filter,
	}


## Always keep top 3 on the podium. For the list:
## - small boards → show everyone after #3
## - player near the top → contiguous rows (no gap)
## - player far down (e.g. #504) → ranks 4–6, then "…", then a window around the player
static func _windowed_rest(entries: Array[Dictionary], player_rank: int) -> Array:
	var rest: Array = []
	var total := entries.size()
	if total <= 3:
		return rest

	if total <= REST_FULL_MAX:
		for index in range(3, total):
			rest.append(entries[index])
		return rest

	var near_last_rank := mini(3 + REST_NEAR_COUNT, total)
	for rank in range(4, near_last_rank + 1):
		rest.append(entries[rank - 1])

	if player_rank <= 0:
		## No player on the board: a short continuation after the near block.
		for rank in range(near_last_rank + 1, mini(10, total) + 1):
			rest.append(entries[rank - 1])
		return rest

	if player_rank <= 3:
		## Player is already on the podium — show a short chase pack.
		for rank in range(near_last_rank + 1, mini(10, total) + 1):
			rest.append(entries[rank - 1])
		return rest

	var ctx_first := maxi(player_rank - REST_CONTEXT, 4)
	var ctx_last := mini(player_rank + REST_CONTEXT, total)

	if ctx_first <= near_last_rank + 1:
		## Player window touches the near block → keep one contiguous list.
		for rank in range(near_last_rank + 1, ctx_last + 1):
			rest.append(entries[rank - 1])
		return rest

	rest.append({
		"is_gap": true,
		"from_rank": near_last_rank + 1,
		"to_rank": ctx_first - 1,
	})
	for rank in range(ctx_first, ctx_last + 1):
		rest.append(entries[rank - 1])
	return rest


static func _normalize_filter(category_filter: String) -> String:
	if category_filter.is_empty() or category_filter == "all":
		return "all"
	return category_filter


static func _live_entries(filter: String, locale: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	entries.append(_player_entry(filter, locale))
	for rival in SaveManager.leaderboard_rivals:
		if typeof(rival) != TYPE_DICTIONARY:
			continue
		entries.append(_rival_entry(rival, filter, locale))
	return entries


static func _player_entry(filter: String, locale: String) -> Dictionary:
	var score := SaveManager.get_leaderboard_score(filter)
	var level := SaveManager.level
	return {
		"id": "player",
		"name": SaveManager.player_name,
		"score": score,
		"level": level,
		"rank_title_key": PlayerRanks.title_for_level(level),
		"is_player": true,
		"category_id": filter,
		"category_name": _category_label(filter, locale),
		"country": "FR",
	}


static func _rival_entry(rival: Dictionary, filter: String, locale: String) -> Dictionary:
	var scores: Dictionary = rival.get("scores", {})
	var score := int(scores.get(filter, scores.get("all", 0)))
	var level := int(rival.get("level", 1))
	return {
		"id": str(rival.get("id", rival.get("name", "rival"))),
		"name": str(rival.get("name", "Player")),
		"score": score,
		"level": level,
		"rank_title_key": PlayerRanks.title_for_level(level),
		"is_player": false,
		"category_id": filter,
		"category_name": _category_label(filter, locale),
		"country": "FR",
	}


static func _demo_entries(
	filter: String,
	locale: String,
	names: Array[String],
	include_player: bool,
	pad_global: bool = false
) -> Array[Dictionary]:
	## Mock-like point scale for the competitive board.
	var base_scores := [3284, 2976, 2843, 2650, 2488, 2310, 2144, 1998, 1850, 1720, 1605, 1490]
	var entries: Array[Dictionary] = []
	for index in range(names.size()):
		var level: int = clampi(32 - index, 9, 32)
		entries.append({
			"id": "demo_%d" % index,
			"name": names[index],
			"score": int(base_scores[index % base_scores.size()]),
			"level": level,
			"rank_title_key": PlayerRanks.title_for_level(level),
			"is_player": false,
			"category_id": filter,
			"category_name": _category_label(filter, locale),
			"country": "FR",
		})

	if pad_global and include_player:
		## Guarantee exact DEMO_PLAYER_RANK: N-1 above, player, then pad below.
		var target_rank := clampi(DEMO_PLAYER_RANK, 1, DEMO_GLOBAL_PAD_TO)
		var need_above := maxi(target_rank - 1 - entries.size(), 0)
		var next_score := 1480
		for filler_index in range(need_above):
			entries.append(_demo_filler_entry(
				filter, locale, filler_index + 1, next_score, clampi(18 - int(filler_index / 40), 5, 18)
			))
			next_score -= 2

		var player_score := next_score - 1
		var player_level := maxi(SaveManager.level, 8)
		entries.append({
			"id": "player",
			"name": SaveManager.player_name,
			"score": player_score,
			"level": player_level,
			"rank_title_key": PlayerRanks.title_for_level(player_level),
			"is_player": true,
			"category_id": filter,
			"category_name": _category_label(filter, locale),
			"country": "FR",
		})

		var below_score := player_score - 2
		var filler_index := need_above
		while entries.size() < DEMO_GLOBAL_PAD_TO:
			filler_index += 1
			entries.append(_demo_filler_entry(
				filter, locale, filler_index, below_score, clampi(18 - int(filler_index / 40), 5, 18)
			))
			below_score = maxi(below_score - 2, 10)
		return entries

	if include_player:
		entries.append({
			"id": "player",
			"name": SaveManager.player_name,
			"score": 1588,
			"level": maxi(SaveManager.level, 12),
			"rank_title_key": PlayerRanks.title_for_level(maxi(SaveManager.level, 12)),
			"is_player": true,
			"category_id": filter,
			"category_name": _category_label(filter, locale),
			"country": "FR",
		})
	return entries


static func _demo_filler_entry(
	filter: String,
	locale: String,
	filler_index: int,
	score: int,
	level: int
) -> Dictionary:
	return {
		"id": "demo_pad_%d" % filler_index,
		"name": "Player %d" % (1000 + filler_index),
		"score": score,
		"level": level,
		"rank_title_key": PlayerRanks.title_for_level(level),
		"is_player": false,
		"category_id": filter,
		"category_name": _category_label(filter, locale),
		"country": "FR",
	}


static func _sort_entries(a: Dictionary, b: Dictionary) -> bool:
	var score_a := int(a.get("score", 0))
	var score_b := int(b.get("score", 0))
	if score_a == score_b:
		return str(a.get("name", "")) < str(b.get("name", ""))
	return score_a > score_b


static func _total_games_played() -> int:
	var total := 0
	for category_id in SaveManager.category_stats.keys():
		total += int(SaveManager.category_stats[category_id].get("games_played", 0))
	return total


static func _category_label(filter: String, locale: String) -> String:
	if filter == "all" or filter == "friends":
		return _tr("UI_LEADERBOARD_FILTER_ALL")
	for category in QuestionLoaderScript.get_categories(locale):
		if str(category.get("id", "")) == filter:
			return str(category.get("name", filter))
	return filter


static func _tr(key: String) -> String:
	return TranslationServer.translate(key)
