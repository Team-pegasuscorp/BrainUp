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


## Shared face-off card height so left/right (and draft/play) stay identical.
const FACE_OFF_CARD_HEIGHT := 232.0
const FACE_OFF_TITLE_FONT := 14
const FACE_OFF_VALUE_FONT := 22

## Vertical player card: banner background, framed avatar, name and one value line
## (score, trophies…). Used for the live face-off.
## The worn title under a pseudo, tinted by rarity; null when the player wears none.
static func title_label(
	cosmetics: Dictionary, font_px: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT,
	outlined: bool = false
) -> Label:
	var title_id := str(cosmetics.get("title", ""))
	var text := ShopCatalog.title_text(title_id)
	if text.is_empty():
		return null
	var label := Label.new()
	label.text = "«\u00a0%s\u00a0»" % text
	label.horizontal_alignment = align
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	## +2 so worn titles read a bit larger under the pseudo.
	label.add_theme_font_size_override("font_size", UiScale.font(font_px + 2))
	## Exact rarity tint (common grey / rare blue / epic purple / legendary gold).
	label.add_theme_color_override(
		"font_color",
		ShopCatalog.rarity_color(ShopCatalog.get_item(title_id))
	)
	if outlined:
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
		label.add_theme_constant_override("outline_size", 4)
	return label


## Invisible title stand-in so a card without a worn title keeps the same height.
static func _title_placeholder(font_px: int) -> Label:
	var label := Label.new()
	label.text = " "
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate.a = 0.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", UiScale.font(font_px + 2))
	return label


static func player_card(
	display_name: String, cosmetics: Dictionary, value_text: String, width: float,
	highlight: Color = Color(0, 0, 0, 0), height: float = FACE_OFF_CARD_HEIGHT, stretch: float = 1.0
) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(width, height)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = stretch
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	card.clip_contents = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border := StyleBoxFlat.new()
	border.bg_color = Color(0, 0, 0, 0)
	border.set_corner_radius_all(18)
	## Same border width on both sides so a highlight does not change the card size.
	border.set_border_width_all(3)
	border.border_color = highlight if highlight.a > 0.02 else Color(0, 0, 0, 0)
	card.add_theme_stylebox_override("panel", border)

	## Slightly dimmed so white text stays readable on any banner.
	var back := banner(str(cosmetics.get("banner", "")), Vector2.ZERO, 18)
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.modulate = Color(0.82, 0.82, 0.86)
	card.add_child(back)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	card.add_child(margin)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 4)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var avatar_box := CenterContainer.new()
	avatar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(avatar_box)
	var avatar_side := clampf(mini(width, height) * 0.36, 52.0, 110.0)
	avatar_box.add_child(avatar(cosmetics, avatar_side))

	var name_base := 22 if height > FACE_OFF_CARD_HEIGHT else (18 if height < FACE_OFF_CARD_HEIGHT else 20)
	var name_label := Label.new()
	name_label.text = display_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override(
		"font_size",
		UiScale.font(UiTokens.pseudo_font_size(display_name, name_base))
	)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	name_label.add_theme_constant_override("outline_size", 4)
	column.add_child(name_label)
	var title_px := FACE_OFF_TITLE_FONT + (2 if height > FACE_OFF_CARD_HEIGHT else 0)
	var title := title_label(cosmetics, title_px, HORIZONTAL_ALIGNMENT_CENTER, true)
	column.add_child(title if title != null else _title_placeholder(title_px))

	var value_px := FACE_OFF_VALUE_FONT + (4 if height > FACE_OFF_CARD_HEIGHT else (-2 if height < FACE_OFF_CARD_HEIGHT else 0))
	var chip := value_chip(value_text if not value_text.is_empty() else " ", value_px)
	column.add_child(chip)
	var value := chip.get_node("Value") as Label
	card.set_meta("value", value)
	card.set_meta("value_chip", chip)
	return card


## Dark pill for trophies / scores so they read clearly on banner art.
static func value_chip(value_text: String, font_px: int = FACE_OFF_VALUE_FONT) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = "ValueChip"
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = Color(0, 0, 0, 0.55)
	chip_style.set_corner_radius_all(16)
	chip_style.content_margin_left = 16
	chip_style.content_margin_right = 16
	chip_style.content_margin_top = 8
	chip_style.content_margin_bottom = 8
	chip_style.set_border_width_all(1)
	chip_style.border_color = Color(1, 1, 1, 0.22)
	chip.add_theme_stylebox_override("panel", chip_style)

	var value := Label.new()
	value.name = "Value"
	value.text = value_text
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", UiScale.font(font_px))
	value.add_theme_color_override("font_color", Color.WHITE)
	value.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	value.add_theme_constant_override("outline_size", 4)
	chip.add_child(value)
	return chip


## Two player cards side by side with "VS" between them.
## `winner`: "left" | "right" | "" — winner card grows, loser shrinks.
static func face_off(
	left_name: String, left_cosmetics: Dictionary, left_value: String,
	right_name: String, right_cosmetics: Dictionary, right_value: String,
	total_width: float, left_highlight: Color = Color(0, 0, 0, 0),
	right_highlight: Color = Color(0, 0, 0, 0), winner: String = ""
) -> Control:
	const WIN_H := FACE_OFF_CARD_HEIGHT * 1.22
	const LOSE_H := FACE_OFF_CARD_HEIGHT * 0.86
	const WIN_STRETCH := 1.28
	const LOSE_STRETCH := 0.82
	var left_h := FACE_OFF_CARD_HEIGHT
	var right_h := FACE_OFF_CARD_HEIGHT
	var left_stretch := 1.0
	var right_stretch := 1.0
	if winner == "left":
		left_h = WIN_H
		right_h = LOSE_H
		left_stretch = WIN_STRETCH
		right_stretch = LOSE_STRETCH
	elif winner == "right":
		left_h = LOSE_H
		right_h = WIN_H
		left_stretch = LOSE_STRETCH
		right_stretch = WIN_STRETCH
	var row_h := maxf(left_h, right_h)
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = row_h
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_width := (total_width - 56.0) * 0.5
	row.add_child(player_card(
		left_name, left_cosmetics, left_value, card_width, left_highlight, left_h, left_stretch
	))
	var vs := Label.new()
	vs.text = "VS"
	vs.custom_minimum_size = Vector2(40, row_h)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vs.add_theme_font_size_override("font_size", UiScale.font(22))
	vs.add_theme_color_override("font_color", UiTokens.PODIUM_GOLD)
	row.add_child(vs)
	row.add_child(player_card(
		right_name, right_cosmetics, right_value, card_width, right_highlight, right_h, right_stretch
	))
	return row
