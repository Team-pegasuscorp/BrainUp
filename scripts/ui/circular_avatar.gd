## Circular avatar: texture clipped to a perfect circle (equal diameter).
class_name CircularAvatar
extends Control

## Runtime presence for social / friends list (not a decorative UI chrome).
enum Presence { HIDDEN, ONLINE, OFFLINE, AWAY }

var texture: Texture2D
## Mock-style conic ring: violet → magenta → orange (clockwise from top).
var ring_color: Color = Color(0.42, 0.36, 1.0, 1)
var ring_color_mid: Color = Color(0.91, 0.36, 0.70, 1)
var ring_color_secondary: Color = Color(1.0, 0.60, 0.0, 1)
var ring_width: float = 3.5
## Gap between photo edge and inner edge of the gradient ring.
var ring_gap: float = 2.5
var fill_color: Color = Color(0.11, 0.12, 0.22, 1)
var presence: Presence = Presence.HIDDEN
var status_online_color: Color = Color(0.2, 0.86, 0.45, 1)
var status_away_color: Color = Color(1.0, 0.72, 0.2, 1)
var status_offline_color: Color = Color(0.45, 0.48, 0.55, 1)
## Soft edit overlay (0 = hidden, 1 = fully shown). Tweened from the profile hero.
var overlay_alpha: float = 0.0
var overlay_icon: String = "✎"

## Aliases kept for older callers that set rim_*/glow_*.
var glow_color: Color:
	set(value):
		ring_color = value
	get:
		return ring_color
var rim_color: Color:
	set(value):
		ring_color_secondary = value
	get:
		return ring_color_secondary
var rim_width: float:
	set(value):
		ring_width = value
	get:
		return ring_width


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func set_avatar(tex: Texture2D) -> void:
	texture = tex
	queue_redraw()


func set_presence(value: Presence) -> void:
	presence = value
	queue_redraw()


func set_online(online: bool) -> void:
	set_presence(Presence.ONLINE if online else Presence.HIDDEN)


func set_overlay_alpha(value: float) -> void:
	overlay_alpha = clampf(value, 0.0, 1.0)
	queue_redraw()


func _status_color() -> Color:
	match presence:
		Presence.ONLINE:
			return status_online_color
		Presence.AWAY:
			return status_away_color
		Presence.OFFLINE:
			return status_offline_color
		_:
			return Color(0, 0, 0, 0)


func _ring_color_at(t: float) -> Color:
	## t in [0,1], 0 = top, clockwise. Violet → magenta → orange → violet.
	var x := fposmod(t, 1.0)
	if x < 0.33:
		return ring_color.lerp(ring_color_mid, x / 0.33)
	if x < 0.66:
		return ring_color_mid.lerp(ring_color_secondary, (x - 0.33) / 0.33)
	return ring_color_secondary.lerp(ring_color, (x - 0.66) / 0.34)


func _draw() -> void:
	## Always use the smaller side so width == height visually (true circle).
	var side := minf(size.x, size.y)
	if side <= 1.0:
		return
	var origin := (size - Vector2(side, side)) * 0.5
	var center := origin + Vector2(side, side) * 0.5
	var radius := side * 0.5
	var stroke := clampf(ring_width, 2.5, side * 0.032)
	var gap := clampf(ring_gap, 1.5, side * 0.03)
	## Photo sits inside the ring with a clear dark gutter (mock).
	var photo_radius := maxf(radius - stroke - gap - 1.0, radius * 0.78)
	var ring_radius := photo_radius + gap + stroke * 0.5

	## Soft neon bloom behind the gradient ring.
	for i in range(4):
		var glow_a := 0.18 - float(i) * 0.035
		if glow_a <= 0.03:
			break
		var glow_r := ring_radius + float(i) * 2.4
		draw_arc(
			center,
			glow_r,
			0.0,
			TAU,
			72,
			Color(ring_color.r, ring_color.g, ring_color.b, glow_a * 0.55),
			stroke + 1.5 + float(i),
			true
		)
		draw_arc(
			center,
			glow_r,
			0.0,
			TAU,
			72,
			Color(ring_color_secondary.r, ring_color_secondary.g, ring_color_secondary.b, glow_a * 0.4),
			stroke + float(i),
			true
		)

	draw_circle(center, photo_radius, fill_color)

	if texture != null:
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
			points.append(center + dir * photo_radius)
			uvs.append(Vector2(0.5, 0.5) + Vector2(dir.x, dir.y) * 0.5)
			colors.append(Color.WHITE)
		draw_polygon(points, colors, uvs, texture)

	## Circular edit overlay — fades in on hover / press.
	if overlay_alpha > 0.01:
		draw_circle(center, photo_radius, Color(0.02, 0.02, 0.08, 0.55 * overlay_alpha))
		var font := ThemeDB.fallback_font
		var icon_size := int(clampf(side * 0.28, 22.0, 40.0))
		var icon_color := Color(1, 1, 1, 0.95 * overlay_alpha)
		var text_size := font.get_string_size(overlay_icon, HORIZONTAL_ALIGNMENT_LEFT, -1, icon_size)
		var icon_pos := Vector2(
			center.x - text_size.x * 0.5,
			center.y - text_size.y * 0.5 + font.get_ascent(icon_size)
		)
		draw_string(
			font,
			icon_pos,
			overlay_icon,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			icon_size,
			icon_color
		)

	## Conic gradient ring (mock): short arc segments, start at top.
	var segments := 72
	for i in range(segments):
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var a0 := -PI * 0.5 + TAU * t0
		var a1 := -PI * 0.5 + TAU * t1
		var col := _ring_color_at((t0 + t1) * 0.5)
		draw_arc(center, ring_radius, a0, a1, 4, col, stroke, true)

	## Subtle inner highlight on the ring for a glass/neon edge.
	draw_arc(
		center,
		ring_radius - stroke * 0.22,
		0.0,
		TAU,
		80,
		Color(1, 1, 1, 0.18),
		1.1,
		true
	)

	if presence == Presence.HIDDEN:
		return
	var status_r := clampf(side * 0.095, 7.0, 12.0)
	var status_pos := center + Vector2(photo_radius * 0.72 + 4.0, photo_radius * 0.72 + 4.0)
	draw_circle(status_pos, status_r + 2.5, fill_color)
	draw_circle(status_pos, status_r + 1.2, Color(0.05, 0.06, 0.12, 1))
	draw_circle(status_pos, status_r, _status_color())
