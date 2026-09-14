class_name GameAssets
extends RefCounted

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
	if not FileAccess.file_exists(path):
		_cache[path] = null
		return null
	# New PNG/SVG assets may exist before the editor generates *.import sidecars.
	var image := Image.new()
	if image.load(path) != OK:
		_cache[path] = null
		return null
	var tex := ImageTexture.create_from_image(image)
	_cache[path] = tex
	return tex


static func category_texture(category_id: String) -> Texture2D:
	return load_texture(category_path(category_id))


static func badge_texture(achievement_id: String) -> Texture2D:
	return load_texture(badge_path(achievement_id))


static func league_texture(league_id: String) -> Texture2D:
	return load_texture(league_path(league_id))


static func demo_avatar_texture(friend_name: String) -> Texture2D:
	return load_texture(demo_avatar_path(friend_name))


static func clear_icon_slot(slot: Control) -> void:
	if slot == null:
		return
	for child in slot.get_children():
		child.queue_free()


static func fill_icon_slot(
	slot: Control,
	texture: Texture2D,
	emoji_fallback: String = "",
	font_size: int = 28,
	inset_ratio: float = 0.72
) -> void:
	if slot == null:
		return
	clear_icon_slot(slot)
	if texture != null:
		var pad := int(round(slot.custom_minimum_size.x * (1.0 - inset_ratio) * 0.5))
		pad = maxi(pad, 2)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", pad)
		margin.add_theme_constant_override("margin_right", pad)
		margin.add_theme_constant_override("margin_top", pad)
		margin.add_theme_constant_override("margin_bottom", pad)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(margin)
		var rect := TextureRect.new()
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(rect)
		return
	if emoji_fallback.is_empty():
		return
	var label := Label.new()
	label.text = emoji_fallback
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	var emoji_font := UiFonts.emoji_font()
	if emoji_font != null and not emoji_fallback.is_valid_int():
		label.add_theme_font_override("font", emoji_font)
	slot.add_child(label)


static func make_icon_slot(
	texture: Texture2D,
	emoji_fallback: String,
	size_px: float,
	font_size: int = 28,
	inset_ratio: float = 0.72
) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(size_px, size_px)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_icon_slot(slot, texture, emoji_fallback, font_size, inset_ratio)
	return slot


static func wire_demo_avatar_to_control(host: Control, friend_name: String) -> bool:
	var texture := demo_avatar_texture(friend_name)
	if texture == null:
		return false
	for child in host.get_children():
		if child is Label:
			child.visible = false
	var existing := host.get_node_or_null("DemoAvatarTex")
	if existing != null:
		existing.queue_free()
	var rect := TextureRect.new()
	rect.name = "DemoAvatarTex"
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.offset_left = 4.0
	rect.offset_top = 4.0
	rect.offset_right = -4.0
	rect.offset_bottom = -4.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(rect)
	host.move_child(rect, 0)
	return true


static func wire_demo_avatar(panel: PanelContainer, friend_name: String) -> bool:
	return wire_demo_avatar_to_control(panel, friend_name)
