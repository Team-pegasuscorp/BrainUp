class_name CosmeticsView
extends RefCounted

## Builders that dress a player with their cosmetics {avatar, frame, banner}
## (ids from ShopCatalog, "" = default). Used by the shop, live matches and the
## leaderboard so every screen shows the same look.

const UiTokens = preload("res://scripts/config/ui_tokens.gd")
const CircularAvatarScript = preload("res://scripts/ui/circular_avatar.gd")


## Round avatar wearing a frame. Unknown avatar ids give the default silhouette.
static func avatar(cosmetics: Dictionary, side: float) -> CircularAvatar:
	var view := CircularAvatarScript.new()
	view.custom_minimum_size = Vector2(side, side)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.fill_color = UiTokens.PROFILE_CARD_BG_RAISED
	view.ring_gap = clampf(side * 0.016, 2.0, 4.0)
	view.set_avatar(SaveManager.avatar_texture_for(str(cosmetics.get("avatar", ""))))
	ShopCatalog.apply_frame(view, str(cosmetics.get("frame", "")))
	return view


static func banner(banner_id: String, min_size: Vector2 = Vector2.ZERO, radius: int = 18) -> BannerView:
	var view := BannerView.new()
	view.custom_minimum_size = min_size
	view.set_corner_radius(radius)
	view.set_banner(banner_id)
	return view


## Vertical player card: banner background, framed avatar, name and one value line
## (score, trophies…). Used for the live face-off.
static func player_card(
	display_name: String, cosmetics: Dictionary, value_text: String, width: float, highlight: Color = Color(0, 0, 0, 0)
) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0, 0, 0, 0)
	border.set_corner_radius_all(18)
	if highlight.a > 0.02:
		border.set_border_width_all(3)
		border.border_color = highlight
	card.add_theme_stylebox_override("panel", border)

	## Slightly dimmed so white text stays readable on any banner.
	var back := banner(str(cosmetics.get("banner", "")))
	back.modulate = Color(0.82, 0.82, 0.86)
	card.add_child(back)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var avatar_box := CenterContainer.new()
	avatar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(avatar_box)
	avatar_box.add_child(avatar(cosmetics, clampf(width * 0.42, 64.0, 120.0)))

	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", UiScale.font(20))
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("outline_size", 4)
	column.add_child(name_label)

	if not value_text.is_empty():
		var value := Label.new()
		value.text = value_text
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", UiScale.font(22))
		value.add_theme_color_override("font_color", Color.WHITE)
		value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		value.add_theme_constant_override("outline_size", 4)
		column.add_child(value)
	return card


## Two player cards side by side with "VS" between them.
static func face_off(
	left_name: String, left_cosmetics: Dictionary, left_value: String,
	right_name: String, right_cosmetics: Dictionary, right_value: String,
	total_width: float, left_highlight: Color = Color(0, 0, 0, 0)
) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_width := (total_width - 56.0) * 0.5
	row.add_child(player_card(left_name, left_cosmetics, left_value, card_width, left_highlight))
	var vs := Label.new()
	vs.text = "VS"
	vs.custom_minimum_size.x = 40
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.size_flags_vertical = Control.SIZE_FILL
	vs.add_theme_font_size_override("font_size", UiScale.font(22))
	vs.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	row.add_child(vs)
	row.add_child(player_card(right_name, right_cosmetics, right_value, card_width))
	return row
