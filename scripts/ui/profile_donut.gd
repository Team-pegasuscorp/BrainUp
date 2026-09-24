extends Control
class_name ProfileDonut

## Multi-segment donut for profile win distribution. Tap a slice to inspect it.

signal segment_clicked(index: int)

var segments: Array = [] ## [{ratio, color, name?, wins?, percent?, ...}]
var center_label: String = ""
var center_sublabel: String = ""
var track := Color(1, 1, 1, 0.08)
var line_width: float = 14.0
var selected_index: int = -1

## Must match `_draw` / hit-test.
const SEGMENT_GAP := 0.07 ## ~4°


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_segments(values: Array, label: String, sublabel: String = "") -> void:
	segments = values
	center_label = label
	center_sublabel = sublabel
	selected_index = -1
	queue_redraw()


func set_selected(index: int) -> void:
	selected_index = index
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var tapped := false
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tapped = true
			pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tapped = true
			pos = st.position
	if not tapped:
		return
	var idx := segment_index_at(pos)
	if idx < 0:
		return
	selected_index = idx
	queue_redraw()
	segment_clicked.emit(idx)
	accept_event()


func segment_index_at(local_pos: Vector2) -> int:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.38
	var half := line_width * 0.55
	var dist := local_pos.distance_to(center)
	if dist < radius - half or dist > radius + half:
		return -1
	var click := atan2(local_pos.y - center.y, local_pos.x - center.x)
	var angle := -PI * 0.5
	for i in range(segments.size()):
		var segment = segments[i]
		if typeof(segment) != TYPE_DICTIONARY:
			continue
		var ratio := clampf(float(segment.get("ratio", 0.0)), 0.0, 1.0)
		if ratio <= 0.001:
			continue
		var span := TAU * ratio
		var draw_span := maxf(span - SEGMENT_GAP, 0.0)
		var start := angle + SEGMENT_GAP * 0.5
		var end := start + draw_span
		if _angle_in_arc(click, start, end):
			return i
		angle += span
	return -1


func _angle_in_arc(a: float, start: float, end: float) -> bool:
	var x := a
	while x < start:
		x += TAU
	while x >= start + TAU:
		x -= TAU
	return x >= start and x <= end


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.38
	draw_arc(center, radius, 0.0, TAU, 64, track, line_width, true)
	var angle := -PI * 0.5
	for i in range(segments.size()):
		var segment = segments[i]
		if typeof(segment) != TYPE_DICTIONARY:
			continue
		var ratio := clampf(float(segment.get("ratio", 0.0)), 0.0, 1.0)
		if ratio <= 0.001:
			continue
		var span := TAU * ratio
		var draw_span := maxf(span - SEGMENT_GAP, 0.0)
		var start := angle + SEGMENT_GAP * 0.5
		var color: Color = segment.get("color", Color.WHITE)
		var width := line_width * (1.18 if i == selected_index else 1.0)
		if i == selected_index:
			color = color.lightened(0.12)
		if draw_span > 0.001:
			draw_arc(center, radius, start, start + draw_span, 48, color, width, true)
		angle += span

	if center_label.is_empty() and center_sublabel.is_empty():
		return
	var font := ThemeDB.fallback_font
	if center_sublabel.is_empty():
		var font_size := UiScale.font(12)
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

	var main_size := int(clampf(minf(size.x, size.y) * 0.18, 24.0, 36.0))
	var sub_size := int(clampf(minf(size.x, size.y) * 0.09, 12.0, 16.0))
	var main_sz := font.get_string_size(center_label, HORIZONTAL_ALIGNMENT_CENTER, -1, main_size)
	var sub_sz := font.get_string_size(center_sublabel, HORIZONTAL_ALIGNMENT_CENTER, -1, sub_size)
	draw_string(
		font,
		center + Vector2(-main_sz.x * 0.5, -4),
		center_label,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		main_size,
		Color(1, 1, 1, 0.95)
	)
	draw_string(
		font,
		center + Vector2(-sub_sz.x * 0.5, sub_size + 10),
		center_sublabel,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		sub_size,
		Color(1, 1, 1, 0.70)
	)
