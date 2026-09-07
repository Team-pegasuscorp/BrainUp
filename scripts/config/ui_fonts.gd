## UI fonts — emoji-capable fallbacks (Godot needs CBDT/SVG emoji fonts).
class_name UiFonts
extends RefCounted

const EMOJI_FONT_PATH := "res://assets/fonts/NotoColorEmoji.ttf"

static var _emoji_font: Font


static func emoji_font() -> Font:
	if _emoji_font == null:
		if ResourceLoader.exists(EMOJI_FONT_PATH):
			_emoji_font = load(EMOJI_FONT_PATH) as Font
	return _emoji_font


## Body font + color-emoji fallback (flags, etc.). Windows Segoe COLR is unsupported by Godot.
static func text_with_emoji() -> Font:
	var body := SystemFont.new()
	body.font_names = PackedStringArray(["Segoe UI", "Arial", "sans-serif"])
	body.allow_system_fallback = true
	var emoji := emoji_font()
	if emoji != null:
		body.fallbacks = [emoji]
	return body
