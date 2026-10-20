extends Node
## Android Play Games sign-in + server auth code for backend linking.
## Outside Android: always fails (no fake Google success).

signal signed_in(profile: Dictionary)
signal sign_in_failed(message: String)

const SIGN_IN_TIMEOUT_SEC := 90.0

var _busy: bool = false
var _sign_in_client: PlayGamesSignInClient = null
var _players_client: PlayGamesPlayersClient = null
var _timeout_timer: SceneTreeTimer = null
var _pending_display_name: String = ""
var _pending_player_id: String = ""


func is_busy() -> bool:
	return _busy


func sign_in() -> void:
	if _busy:
		return
	if OS.get_name() != "Android":
		sign_in_failed.emit(tr("UI_AUTH_GOOGLE_ANDROID_ONLY"))
		return
	var server_client_id := str(PlayGamesConfig.SERVER_CLIENT_ID).strip_edges()
	if server_client_id.is_empty():
		sign_in_failed.emit(tr("UI_AUTH_GOOGLE_NOT_CONFIGURED"))
		return
	if not Engine.has_singleton("GodotPlayGameServices"):
		sign_in_failed.emit(tr("UI_AUTH_GOOGLE_UNAVAILABLE"))
		return

	_busy = true
	_pending_display_name = ""
	_pending_player_id = ""
	_arm_timeout()

	## Clients connect native signals in _ready — init the plugin first.
	if GodotPlayGameServices.initialize() != GodotPlayGameServices.PlayGamesPluginError.OK:
		_fail(tr("UI_AUTH_GOOGLE_UNAVAILABLE"))
		return
	if not _ensure_clients():
		_fail(tr("UI_AUTH_GOOGLE_UNAVAILABLE"))
		return

	_sign_in_client.sign_in()


func _ensure_clients() -> bool:
	if not GodotPlayGameServices.android_plugin:
		return false
	if _sign_in_client == null:
		_sign_in_client = PlayGamesSignInClient.new()
		_sign_in_client.name = "PlayGamesSignInClient"
		add_child(_sign_in_client)
		_sign_in_client.user_authenticated.connect(_on_user_authenticated)
		_sign_in_client.server_side_access_requested.connect(_on_server_side_access_requested)
	if _players_client == null:
		_players_client = PlayGamesPlayersClient.new()
		_players_client.name = "PlayGamesPlayersClient"
		add_child(_players_client)
		_players_client.current_player_loaded.connect(_on_current_player_loaded)
	return true


func _arm_timeout() -> void:
	_disarm_timeout()
	_timeout_timer = get_tree().create_timer(SIGN_IN_TIMEOUT_SEC)
	_timeout_timer.timeout.connect(_on_sign_in_timeout, CONNECT_ONE_SHOT)


func _disarm_timeout() -> void:
	if _timeout_timer != null and is_instance_valid(_timeout_timer) and _timeout_timer.timeout.is_connected(_on_sign_in_timeout):
		_timeout_timer.timeout.disconnect(_on_sign_in_timeout)
	_timeout_timer = null


func _on_sign_in_timeout() -> void:
	if not _busy:
		return
	_fail(tr("UI_AUTH_GOOGLE_FAILED"))


func _on_user_authenticated(is_authenticated: bool) -> void:
	if not _busy:
		return
	if not is_authenticated:
		_fail(tr("UI_AUTH_GOOGLE_FAILED"))
		return
	_players_client.load_current_player(true)


func _on_current_player_loaded(player: PlayGamesPlayer) -> void:
	if not _busy:
		return
	if player == null:
		_fail(tr("UI_AUTH_GOOGLE_FAILED"))
		return
	_pending_display_name = str(player.display_name).strip_edges()
	_pending_player_id = str(player.player_id).strip_edges()
	var server_client_id := str(PlayGamesConfig.SERVER_CLIENT_ID).strip_edges()
	_sign_in_client.request_server_side_access(server_client_id, true)


func _on_server_side_access_requested(token: String) -> void:
	if not _busy:
		return
	var auth_code := str(token).strip_edges()
	if auth_code.is_empty():
		_fail(tr("UI_AUTH_GOOGLE_FAILED"))
		return
	var profile := {
		"display_name": _pending_display_name,
		"play_games_player_id": _pending_player_id,
		"server_auth_code": auth_code,
	}
	_busy = false
	_disarm_timeout()
	signed_in.emit(profile)


func _fail(message: String) -> void:
	_busy = false
	_disarm_timeout()
	sign_in_failed.emit(message)
