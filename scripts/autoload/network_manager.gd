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
signal daily_challenge_received(data: Dictionary)
signal daily_challenge_failed

## Local dev backend (docker compose in ~/Documents/quizz-backend).
## Swap this for the Hetzner domain once the backend is migrated (Phase 7).
const BASE_URL: String = "http://127.0.0.1:8000"
const DEVICE_ID_PATH: String = "user://device_id.txt"

var player_id: String = ""

var _players_request: HTTPRequest
var _leaderboard_request: HTTPRequest
var _matches_request: HTTPRequest
var _challenges_request: HTTPRequest
var _challenge_result_request: HTTPRequest
var _daily_request: HTTPRequest

var _live_socket: WebSocketPeer = null
var _live_pending_join: Variant = null


func _process(_delta: float) -> void:
	if _live_socket == null:
		return

	_live_socket.poll()
	var state := _live_socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if _live_pending_join != null:
			_live_socket.send_text(JSON.stringify(_live_pending_join))
			_live_pending_join = null
		while _live_socket != null and _live_socket.get_available_packet_count() > 0:
			_handle_live_message(_live_socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		_live_socket = null
		_live_pending_join = null
		live_error.emit("disconnected")


func start_live_matchmaking(category: String) -> void:
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

	_live_pending_join = {
		"type": "join_queue",
		"player_id": player_id,
		"category": category,
		"locale": LocaleManager.get_content_locale(),
	}


func send_live_answer(index: int, selected_index: int) -> void:
	if _live_socket == null:
		return
	_live_socket.send_text(JSON.stringify({
		"type": "answer",
		"index": index,
		"selected_index": selected_index,
	}))


func stop_live_matchmaking() -> void:
	if _live_socket != null:
		_live_socket.close()
		_live_socket = null
	_live_pending_join = null


func _handle_live_message(raw: String) -> void:
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	match str(parsed.get("type", "")):
		"match_found":
			live_match_found.emit(parsed)
		"question":
			live_question.emit(parsed)
		"reveal":
			live_reveal.emit(parsed)
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
	var payload := {"device_id": device_id, "display_name": SaveManager.player_name}
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
