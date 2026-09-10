class_name UiStyle
extends RefCounted

const UiTokens = preload("res://scripts/config/ui_tokens.gd")


static func card(accent: Color = Color(0, 0, 0, 0), radius: int = -1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.CARD_BG
	style.set_border_width_all(0)
	style.set_corner_radius_all(UiTokens.CARD_RADIUS if radius < 0 else radius)
	style.shadow_color = UiTokens.CARD_SHADOW
	style.shadow_size = 14
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 16
	style.content_margin_top = 16
	style.content_margin_right = 16
	style.content_margin_bottom = 16
	if accent.a > 0.02:
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.12)
	return style


static func glass_panel(accent: Color = Color(1, 1, 1, 0.16), radius: int = -1) -> StyleBoxFlat:
	return card(accent, radius)


static func glass_strong(accent: Color = Color(1, 1, 1, 0.16), radius: int = -1) -> StyleBoxFlat:
	var style := card(accent, radius)
	style.bg_color = UiTokens.CARD_BG_SOFT
	return style


static func filled(color: Color, radius: int = 22) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(color.r, color.g, color.b, 0.32)
	style.shadow_size = 12
	style.shadow_offset = Vector2(0, 4)
	return style


static func filled_disc(color: Color, radius: int) -> StyleBoxFlat:
	var style := filled(color, radius)
	style.shadow_size = UiTokens.QUIZ_FAB_SHADOW_SIZE
	style.shadow_color = Color(color.r, color.g, color.b, 0.18)
	style.border_width_bottom = 2
	style.border_color = Color(1, 1, 1, 0.35)
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	return style


static func quiz_fab_disc(color: Color) -> StyleBoxFlat:
	var style := filled(color, UiTokens.QUIZ_FAB_CORNER_RADIUS)
	style.bg_color = Color(color.r, color.g, color.b, 1.0)
	style.shadow_size = UiTokens.QUIZ_FAB_SHADOW_SIZE
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_offset = Vector2(0, 6)
	style.set_border_width_all(0)
	style.anti_aliasing = true
	style.anti_aliasing_size = 1.0
	return style


static func glow_disc(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, UiTokens.QUIZ_FAB_GLOW_COLOR.a)
	style.set_corner_radius_all(radius)
	return style


static func chip(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.14)
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_top = 6
	style.content_margin_right = 12
	style.content_margin_bottom = 6
	return style


static func progress_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.PROFILE_MASTERY_BAR_BG
	style.set_corner_radius_all(10)
	return style


static func progress_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(10)
	return style


static func nav_dock() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.BOTTOM_NAV_BG
	style.set_border_width_all(0)
	style.set_corner_radius_all(UiTokens.BOTTOM_NAV_CORNER_RADIUS)
	style.shadow_color = UiTokens.BOTTOM_NAV_GLOW
	style.shadow_size = 16
	style.shadow_offset = Vector2(0, 4)
	return style


static func nav_pill(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.14)
	style.set_corner_radius_all(22)
	return style


static func header_bar() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.HEADER_BANNER_BG
	style.set_border_width_all(0)
	style.set_corner_radius_all(0)
	style.shadow_color = Color(0.0, 0.0, 0.04, 0.35)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	return style


static func settings_chip() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var radius := int(round(UiTokens.HEADER_SETTINGS_SIZE * 0.5))
	style.bg_color = Color(1, 1, 1, 1)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(0)
	style.shadow_color = UiTokens.CARD_SHADOW
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 0)
	return style


static func category_tile(accent: Color) -> StyleBoxFlat:
	var style := card(accent, 22)
	style.bg_color = Color(1, 1, 1, 1)
	return style


static func category_tile_selected(accent: Color) -> StyleBoxFlat:
	var style := category_tile(accent)
	style.bg_color = Color(accent.r, accent.g, accent.b, 0.12)
	style.set_border_width_all(2)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.shadow_color = Color(accent.r, accent.g, accent.b, 0.16)
	return style


