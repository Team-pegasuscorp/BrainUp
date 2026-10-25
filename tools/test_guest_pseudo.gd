## Headless test: "continue as guest" must not erase an existing player pseudo.
##   XDG_DATA_HOME=/tmp/brainup-test-guest godot --headless --path . tools/test_guest_pseudo.tscn
extends Node


func _ready() -> void:
	var failures: Array[String] = []

	## Fresh player (default pseudo, never chosen) gets a generated guest animal.
	SaveManager.player_name = UiTokens.DEFAULT_PLAYER_NAME
	SaveManager.auth_mode = ""
	SaveManager.continue_as_guest()
	if SaveManager.auth_mode != "guest":
		failures.append("auth_mode != guest (%s)" % SaveManager.auth_mode)
	if SaveManager.player_name.is_empty() or SaveManager.player_name == UiTokens.DEFAULT_PLAYER_NAME:
		failures.append("fresh player: guest pseudo not generated (%s)" % SaveManager.player_name)

	## Returning player with a custom pseudo keeps it when choosing guest.
	SaveManager.player_name = "Arknoid"
	SaveManager.auth_mode = ""
	SaveManager.continue_as_guest()
	if SaveManager.player_name != "Arknoid":
		failures.append("existing pseudo erased: %s" % SaveManager.player_name)

	## Sign-out then guest again still keeps the pseudo.
	SaveManager.player_name = "Sylou"
	SaveManager.auth_mode = "google"
	SaveManager.sign_out()
	SaveManager.continue_as_guest()
	if SaveManager.player_name != "Sylou":
		failures.append("pseudo lost after sign_out + guest: %s" % SaveManager.player_name)

	if failures.is_empty():
		print("[test_guest_pseudo] OK")
		get_tree().quit(0)
	else:
		for failure in failures:
			printerr("[test_guest_pseudo] FAIL: %s" % failure)
		get_tree().quit(1)
