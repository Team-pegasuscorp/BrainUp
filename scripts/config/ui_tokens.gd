class_name UiTokens
extends RefCounted

## Minimal Premium — light canvas, dark type, white cards, tab accents.

const FEEDBACK_TIMEOUT := Color(0.941, 0.706, 0.161, 1)
const FEEDBACK_CORRECT := Color(0.18, 0.78, 0.52, 1)
const FEEDBACK_WRONG := Color(1.0, 0.31, 0.427, 1)
const NEUTRAL := Color(1, 1, 1, 1)

const BG_CREAM := Color(0.110, 0.094, 0.188, 1)              # #1C1830 — brand navy, lighter canvas
const BG_MINT := Color(0.157, 0.133, 0.255, 1)               # #282241 — soft lift for wash
const INK := Color(0.12, 0.13, 0.15, 1)
const INK_MUTED := Color(0.55, 0.57, 0.6, 1)
const TEXT_ON_ACCENT := Color(1, 1, 1, 1)

const ACCENT_HOME := Color(0.071, 0.769, 0.722, 1)             # teal
const ACCENT_LEADERBOARD := Color(0.941, 0.706, 0.161, 1)      # gold
const ACCENT_QUIZ := Color(0.36, 0.75, 1.0, 1)                 # light blue #5CBFFF
const ACCENT_QUIZ_DEEP := Color(0.18, 0.56, 0.88, 1)           # #2E8FE0
const ACCENT_SOCIAL := Color(0.91, 0.365, 0.604, 1)            # magenta
const ACCENT_PROFILE := Color(0.42, 0.361, 1.0, 1)             # violet
const ACCENT_XP := Color(0.071, 0.769, 0.722, 1)               # cyan progress
## Brand sheet background (#010010) — header + Quiz FAB disc
const BRAND_BG := Color(0.004, 0.0, 0.063, 1)
const BRAND_BG_RAISED := Color(0.043, 0.004, 0.137, 1)        # #0B0123

## Indexed like ScenePaths.Tab: HOME, QUIZ, SOCIAL, LEADERBOARD, PROFILE
const TAB_ACCENTS: Array[Color] = [
	ACCENT_HOME,
	ACCENT_QUIZ,
	ACCENT_SOCIAL,
	ACCENT_LEADERBOARD,
	ACCENT_PROFILE,
]

const CARD_BG := Color(1, 1, 1, 1)
const CARD_BG_SOFT := Color(0.97, 0.98, 0.99, 1)
const CARD_BORDER := Color(0, 0, 0, 0)
const CARD_SHADOW := Color(0.45, 0.62, 0.78, 0.1)
const CARD_RADIUS: int = 24
const TEXT_MUTED := INK_MUTED

const BRAND_BLUE := ACCENT_HOME
const BRAND_BLUE_DARK := Color(0.086, 0.22, 0.35, 1)
const BRAND_CYAN := ACCENT_HOME
const BRAND_ORANGE := ACCENT_QUIZ

const HEADER_BANNER_BG := BRAND_BG
const HEADER_BANNER_FG := TEXT_ON_ACCENT
const HEADER_BANNER_HEIGHT: float = 112.0
const HEADER_SHELL_HEIGHT: float = 112.0
const HEADER_SHELL_MARGIN_H: int = 0
const HEADER_SHELL_MARGIN_TOP: int = 0
const HEADER_SHELL_MARGIN_BOTTOM: int = 0
const HEADER_BAR_RADIUS: int = 0
const HEADER_LOGO_SIZE: float = 80.0
const HEADER_WORDMARK_WIDTH: float = 280.0
const HEADER_WORDMARK_HEIGHT: float = 64.0
const HEADER_BRAND_SEPARATION: int = 12
const HEADER_BRAND_OFFSET_X: float = 10.0
const HEADER_TITLE_SIZE: int = 28
const HEADER_SETTINGS_SIZE: float = 64.0
const HEADER_SETTINGS_ICON_SIZE: int = 56
const HEADER_SIDE_PADDING: float = 26.0
const APP_LOGO_PATH := "res://assets/ui/logo_app.png"
const APP_WORDMARK_PATH := "res://assets/ui/brainup_wordmark.png"
const APP_SETTINGS_ICON_PATH := "res://assets/ui/icon_settings.png"