static func profile_card(accent: Color = Color(0, 0, 0, 0), raised: bool = false) -> StyleBoxFlat:
	## Mock-style navy tile: soft border + colored outer glow when accented.
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.PROFILE_CARD_BG_RAISED if raised else UiTokens.PROFILE_CARD_BG
	style.set_border_width_all(1)
	style.set_corner_radius_all(UiTokens.PROFILE_CARD_RADIUS)
	style.shadow_offset = Vector2(0, 4)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	if accent.a > 0.02:
		style.border_color = Color(accent.r, accent.g, accent.b, 0.28 if raised else 0.18)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.22 if raised else 0.14)
		style.shadow_size = 14 if raised else 10
	else:
		style.border_color = UiTokens.PROFILE_CARD_BORDER
		style.shadow_color = Color(0, 0, 0, 0.30)
		style.shadow_size = 10 if raised else 6
	return style


static func profile_surface(accent: Color = Color(0, 0, 0, 0), raised: bool = false, pad: int = 16) -> StyleBoxFlat:
	## Profile navy tile with built-in padding (for Home / Social / Leaderboard).
	var style := profile_card(accent, raised)
	style.set_content_margin_all(pad)
	return style


static func social_surface(raised: bool = false, pad: int = 10) -> StyleBoxFlat:
	## Dark magenta tiles tuned to Social's pastel page wash.
	var style := profile_card(UiTokens.ACCENT_SOCIAL, raised)
	style.bg_color = UiTokens.SOCIAL_CARD_BG_RAISED if raised else UiTokens.SOCIAL_CARD_BG
	style.border_color = UiTokens.SOCIAL_CARD_BORDER
	style.shadow_color = Color(UiTokens.ACCENT_SOCIAL.r, UiTokens.ACCENT_SOCIAL.g, UiTokens.ACCENT_SOCIAL.b, 0.20)
	style.shadow_size = 12 if raised else 9
	style.set_content_margin_all(pad)
	return style


static func social_chip(accent: Color, selected: bool = false) -> StyleBoxFlat:
	## Category chips on Social dark-rose tiles.
	var style := profile_chip(accent, selected)
	if not selected:
		style.bg_color = UiTokens.SOCIAL_CARD_BG_RAISED
		style.border_color = UiTokens.SOCIAL_CARD_BORDER
	return style


static func profile_chip(accent: Color, selected: bool = false) -> StyleBoxFlat:
	## Filter / category chip on navy surfaces.
	var style := StyleBoxFlat.new()
	if selected:
		style.bg_color = Color(accent.r, accent.g, accent.b, 0.22)
		style.set_border_width_all(2)
		style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.16)
		style.shadow_size = 8
	else:
		style.bg_color = UiTokens.PROFILE_CARD_BG
		style.set_border_width_all(1)
		style.border_color = UiTokens.PROFILE_CARD_BORDER
		style.shadow_color = Color(0, 0, 0, 0.22)
		style.shadow_size = 4
	style.set_corner_radius_all(14)
	style.content_margin_left = 12
	style.content_margin_top = 6
	style.content_margin_right = 12
	style.content_margin_bottom = 6
	style.shadow_offset = Vector2(0, 2)
	return style


static func dash_tile(accent: Color = Color(0, 0, 0, 0), raised: bool = false) -> StyleBoxFlat:
	## Compact mosaic tile: raised navy fill + accent rim for peripheral coding.
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.PROFILE_CARD_BG_RAISED if raised else UiTokens.PROFILE_CARD_BG
	style.set_corner_radius_all(UiTokens.DASH_TILE_RADIUS)
	style.set_border_width_all(2)
	if accent.a > 0.02:
		style.border_color = Color(accent.r, accent.g, accent.b, 0.45)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.14)
	else:
		style.border_color = UiTokens.PROFILE_CARD_BORDER
		style.shadow_color = Color(0, 0, 0, 0.22)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 2)
	style.content_margin_left = 0
	style.content_margin_top = 0
	style.content_margin_right = 0
	style.content_margin_bottom = 0
	return style


static func profile_progress_bg() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiTokens.PROFILE_MASTERY_BAR_BG
	style.set_corner_radius_all(8)
	return style
