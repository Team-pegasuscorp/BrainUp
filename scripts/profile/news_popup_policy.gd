## Launch news / patch-notes popup policy.
## Frequency rules are intentionally stubbed — product will define when to show.
class_name NewsPopupPolicy
extends RefCounted

## Session flag so a single app run never stacks the popup.
static var _shown_this_session: bool = false


## Called from AppShell on open. Replace body when frequency is decided
## (e.g. once per day, once per news id, on version bump…).
static func should_show_on_launch() -> bool:
	if _shown_this_session:
		return false
	## TODO(frequency): gate on last_seen_news_id / day / app version.
	return true


static func mark_shown() -> void:
	_shown_this_session = true
