extends Node

signal player_ready(player_id: String)
signal leaderboard_received(category: String, entries: Array)
signal leaderboard_failed(category: String)
signal challenge_created(challenge: Dictionary)
signal challenge_create_failed
signal challenge_joined(challenge: Dictionary)
signal challenge_join_failed(error_code: int)
signal challenge_fetched(challenge: Dictionary)
signal challenge_fetch_failed(code: String)
signal live_match_found(data: Dictionary)
signal live_question(data: Dictionary)
signal live_reveal(data: Dictionary)
signal live_match_over(data: Dictionary)
signal live_error(reason: String)
## Ranked duel flow (mode queue): draft result, start of play, opponent's live score
## in time attack, and "your clock ran out, waiting for the opponent".
signal live_draft_result(data: Dictionary)
signal live_match_start(data: Dictionary)
signal live_opponent_progress(data: Dictionary)
signal live_player_done(data: Dictionary)
## Synced modes: the opponent answered (not what) / tapped "ready" after the explanation.
signal live_opponent_answered(data: Dictionary)
signal live_opponent_ready(data: Dictionary)
## Battle pass (server state; see brainup-backend app/battle_pass.py).
signal pass_received(state: Dictionary)
signal pass_failed
signal pass_reward_claimed(result: Dictionary)
signal pass_claim_failed(reason: String)
signal live_search_range_changed(trophy_range: int)
signal daily_challenge_received(data: Dictionary)
signal daily_challenge_failed
signal daily_result_submitted(data: Dictionary)
signal daily_leaderboard_received(data: Dictionary)
signal daily_leaderboard_failed

## Local dev backend (docker compose in ~/Documents/quizz-backend).
## Swap this for the Hetzner domain once the backend is migrated (Phase 7).
const BASE_URL: String = "http://127.0.0.1:8000"
const DEVICE_ID_PATH: String = "user://device_id.txt"
const LiveMatchmakingScript = preload("res://scripts/profile/live_matchmaking.gd")

var player_id: String = ""

var _players_request: HTTPRequest
var _leaderboard_request: HTTPRequest
var _matches_request: HTTPRequest
var _challenges_request: HTTPRequest
var _challenge_result_request: HTTPRequest
var _daily_request: HTTPRequest
var _daily_result_request: HTTPRequest
var _daily_board_request: HTTPRequest
var _cosmetics_request: HTTPRequest
var _pass_request: HTTPRequest
var _pass_write_request: HTTPRequest
## Last pass state received (empty until the first fetch).
var pass_state: Dictionary = {}
## A fetch was asked while another was running: fetch again right after it.
var _pass_refetch: bool = false
## Another look change arrived while a sync was in flight: send again after it.
var _cosmetics_dirty: bool = false

## Server's answer to today's submission ({rank, score, ...}); lets the results
## screen show the rank even if the reply lands before the screen is up.
var last_daily_result: Dictionary = {}

var _live_socket: WebSocketPeer = null
var _live_pending_join: Variant = null
## Trophy-first queue: start narrow, widen if no opponent.
var _live_searching: bool = false
var _live_trophy_range: int = LiveMatchmakingScript.initial_range()
var _live_widen_elapsed: float = 0.0
## Public mirror for UI (searching label).
var live_trophy_range: int = LiveMatchmakingScript.initial_range()


