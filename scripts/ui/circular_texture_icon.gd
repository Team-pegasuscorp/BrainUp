## Draws a texture (or emoji fallback) clipped to a perfect circle.
class_name CircularTextureIcon
extends Control

const UiFonts = preload("res://scripts/config/ui_fonts.gd")

var texture: Texture2D
var emoji_fallback: String = ""
var emoji_font_size: int = 28
## Trim from the outer edge, as a fraction of the radius (room for borders / glow).
var clip_inset: float = 0.10
var fill_color: Color = Color(0, 0, 0, 0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_content(tex: Texture2D, fallback: String = "", font_size: int = 28) -> void:
	texture = tex
	emoji_fallback = fallback
	emoji_font_size = font_size
	queue_redraw()


func _draw() -> void:
	var side := minf(size.x, size.y)
	if side <= 1.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var center := origin + Vector2(side, side) * 0.5
	var radius := side * 0.5 * (1.0 - clampf(clip_inset, 0.0, 0.35))

	if fill_color.a > 0.01:
		draw_circle(center, radius, fill_color)

	if texture != null:
		_draw_textured_disc(center, radius, texture)
		return

	if emoji_fallback.is_empty():
		return

	var font := UiFonts.emoji_font()
	if font == null or emoji_fallback.is_valid_int():
		font = ThemeDB.fallback_font
	draw_circle(center, radius, Color(0.12, 0.13, 0.22, 0.55))
	var icon_size := int(clampf(side * 0.42, 14.0, 40.0))
	var text_size := font.get_string_size(emoji_fallback, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size)
	var pos := Vector2(
		center.x - text_size.x * 0.5,
		center.y - text_size.y * 0.5 + font.get_ascent(icon_size)
	)
	draw_string(font, pos, emoji_fallback, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size, Color.WHITE)


func _draw_textured_disc(center: Vector2, radius: float, tex: Texture2D) -> void:
	var points := PackedVector2Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var steps := 64
	points.append(center)
	uvs.append(Vector2(0.5, 0.5))
	colors.append(Color.WHITE)
	for i in range(steps + 1):
		var angle := -PI * 0.5 + TAU * float(i) / float(steps)
		var dir := Vector2(cos(angle), sin(angle))
		points.append(center + dir * radius)
		uvs.append(Vector2(0.5, 0.5) + Vector2(dir.x, dir.y) * 0.5)
		colors.append(Color.WHITE)
	draw_polygon(points, colors, uvs, tex)
