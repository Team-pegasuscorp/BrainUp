## First-launch account gate (Google sign-in or guest).
class_name AuthGatePolicy
extends RefCounted

## Dev: show the gate every launch so you can tweak the UI. Set false for shipping.
const FORCE_SHOW_ON_LAUNCH: bool = false

## Session flag so a single app run never stacks the popup.
static var _shown_this_session: bool = false


static func should_show_on_launch() -> bool:
	if _shown_this_session:
		return false
	if FORCE_SHOW_ON_LAUNCH:
		return true
	return SaveManager.needs_auth_choice()


static func mark_shown() -> void:
	_shown_this_session = true