func _process(_delta: float) -> void:
	if _live_socket == null:
		return

	_live_socket.poll()
	var state := _live_socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if _live_pending_join != null:
			_live_socket.send_text(JSON.stringify(_live_pending_join))
			_live_pending_join = null
		if _live_searching:
			_tick_live_widen(_delta)
		while _live_socket != null and _live_socket.get_available_packet_count() > 0:
			_handle_live_message(_live_socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		_live_socket = null
		_live_pending_join = null
		_live_searching = false
		live_error.emit("disconnected")


## `mode` ("classic", "survival", "time_attack") queues a ranked duel whose category
## is drafted after pairing; without it the old fixed-category classic match is used.
func start_live_matchmaking(category: String, mode: String = "") -> void:
	if player_id.is_empty():
		live_error.emit("no_player")
		return

	stop_live_matchmaking()
	var ws_url := BASE_URL.replace("http://", "ws://").replace("https://", "wss://") + "/ws/live"
	_live_socket = WebSocketPeer.new()
	if _live_socket.connect_to_url(ws_url) != OK:
		_live_socket = null
		live_error.emit("connect_failed")
		return

	_live_trophy_range = LiveMatchmakingScript.initial_range()
	live_trophy_range = _live_trophy_range
	_live_widen_elapsed = 0.0
	_live_searching = true
	## Prefer opponents near our trophy count; server must honor `trophy_range`
	## and `widen_search` (see docs/LIVE_MATCHMAKING_TROPHIES.md).
	_live_pending_join = {
		"type": "join_queue",
		"player_id": player_id,
		"locale": LocaleManager.get_content_locale(),
		"trophies": SaveManager.trophies,
		"trophy_range": _live_trophy_range,
	}
	if mode.is_empty():
		_live_pending_join["category"] = category
	else:
		_live_pending_join["mode"] = mode
	live_search_range_changed.emit(_live_trophy_range)


func send_live_answer(index: int, selected_index: int) -> void:
	if _live_socket == null:
		return
	_live_socket.send_text(JSON.stringify({
		"type": "answer",
		"index": index,
		"selected_index": selected_index,
	}))


## Done reading the explanation of question `index` (the server moves on when both are).
func send_live_ready(index: int) -> void:
	if _live_socket == null:
		return
	_live_socket.send_text(JSON.stringify({"type": "ready", "index": index}))


func send_draft_vote(category: String) -> void:
	if _live_socket == null:
		return
	_live_socket.send_text(JSON.stringify({"type": "draft_vote", "category": category}))


func stop_live_matchmaking() -> void:
	_live_searching = false
	_live_widen_elapsed = 0.0
	if _live_socket != null:
		_live_socket.close()
		_live_socket = null
	_live_pending_join = null


func _tick_live_widen(delta: float) -> void:
	if LiveMatchmakingScript.is_max_range(_live_trophy_range):
		return
	_live_widen_elapsed += delta
	if _live_widen_elapsed < LiveMatchmakingScript.STEP_SECONDS:
		return
	_live_widen_elapsed = 0.0
	var next_range := LiveMatchmakingScript.next_range(_live_trophy_range)
	if next_range == _live_trophy_range:
		return
	_live_trophy_range = next_range
	live_trophy_range = _live_trophy_range
	_live_socket.send_text(JSON.stringify({
		"type": "widen_search",
		"trophies": SaveManager.trophies,
		"trophy_range": _live_trophy_range,
	}))
	live_search_range_changed.emit(_live_trophy_range)


func _handle_live_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	match str(parsed.get("type", "")):
		"match_found":
			_live_searching = false
			live_match_found.emit(parsed)
		"question":
			live_question.emit(parsed)
		"reveal":
			live_reveal.emit(parsed)
		"draft_result":
			live_draft_result.emit(parsed)
		"match_start":
			live_match_start.emit(parsed)
		"opponent_progress":
			live_opponent_progress.emit(parsed)
		"player_done":
			live_player_done.emit(parsed)
		"opponent_answered":
			live_opponent_answered.emit(parsed)
		"opponent_ready":
			live_opponent_ready.emit(parsed)
		"match_over":
			live_match_over.emit(parsed)
			stop_live_matchmaking()
		"match_aborted":
			live_error.emit("aborted")
			stop_live_matchmaking()


func _ready() -> void:
	_players_request = _make_request_node()
	_leaderboard_request = _make_request_node()
	_matches_request = _make_request_node()
	_challenges_request = _make_request_node()
	_challenge_result_request = _make_request_node()
	_daily_request = _make_request_node()
	_daily_result_request = _make_request_node()
	_daily_board_request = _make_request_node()
	_cosmetics_request = _make_request_node()
	_pass_request = _make_request_node()
	_pass_write_request = _make_request_node()
	SaveManager.cosmetics_changed.connect(_sync_cosmetics)
	_register_player()


func fetch_leaderboard(category: String) -> void:
	var url := "%s/leaderboard?category=%s" % [BASE_URL, category.uri_encode()]
	if _leaderboard_request.request(url) != OK:
		leaderboard_failed.emit(category)
		return

	var result: Array = await _leaderboard_request.request_completed
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		leaderboard_failed.emit(category)
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_ARRAY:
		leaderboard_failed.emit(category)
		return

	leaderboard_received.emit(category, parsed)


## Today's shared challenge ({date, category_id, seed}); the server owns the rotation.
func fetch_daily_challenge() -> void:
	if _daily_request.request("%s/daily-challenge" % BASE_URL) != OK:
		daily_challenge_failed.emit()
		return

	var result: Array = await _daily_request.request_completed
	var response_code: int = result[1]
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if response_code != 200 or typeof(parsed) != TYPE_DICTIONARY \
			or str(parsed.get("category_id", "")).is_empty() or str(parsed.get("seed", "")).is_empty():
		daily_challenge_failed.emit()
		return

	daily_challenge_received.emit(parsed)


## Idempotent on the server: only the first result of the day is kept, so it is
## safe to resend a stored result (e.g. after playing offline).
func submit_daily_result(score: int, correct_count: int, total_count: int, max_combo: int) -> void:
	if player_id.is_empty():
		return
	var payload := {
		"player_id": player_id,
		"score": score,
		"correct_count": correct_count,
		"total_count": total_count,
		"max_combo": max_combo,
	}
	if _daily_result_request.request(
		"%s/daily-challenge/result" % BASE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	) != OK:
		return

	var result: Array = await _daily_result_request.request_completed
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if result[1] != 200 or typeof(parsed) != TYPE_DICTIONARY:
		return
	last_daily_result = parsed
	daily_result_submitted.emit(parsed)


func fetch_daily_leaderboard() -> void:
	var url := "%s/daily-challenge/leaderboard" % BASE_URL
	if not player_id.is_empty():
		url += "?player_id=%s" % player_id.uri_encode()
	if _daily_board_request.request(url) != OK:
		daily_leaderboard_failed.emit()
		return

	var result: Array = await _daily_board_request.request_completed
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if result[1] != 200 or typeof(parsed) != TYPE_DICTIONARY:
		daily_leaderboard_failed.emit()
		return
	daily_leaderboard_received.emit(parsed)


func submit_match(
	category_id: String,
	score: int,
	correct_count: int,
	total_count: int,
	max_combo: int,
	won: bool,
) -> void:
	if player_id.is_empty():
		return

	var payload := {
		"player_id": player_id,
		"category": category_id,
		"score": score,
		"correct_count": correct_count,
		"total_count": total_count,
		"max_combo": max_combo,
		"won": won,
	}
	_matches_request.request(
		"%s/matches" % BASE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)


func create_challenge(category: String) -> void:
	if player_id.is_empty():
		challenge_create_failed.emit()
		return

	var payload := {"challenger_id": player_id, "category": category}
	var sent := _challenges_request.request(
		"%s/challenges" % BASE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if sent != OK:
		challenge_create_failed.emit()
		return

	var result: Array = await _challenges_request.request_completed
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		challenge_create_failed.emit()
		return

	challenge_created.emit(parsed)


func join_challenge(code: String) -> void:
	if player_id.is_empty():
		challenge_join_failed.emit(0)
		return

	var payload := {"player_id": player_id}
	var sent := _challenges_request.request(
		"%s/challenges/%s/join" % [BASE_URL, code.uri_encode()],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if sent != OK:
		challenge_join_failed.emit(0)
		return

	var result: Array = await _challenges_request.request_completed
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		challenge_join_failed.emit(response_code)
		return

	challenge_joined.emit(parsed)


func fetch_challenge(code: String) -> void:
	var sent := _challenges_request.request("%s/challenges/%s" % [BASE_URL, code.uri_encode()])
	if sent != OK:
		challenge_fetch_failed.emit(code)
		return

	var result: Array = await _challenges_request.request_completed
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code != 200 or typeof(parsed) != TYPE_DICTIONARY:
		challenge_fetch_failed.emit(code)
		return

	challenge_fetched.emit(parsed)


func submit_challenge_result(code: String, score: int, correct_count: int) -> void:
	if player_id.is_empty():
		return

	var payload := {"player_id": player_id, "score": score, "correct_count": correct_count}
	_challenge_result_request.request(
		"%s/challenges/%s/result" % [BASE_URL, code.uri_encode()],
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)


func _register_player() -> void:
	var device_id := _load_or_create_device_id()
	var payload := {
		"device_id": device_id,
		"display_name": SaveManager.player_name,
		"cosmetics": SaveManager.get_cosmetics(),
	}
	var sent := _players_request.request(
		"%s/players" % BASE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if sent != OK:
		return

	var result: Array = await _players_request.request_completed
	var response_code: int = result[1]
	var body: PackedByteArray = result[3]
	if response_code != 200:
		return

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	player_id = str(parsed.get("id", ""))
	if not player_id.is_empty():
		player_ready.emit(player_id)


func fetch_pass() -> void:
	if _pass_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_pass_refetch = true
		return
	var url := "%s/pass?device_id=%s" % [BASE_URL, _load_or_create_device_id().uri_encode()]
	if _pass_request.request(url) != OK:
		pass_failed.emit()
		return
	var result: Array = await _pass_request.request_completed
	var parsed: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if int(result[1]) != 200 or typeof(parsed) != TYPE_DICTIONARY:
		pass_failed.emit()
		return
	pass_state = parsed
	pass_received.emit(pass_state)
	if _pass_refetch:
		_pass_refetch = false
		fetch_pass()


## Claims one reached tier; the reward is applied to the local inventory, then the
## state is refreshed.
func claim_pass_reward(tier: int, track: String) -> void:
	var body := {"device_id": _load_or_create_device_id(), "tier": tier, "track": track}
	var parsed: Variant = await _pass_post("/pass/claim", body)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("reward"):
		pass_claim_failed.emit(str(parsed.get("detail", "offline")) if typeof(parsed) == TYPE_DICTIONARY else "offline")
		return
	SaveManager.apply_pass_reward(parsed["reward"])
	pass_reward_claimed.emit(parsed)
	fetch_pass()


## A daily quest was claimed on the phone: the server pays pass XP (3 a day at most).
func claim_pass_quest(quest_id: String) -> void:
	await _pass_post("/pass/quest", {"device_id": _load_or_create_device_id(), "quest_id": quest_id})


## TODO(billing): send the Google Play purchase token. "dev" only works on a development
## server (PASS_DEV_UNLOCK=1).
func unlock_pass_premium(receipt: String) -> void:
	var parsed: Variant = await _pass_post("/pass/premium", {"device_id": _load_or_create_device_id(), "receipt": receipt})
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("premium"):
		pass_state = parsed
		pass_received.emit(pass_state)
	else:
		pass_claim_failed.emit("premium")


func _pass_post(path: String, body: Dictionary) -> Variant:
	while _pass_write_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		await get_tree().process_frame
	var sent := _pass_write_request.request(
		BASE_URL + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body)
	)
	if sent != OK:
		return null
	var result: Array = await _pass_write_request.request_completed
	return JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())


## Re-sends the look through the same upsert as registration (keyed by device id).
func _sync_cosmetics() -> void:
	if _cosmetics_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_cosmetics_dirty = true
		return
	var payload := {
		"device_id": _load_or_create_device_id(),
		"display_name": SaveManager.player_name,
		"cosmetics": SaveManager.get_cosmetics(),
	}
	var sent := _cosmetics_request.request(
		"%s/players" % BASE_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if sent != OK:
		return
	await _cosmetics_request.request_completed
	if _cosmetics_dirty:
		_cosmetics_dirty = false
		_sync_cosmetics()


func _make_request_node() -> HTTPRequest:
	var request := HTTPRequest.new()
	add_child(request)
	return request


func _load_or_create_device_id() -> String:
	if FileAccess.file_exists(DEVICE_ID_PATH):
		var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.READ)
		var existing_id := file.get_as_text().strip_edges()
		file.close()
		if not existing_id.is_empty():
			return existing_id

	var new_id := _generate_uuid_v4()
	var file := FileAccess.open(DEVICE_ID_PATH, FileAccess.WRITE)
	file.store_string(new_id)
	file.close()
	return new_id


func _generate_uuid_v4() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [
		hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12),
	]
