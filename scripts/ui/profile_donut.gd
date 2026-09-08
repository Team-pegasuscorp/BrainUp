extends Control
class_name ProfileDonut

## Multi-segment donut for profile win distribution.

var segments: Array = [] ## [{ratio: float, color: Color}]
var center_label: String = ""
var center_sublabel: String = ""
var track := Color(1, 1, 1, 0.08)
var line_width: float = 14.0


func set_segments(values: Array, label: String, sublabel: String = "") -> void:
	segments = values
	center_label = label
	center_sublabel = sublabel
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.38
	draw_arc(center, radius, 0.0, TAU, 64, track, line_width, true)
	var angle := -PI * 0.5
	for segment in segments:
		if typeof(segment) != TYPE_DICTIONARY:
			continue
		var ratio := clampf(float(segment.get("ratio", 0.0)), 0.0, 1.0)
		if ratio <= 0.001:
			continue
		var span := TAU * ratio
		var color: Color = segment.get("color", Color.WHITE)
		draw_arc(center, radius, angle, angle + span, 48, color, line_width, true)
		angle += span

	if center_label.is_empty() and center_sublabel.is_empty():
		return
	var font := ThemeDB.fallback_font
	if center_sublabel.is_empty():
		var font_size := 12
		var text_size := font.get_string_size(center_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		draw_string(
			font,
			center - text_size * 0.5 + Vector2(0, font_size * 0.35),
			center_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			font_size,
			Color(1, 1, 1, 0.92)
		)
		return

	var main_size := int(clampf(minf(size.x, size.y) * 0.12, 18.0, 28.0))
	var sub_size := int(clampf(minf(size.x, size.y) * 0.065, 10.0, 14.0))
	var main_sz := font.get_string_size(center_label, HORIZONTAL_ALIGNMENT_CENTER, -1, main_size)
	var sub_sz := font.get_string_size(center_sublabel, HORIZONTAL_ALIGNMENT_CENTER, -1, sub_size)
	draw_string(
		font,
		center + Vector2(-main_sz.x * 0.5, -2),
		center_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		main_size,
		Color(1, 1, 1, 0.95)
	)
	draw_string(
		font,
		center + Vector2(-sub_sz.x * 0.5, sub_size + 8),
		center_sublabel,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		sub_size,
		Color(1, 1, 1, 0.70)
	)
