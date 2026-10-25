class_name LiveData
extends RefCounted

## Names used by backend tests / filler — never show in live Social or leaderboards.
const BLOCKED_DISPLAY_NAMES: Array[String] = [
	"player",
	"bot",
	"drafta",
	"draftb",
	"shoptest",
	"passtest",
	"alpha",
	"beta",
	"ta",
	"classic",
	"survival",
	"time_attack",
]


static func show_ui_placeholders() -> bool:
	## Editor-only mock data; release builds always use server / save.
	return false


static func is_blocked_name(name: String) -> bool:
	return BLOCKED_DISPLAY_NAMES.has(name.strip_edges().to_lower())
