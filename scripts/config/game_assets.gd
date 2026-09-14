class_name GameAssets
extends RefCounted

const UiFonts = preload("res://scripts/config/ui_fonts.gd")

static var _cache: Dictionary = {}


static func category_path(category_id: String) -> String:
	return "res://assets/categories/%s.png" % category_id


static func badge_path(achievement_id: String) -> String:
	return "res://assets/badges/%s.png" % achievement_id


static func league_path(league_id: String) -> String:
	return "res://assets/leagues/%s.png" % league_id


static func demo_avatar_path(friend_name: String) -> String:
	return "res://assets/avatars/demo/%s.png" % friend_slug(friend_name)


static func friend_slug(friend_name: String) -> String:
	var slug := friend_name.to_lower()
	slug = slug.replace("é", "e").replace("è", "e").replace("ê", "e")
	slug = slug.replace("à", "a").replace("ù", "u").replace("ô", "o").replace("î", "i")
	slug = slug.replace("ç", "c")
	return slug


static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path] as Texture2D

	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported != null:
			_cache[path] = imported
			return imported

	var fs_path := ProjectSettings.globalize_path(path)
	var candidates: PackedStringArray = [path]
	if fs_path != path and not fs_path.is_empty():
		candidates.append(fs_path)

	for try_path in candidates:
		if not FileAccess.file_exists(try_path):
			continue
		var image := Image.new()
		if image.load(try_path) != OK:
			continue
		var tex := ImageTexture.create_from_image(image)
		_cache[path] = tex
		return tex

	push_warning("GameAssets: failed to load texture %s" % path)
	return null


static func category_texture(category_id: String) -> Texture2D:
	return load_texture(category_path(category_id))


static func badge_texture(achievement_id: String) -> Texture2D:
	return load_texture(badge_path(achievement_id))


static func league_texture(league_id: String) -> Texture2D:
	return load_texture(league_path(league_id))


static func demo_avatar_texture(friend_name: String) -> Texture2D:
	return load_texture(demo_avatar_path(friend_name))


## Round PNG assets (categories, badges, avatars) — already circular on disk.
static func make_circular_icon_display(
	texture: Texture2D,
	emoji_fallback: String,
	size_px: float,
	font_size: int = 28,
	inset_ratio: float = 0.72
) -> Control:
	return make_icon_display(texture, emoji_fallback, size_px, font_size, inset_ratio)


static func make_icon_display(
	texture: Texture2D,
	emoji_fallback: String,
	size_px: float,
	font_size: int = 28,
	inset_ratio: float = 0.72
) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(size_px, size_px)
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if texture != null:
		var inner := maxf(size_px * inset_ratio, 16.0)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(inner, inner)
		icon.expand_mode = TextureRect.EXPAND_KEEP_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		icon.texture = texture
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(icon)
		return wrap

	if emoji_fallback.is_empty():
		return wrap

	var label := Label.new()
	label.text = emoji_fallback
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null and not emoji_fallback.is_valid_int():
		label.add_theme_font_override("font", emoji_font)
	wrap.add_child(label)
	return wrap


static func fill_icon_slot(
	slot: Control,
	texture: Texture2D,
	emoji_fallback: String = "",
	font_size: int = 28,
	inset_ratio: float = 0.72,
	circular: bool = false,
	_inset: float = 0.10
) -> void:
	if slot == null:
		return
	for child in slot.get_children():
		child.queue_free()
	var side := size_px_from_slot(slot)
	var display: Control
	if circular:
		display = make_circular_icon_display(texture, emoji_fallback, side, font_size)
	else:
		display = make_icon_display(texture, emoji_fallback, side, font_size, inset_ratio)
	display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	slot.add_child(display)


static func size_px_from_slot(slot: Control, fallback: float = 48.0) -> float:
	var side := slot.custom_minimum_size.x
	if side <= 0.0:
		side = slot.size.x
	if side <= 0.0:
		side = fallback
	return side


static func wire_demo_avatar_to_control(host: Control, friend_name: String) -> bool:
	var tex := demo_avatar_texture(friend_name)
	if tex == null:
		return false
	for child in host.get_children():
		if child is Label:
			child.visible = false
	var existing := host.get_node_or_null("DemoAvatarWrap")
	if existing != null:
		existing.queue_free()
	var side := size_px_from_slot(host, 56.0)
	var wrap := make_circular_icon_display(tex, "", side, 28, 0.78)
	wrap.name = "DemoAvatarWrap"
	wrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(wrap)
	host.move_child(wrap, 0)
	return true


static func wire_demo_avatar(panel: PanelContainer, friend_name: String) -> bool:
	return wire_demo_avatar_to_control(panel, friend_name)