const BOTTOM_NAV_HEIGHT: float = 96.0
## Full chrome height (dock + FAB lift zone above the white pill).
const BOTTOM_NAV_TOTAL_HEIGHT: float = 188.0
## Empty band above the white dock reserved for the Quiz FAB.
const BOTTOM_NAV_FAB_CLEARANCE: float = 64.0
## Protected strip = white dock + bottom margin + a little breathing room.
const BOTTOM_NAV_SAFE_ZONE: float = BOTTOM_NAV_TOTAL_HEIGHT - BOTTOM_NAV_FAB_CLEARANCE + 15.0
const BOTTOM_NAV_CONTENT_INSET: float = BOTTOM_NAV_SAFE_ZONE
const BOTTOM_NAV_BG := Color(1, 1, 1, 1)
const BOTTOM_NAV_BORDER := Color(0, 0, 0, 0)
const BOTTOM_NAV_GLOW := Color(0.45, 0.62, 0.78, 0.12)
const BOTTOM_NAV_CORNER_RADIUS: int = 32
const BOTTOM_NAV_ICON_SIZE: int = 28
const BOTTOM_NAV_INDICATOR_HEIGHT: float = 3.0
const BOTTOM_NAV_PILL_INSET: float = 6.0
const BOTTOM_NAV_PILL_HEIGHT: float = 80.0
const BOTTOM_NAV_PILL_DURATION: float = 0.2
const SECONDARY_NAV_ICON_SIZE: int = 44
const SECONDARY_NAV_LABEL_SIZE_ACTIVE: int = 17
const SECONDARY_NAV_LABEL_SIZE_INACTIVE: int = 16
const SECONDARY_NAV_INACTIVE_ALPHA: float = 1.0
const QUIZ_FAB_SIZE: float = 128.0
const QUIZ_FAB_LIFT: float = 56.0
const QUIZ_FAB_ICON_SIZE: int = 52
const QUIZ_FAB_LABEL_SIZE: int = 17
const QUIZ_FAB_ICON_LABEL_SEPARATION: int = 4
const QUIZ_FAB_SHADOW_SIZE: int = 14
const QUIZ_FAB_GLOW_SIZE: float = 140.0
const QUIZ_FAB_RING_SIZE: float = 144.0
const QUIZ_FAB_CORNER_RADIUS: int = 64
const QUIZ_FAB_INACTIVE_ALPHA: float = 1.0
const QUIZ_FAB_PRESS_SCALE: float = 0.92
const QUIZ_FAB_PRESS_DURATION: float = 0.08
const QUIZ_FAB_GLOW_DURATION: float = 1.8
const QUIZ_FAB_BG := Color(0.004, 0.0, 0.063, 1)             # #010010 solid
const QUIZ_FAB_BG_INACTIVE := Color(0.02, 0.008, 0.08, 1)     # solid, no wash-through
const QUIZ_FAB_GLOW_COLOR := Color(1.0, 0.302, 1.0, 0.14)      # #FF4DFF soft glow
const QUIZ_FAB_GLOW_ALPHA_MIN: float = 0.10
const QUIZ_FAB_GLOW_ALPHA_MAX: float = 0.22
const TAB_SWIPE_THRESHOLD: float = 80.0
const TAB_SWIPE_DRAG_LOCK: float = 14.0
const TAB_SWIPE_DURATION: float = 0.24
const TAB_INACTIVE_COLOR := Color(0.55, 0.57, 0.6, 1)
const TAB_ACTIVE_COLOR := Color(0.12, 0.13, 0.15, 1)
const TAB_ICON_PATHS: Array[String] = [
	"res://assets/ui/icon_tab_home.svg",
	"res://assets/ui/icon_tab_quiz.png",
	"res://assets/ui/icon_tab_multiplayer.svg",
	"res://assets/ui/icon_tab_leaderboard.svg",
	"res://assets/ui/icon_tab_profile.svg",
]

