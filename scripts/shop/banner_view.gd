class_name BannerView
extends Panel

## Player banner drawn from a catalogue item: a horizontal gradient (2-3 colours)
## plus a light pattern. The rounded panel clips the drawing (clip_children).

const PATTERN_ALPHA := 0.16

var colors: Array[Color] = [Color(0.17, 0.14, 0.31), Color(0.29, 0.18, 0.48)]
var pattern: String = ""
var corner_radius: int = 18

var _fill: Control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_fill = Control.new()
	_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fill.draw.connect(_draw_fill)
	_fill.resized.connect(_fill.queue_redraw)
	add_child(_fill)
	_update_mask()


## Unknown / empty id gives the default banner.
func set_banner(banner_id: String) -> void:
	var item := ShopCatalog.get_item(banner_id)
	if str(item.get("kind", "")) != ShopCatalog.KIND_BANNER:
		item = ShopCatalog.get_item(ShopCatalog.default_banner_id())
	var parsed: Array[Color] = []
	for raw in item.get("colors", []):
		parsed.append(Color.html(str(raw)))
	if parsed.size() >= 2:
		colors = parsed
	pattern = str(item.get("pattern", ""))
	_fill.queue_redraw()


func set_corner_radius(radius: int) -> void:
	corner_radius = radius
	_update_mask()


func _update_mask() -> void:
	var mask := StyleBoxFlat.new()
	mask.bg_color = Color.WHITE
	mask.set_corner_radius_all(corner_radius)
	add_theme_stylebox_override("panel", mask)


func _draw_fill() -> void:
	var size_px := _fill.size
	if size_px.x < 2.0 or size_px.y < 2.0:
		return
	## Gradient: one quad per pair of colour stops.
	var stops := colors.size()
	for i in range(stops - 1):
		var x0 := size_px.x * float(i) / float(stops - 1)
		var x1 := size_px.x * float(i + 1) / float(stops - 1)
		_fill.draw_polygon(
			PackedVector2Array([Vector2(x0, 0), Vector2(x1, 0), Vector2(x1, size_px.y), Vector2(x0, size_px.y)]),
			PackedColorArray([colors[i], colors[i + 1], colors[i + 1], colors[i]])
		)
	var ink := Color(1, 1, 1, PATTERN_ALPHA)
	match pattern:
		"stripes":
			var step := 28.0
			var x := -size_px.y
			while x < size_px.x:
				_fill.draw_line(Vector2(x, size_px.y), Vector2(x + size_px.y, 0), ink, 9.0, true)
				x += step
		"dots":
			var step := 22.0
			var row := 0
			var y := step * 0.5
			while y < size_px.y:
				var x := step * (0.25 if row % 2 == 0 else 0.75)
				while x < size_px.x:
					_fill.draw_circle(Vector2(x, y), 3.0, ink)
					x += step
				y += step * 0.8
				row += 1
		"waves":
			var y := 12.0
			while y < size_px.y + 12.0:
				var points := PackedVector2Array()
				var x := 0.0
				while x <= size_px.x + 8.0:
					points.append(Vector2(x, y + sin(x / 22.0) * 6.0))
					x += 8.0
				_fill.draw_polyline(points, ink, 3.0, true)
				y += 20.0
		"chevrons":
			var y := 10.0
			while y < size_px.y + 20.0:
				var points := PackedVector2Array()
				var x := 0.0
				var up := true
				while x <= size_px.x + 18.0:
					points.append(Vector2(x, y + (0.0 if up else 10.0)))
					up = not up
					x += 18.0
				_fill.draw_polyline(points, ink, 3.0, true)
				y += 22.0
		"stars":
			## Fixed seed: the same banner always shows the same sky.
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			var count := int(size_px.x * size_px.y / 900.0)
			for i in range(count):
				var p := Vector2(rng.randf() * size_px.x, rng.randf() * size_px.y)
				var r := rng.randf_range(0.8, 2.4)
				_fill.draw_circle(p, r, Color(1, 1, 1, rng.randf_range(0.25, 0.8)))