const PROFILE_CARD_RADIUS: int = 16
## Dark competitive profile surface (BrainUp mock).
const PROFILE_PAGE_BG := Color(0.043, 0.043, 0.118, 1)       # #0B0B1E
const PROFILE_CARD_BG := Color(0.102, 0.102, 0.180, 1)         # #1A1A2E
const PROFILE_CARD_BG_RAISED := Color(0.125, 0.125, 0.210, 1)  # #202036
const PROFILE_CARD_BORDER := Color(1, 1, 1, 0.08)
const PROFILE_TEXT := Color(1, 1, 1, 1)
const PROFILE_TEXT_MUTED := Color(0.62, 0.66, 0.78, 1)
const PROFILE_TITLE_CAPS := Color(0.55, 0.58, 0.70, 1)
const PROFILE_STAT_ACCENT := ACCENT_PROFILE
const PROFILE_MASTERY_BAR_BG := Color(1, 1, 1, 0.08)
const PROFILE_MASTERY_BAR_FILL := ACCENT_XP
const PROFILE_BADGE_LOCKED := Color(0.55, 0.58, 0.66, 0.4)
const PROFILE_AVATAR_DISPLAY: float = 72.0
const PROFILE_AVATAR_RING := Color(1.0, 0.604, 0.0, 1)         # orange ring from mock
const PROFILE_AVATAR_SIZE: int = 256
## Mosaic dashboard tiles (bento).
const DASH_GUTTER: int = 8
const DASH_TILE_RADIUS: int = 14
const DASH_TILE_PAD: int = 10
const DASH_STAT_HEIGHT: float = 106.0
const DASH_BEST_SUBJECT_HEIGHT: float = 123.0
const DASH_WIN_SPLIT_HEIGHT: float = 175.0
## Tall enough for 6 category rows (icon 54 + gaps + header/padding).
const DASH_CATEGORY_HEIGHT: float = 455.0
## Recent matches — snug fit for 4 rows (icon 54 + gaps + header/padding).
const DASH_HISTORY_HEIGHT: float = 326.0
## Recent achievements — room for 3×2 grid at history-name text scale.
const DASH_BADGES_HEIGHT: float = 410.0
const DASH_SEASON_HEIGHT: float = 235.0
const DASH_HERO_HEIGHT: float = 225.0
const DEFAULT_PLAYER_NAME: String = "Player"
const MAX_PLAYER_NAME_LENGTH: int = 24

const ANSWER_TILE_MIN: float = 140.0
const ANSWER_TILE_MAX: float = 200.0
const BUTTON_PRESS_SCALE: float = 0.94

const PAGE_MARGIN: int = 22
const SECTION_GAP: int = 18


static func accent_for_tab(tab_id: int) -> Color:
	if tab_id < 0 or tab_id >= TAB_ACCENTS.size():
		return ACCENT_QUIZ
	return TAB_ACCENTS[tab_id]


## Softened tab tint for page canvas (Quiz keeps the brand navy wash).
static func page_bg_for_tab(tab_id: int) -> Color:
	var accent := accent_for_tab(tab_id)
	# Pull toward a light mist so accents stay recognizable but less loud.
	return accent.lerp(Color(0.94, 0.95, 0.97, 1), 0.72)


static func accent_for_category(category_id: String) -> Color:
	match category_id:
		"sport":
			return ACCENT_HOME
		"cinema":
			return ACCENT_SOCIAL
		"history":
			return ACCENT_LEADERBOARD
		"music":
			return ACCENT_QUIZ
		"geography":
			return Color(0.28, 0.72, 0.45, 1)
		"science":
			return FEEDBACK_CORRECT
		"general":
			return ACCENT_PROFILE
		"television":
			return Color(0.95, 0.48, 0.28, 1)
		_:
			return ACCENT_PROFILE
